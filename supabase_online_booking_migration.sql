begin;

alter table public.reservations
  add column if not exists booking_source text not null default 'reception',
  add column if not exists hold_expires_at timestamptz;

alter table public.reservations
  drop constraint if exists reservations_status_check;
alter table public.reservations
  add constraint reservations_status_check
  check (status in ('booked', 'checked_in', 'checked_out', 'cancelled', 'pending_payment'));

alter table public.reservations
  drop constraint if exists reservations_booking_source_check;
alter table public.reservations
  add constraint reservations_booking_source_check
  check (booking_source in ('reception', 'online'));

create index if not exists reservations_room_stay_idx
  on public.reservations (room_number, status, check_in, check_out);
create index if not exists reservations_online_hold_idx
  on public.reservations (hold_expires_at)
  where status = 'pending_payment';

create table if not exists public.online_room_listings (
  room_number text primary key references public.rooms(number) on delete cascade,
  description text not null default '',
  photo_path text not null default '',
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.online_booking_settings (
  id boolean primary key default true check (id),
  bank_name text not null default '',
  account_name text not null default '',
  account_number text not null default '',
  reception_whatsapp text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.online_booking_settings (id)
values (true)
on conflict (id) do nothing;

alter table public.online_room_listings enable row level security;
alter table public.online_booking_settings enable row level security;

revoke all on public.online_room_listings, public.online_booking_settings from anon, authenticated;
grant select, insert, update, delete on public.online_room_listings to authenticated;
grant select, insert, update on public.online_booking_settings to authenticated;
grant all on public.online_room_listings, public.online_booking_settings to service_role;

drop policy if exists "Managers manage online room listings" on public.online_room_listings;
create policy "Managers manage online room listings" on public.online_room_listings
for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "Managers manage online booking settings" on public.online_booking_settings;
create policy "Managers manage online booking settings" on public.online_booking_settings
for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

create or replace function public.create_online_booking(
  p_guest_name text,
  p_email text,
  p_phone text,
  p_room_number text,
  p_check_in date,
  p_check_out date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rate bigint;
  v_reservation_id uuid;
begin
  if p_guest_name is null or length(trim(p_guest_name)) = 0
     or length(trim(p_guest_name)) > 160
     or p_phone is null or length(trim(p_phone)) = 0
     or length(trim(p_phone)) > 40
     or p_email is null or length(trim(p_email)) > 254
     or position('@' in p_email) < 2
     or p_room_number is null or length(trim(p_room_number)) = 0
     or p_check_in is null or p_check_out is null
     or p_check_in < current_date
     or p_check_out <= p_check_in then
    raise exception 'Invalid guest details or stay dates.';
  end if;

  select r.rate into v_rate
  from public.rooms r
  join public.online_room_listings l on l.room_number = r.number
  where r.number = p_room_number
    and l.enabled
    and r.status not in ('unavailable', 'cleaning')
  for update of r;

  if not found then
    raise exception 'That room is no longer listed or available.';
  end if;

  if exists (
    select 1 from public.reservations b
    where b.room_number = p_room_number
      and b.status in ('booked', 'checked_in', 'pending_payment')
      and (b.status != 'pending_payment' or b.hold_expires_at > now())
      and b.check_in < p_check_out
      and b.check_out > p_check_in
  ) then
    raise exception 'That room already has a booking during the selected dates.';
  end if;

  insert into public.reservations (
    guest_name, email, phone, room_number, check_in, check_out, amount,
    amount_paid, payment_method, payment_status, status, created_at,
    booking_source, hold_expires_at
  )
  values (
    trim(p_guest_name), trim(p_email), trim(p_phone), p_room_number,
    p_check_in, p_check_out, (p_check_out - p_check_in)::bigint * v_rate,
    0, 'Transfer', 'pending', 'pending_payment', now(), 'online',
    now() + interval '30 minutes'
  )
  returning id into v_reservation_id;

  return v_reservation_id;
end;
$$;

revoke all on function public.create_online_booking(text, text, text, text, date, date) from public;
grant execute on function public.create_online_booking(text, text, text, text, date, date) to anon, authenticated, service_role;

create or replace function public.confirm_online_booking(
  p_reservation_id uuid,
  p_received_by text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reservation public.reservations%rowtype;
  v_role text;
begin
  v_role := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
  if v_role != 'reception' and coalesce(auth.jwt() ->> 'role', '') != 'service_role' then
    raise exception 'Only Reception can confirm online bank transfers.';
  end if;

  select * into v_reservation
  from public.reservations
  where id = p_reservation_id
    and booking_source = 'online'
    and status = 'pending_payment'
  for update;

  if not found then
    return false;
  end if;
  if v_reservation.hold_expires_at is null
     or v_reservation.hold_expires_at <= now() then
    update public.reservations
      set status = 'cancelled', hold_expires_at = null
      where id = p_reservation_id;
    return false;
  end if;

  update public.reservations
    set status = 'booked',
        amount_paid = amount,
        payment_status = 'paid',
        hold_expires_at = null
    where id = p_reservation_id;

  if v_reservation.amount > 0 then
    insert into public.payments (
      reservation_id, room_number, amount, balance, method, received_by, created_at
    )
    values (
      v_reservation.id, v_reservation.room_number, v_reservation.amount, 0,
      'Transfer', left(trim(coalesce(p_received_by, 'Reception')), 120), now()
    );
  end if;
  return true;
end;
$$;

revoke all on function public.confirm_online_booking(uuid, text) from public, anon;
grant execute on function public.confirm_online_booking(uuid, text) to authenticated, service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('room-photos', 'room-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Managers upload room photos" on storage.objects;
create policy "Managers upload room photos" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
);

drop policy if exists "Managers update room photos" on storage.objects;
create policy "Managers update room photos" on storage.objects
for update to authenticated
using (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
)
with check (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
);

drop policy if exists "Managers delete room photos" on storage.objects;
create policy "Managers delete room photos" on storage.objects
for delete to authenticated
using (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
);

notify pgrst, 'reload schema';

commit;
