begin;

create table if not exists public.hotels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.hotels (id, name, slug)
values ('00000000-0000-0000-0000-000000000001', 'Labim Hotel and Suite', 'labim-hotel-and-suite')
on conflict (id) do nothing;

alter table public.reservations drop constraint if exists reservations_room_number_fkey;
alter table public.reservations drop constraint if exists reservations_room_tenant_fkey;
alter table public.payments drop constraint if exists payments_room_number_fkey;
alter table public.payments drop constraint if exists payments_room_tenant_fkey;
alter table public.online_room_listings drop constraint if exists online_room_listings_room_number_fkey;
alter table public.online_room_listings drop constraint if exists online_room_listings_room_tenant_fkey;

alter table public.profiles add column if not exists hotel_id uuid;
update public.profiles set hotel_id = '00000000-0000-0000-0000-000000000001'
where hotel_id is null;
alter table public.profiles alter column hotel_id set not null;
alter table public.profiles alter column hotel_id
  set default '00000000-0000-0000-0000-000000000001';
alter table public.profiles drop constraint if exists profiles_hotel_id_fkey;
alter table public.profiles add constraint profiles_hotel_id_fkey
  foreign key (hotel_id) references public.hotels(id);
create index if not exists profiles_hotel_role_idx on public.profiles(hotel_id, role);

alter table public.rooms add column if not exists hotel_id uuid;
update public.rooms set hotel_id = '00000000-0000-0000-0000-000000000001'
where hotel_id is null;
alter table public.rooms alter column hotel_id set not null;
alter table public.rooms alter column hotel_id
  set default '00000000-0000-0000-0000-000000000001';
alter table public.rooms drop constraint if exists rooms_pkey;
alter table public.rooms add constraint rooms_pkey primary key (hotel_id, number);
alter table public.rooms drop constraint if exists rooms_hotel_id_fkey;
alter table public.rooms add constraint rooms_hotel_id_fkey
  foreign key (hotel_id) references public.hotels(id);

alter table public.reservations add column if not exists hotel_id uuid;
update public.reservations set hotel_id = '00000000-0000-0000-0000-000000000001'
where hotel_id is null;
alter table public.reservations alter column hotel_id set not null;
alter table public.reservations alter column hotel_id
  set default '00000000-0000-0000-0000-000000000001';
alter table public.reservations drop constraint if exists reservations_room_tenant_fkey;
alter table public.reservations add constraint reservations_room_tenant_fkey
  foreign key (hotel_id, room_number) references public.rooms(hotel_id, number);
create index if not exists reservations_hotel_stay_idx
  on public.reservations (hotel_id, room_number, status, check_in, check_out);

alter table public.payments add column if not exists hotel_id uuid;
update public.payments set hotel_id = '00000000-0000-0000-0000-000000000001'
where hotel_id is null;
alter table public.payments alter column hotel_id set not null;
alter table public.payments alter column hotel_id
  set default '00000000-0000-0000-0000-000000000001';
alter table public.payments drop constraint if exists payments_room_tenant_fkey;
alter table public.payments add constraint payments_room_tenant_fkey
  foreign key (hotel_id, room_number) references public.rooms(hotel_id, number);

alter table public.online_room_listings add column if not exists hotel_id uuid;
update public.online_room_listings set hotel_id = '00000000-0000-0000-0000-000000000001'
where hotel_id is null;
alter table public.online_room_listings alter column hotel_id set not null;
alter table public.online_room_listings alter column hotel_id
  set default '00000000-0000-0000-0000-000000000001';
alter table public.online_room_listings drop constraint if exists online_room_listings_pkey;
alter table public.online_room_listings add constraint online_room_listings_pkey
  primary key (hotel_id, room_number);
alter table public.online_room_listings add constraint online_room_listings_room_tenant_fkey
  foreign key (hotel_id, room_number) references public.rooms(hotel_id, number) on delete cascade;

alter table public.online_booking_settings drop constraint if exists online_booking_settings_pkey;
alter table public.online_booking_settings drop constraint if exists online_booking_settings_id_check;
alter table public.online_booking_settings alter column id drop not null;
alter table public.online_booking_settings alter column id drop default;
alter table public.online_booking_settings add column if not exists hotel_id uuid;
update public.online_booking_settings set hotel_id = '00000000-0000-0000-0000-000000000001'
where hotel_id is null;
alter table public.online_booking_settings alter column hotel_id set not null;
alter table public.online_booking_settings alter column hotel_id
  set default '00000000-0000-0000-0000-000000000001';
alter table public.online_booking_settings drop constraint if exists online_booking_settings_hotel_fkey;
alter table public.online_booking_settings add constraint online_booking_settings_pkey
  primary key (hotel_id);
alter table public.online_booking_settings add constraint online_booking_settings_hotel_fkey
  foreign key (hotel_id) references public.hotels(id) on delete cascade;

create or replace function public.current_user_hotel_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.hotel_id from public.profiles p where p.id = (select auth.uid())
$$;
revoke all on function public.current_user_hotel_id() from public, anon;
grant execute on function public.current_user_hotel_id() to authenticated, service_role;

alter table public.hotels enable row level security;
revoke all on public.hotels from anon, authenticated;
grant select on public.hotels to anon, authenticated;
grant all on public.hotels to service_role;
drop policy if exists "Public can see active hotels" on public.hotels;
create policy "Public can see active hotels" on public.hotels
for select to anon, authenticated using (is_active);

drop policy if exists "Users read own profile" on public.profiles;
drop policy if exists "Managers read workspace profiles" on public.profiles;
create policy "Users read own profile" on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or (
    hotel_id = (select public.current_user_hotel_id())
    and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
  )
);

drop policy if exists "Hotel roles read rooms" on public.rooms;
drop policy if exists "Managers register rooms" on public.rooms;
drop policy if exists "Reception updates rooms" on public.rooms;
drop policy if exists "Managers update room status" on public.rooms;
drop policy if exists "Managers delete unused rooms" on public.rooms;
drop policy if exists "Hotel roles read own rooms" on public.rooms;
drop policy if exists "Managers register own rooms" on public.rooms;
drop policy if exists "Hotel staff update own rooms" on public.rooms;
drop policy if exists "Managers delete own unused rooms" on public.rooms;
create policy "Hotel roles read own rooms" on public.rooms
for select to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'director', 'reception')
);
create policy "Managers register own rooms" on public.rooms
for insert to authenticated
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
);
create policy "Hotel staff update own rooms" on public.rooms
for update to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'reception')
)
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'reception')
);
create policy "Managers delete own unused rooms" on public.rooms
for delete to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
  and not exists (
    select 1 from public.reservations r
    where r.hotel_id = rooms.hotel_id and r.room_number = rooms.number
  )
  and not exists (
    select 1 from public.payments p
    where p.hotel_id = rooms.hotel_id and p.room_number = rooms.number
  )
);

drop policy if exists "Hotel roles read reservations" on public.reservations;
drop policy if exists "Reception creates reservations" on public.reservations;
drop policy if exists "Reception updates reservations" on public.reservations;
drop policy if exists "Managers manage reservations" on public.reservations;
drop policy if exists "Hotel roles read own reservations" on public.reservations;
drop policy if exists "Reception creates own reservations" on public.reservations;
drop policy if exists "Hotel staff updates own reservations" on public.reservations;
create policy "Hotel roles read own reservations" on public.reservations
for select to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'director', 'reception')
);
create policy "Reception creates own reservations" on public.reservations
for insert to authenticated
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception'
);
create policy "Hotel staff updates own reservations" on public.reservations
for update to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'reception')
)
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'reception')
);

drop policy if exists "Hotel roles read payments" on public.payments;
drop policy if exists "Reception records payments" on public.payments;
drop policy if exists "Hotel roles read own payments" on public.payments;
drop policy if exists "Reception records own payments" on public.payments;
create policy "Hotel roles read own payments" on public.payments
for select to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'director', 'reception')
);
create policy "Reception records own payments" on public.payments
for insert to authenticated
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception'
);

drop policy if exists "Managers manage online room listings" on public.online_room_listings;
drop policy if exists "Managers manage own online room listings" on public.online_room_listings;
create policy "Managers manage own online room listings" on public.online_room_listings
for all to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
)
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
);
drop policy if exists "Managers manage online booking settings" on public.online_booking_settings;
drop policy if exists "Managers manage own online booking settings" on public.online_booking_settings;
create policy "Managers manage own online booking settings" on public.online_booking_settings
for all to authenticated
using (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
)
with check (
  hotel_id = (select public.current_user_hotel_id())
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
);

drop policy if exists "Managers upload room photos" on storage.objects;
drop policy if exists "Managers update room photos" on storage.objects;
drop policy if exists "Managers delete room photos" on storage.objects;
drop policy if exists "Managers upload own hotel room photos" on storage.objects;
drop policy if exists "Managers update own hotel room photos" on storage.objects;
drop policy if exists "Managers delete own hotel room photos" on storage.objects;
create policy "Managers upload own hotel room photos" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
  and split_part(name, '/', 1) = (select public.current_user_hotel_id())::text
);
create policy "Managers update own hotel room photos" on storage.objects
for update to authenticated
using (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
  and split_part(name, '/', 1) = (select public.current_user_hotel_id())::text
)
with check (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
  and split_part(name, '/', 1) = (select public.current_user_hotel_id())::text
);
create policy "Managers delete own hotel room photos" on storage.objects
for delete to authenticated
using (
  bucket_id = 'room-photos'
  and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager'
  and split_part(name, '/', 1) = (select public.current_user_hotel_id())::text
);

drop function if exists public.create_online_booking(text, text, text, text, date, date);
drop function if exists public.create_online_booking(uuid, text, text, text, text, date, date);
create function public.create_online_booking(
  p_hotel_id uuid,
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
     or p_hotel_id is null
     or p_room_number is null or length(trim(p_room_number)) = 0
     or p_check_in is null or p_check_out is null
     or p_check_in < current_date
     or p_check_out <= p_check_in then
    raise exception 'Invalid guest details or stay dates.';
  end if;

  select r.rate into v_rate
  from public.rooms r
  join public.online_room_listings l
    on l.hotel_id = r.hotel_id and l.room_number = r.number
  where r.hotel_id = p_hotel_id
    and r.number = p_room_number
    and l.enabled
    and r.status not in ('unavailable', 'cleaning')
    and exists (
      select 1 from public.hotels h
      where h.id = r.hotel_id and h.is_active
    )
    and exists (
      select 1 from public.online_booking_settings s
      where s.hotel_id = r.hotel_id
        and length(trim(s.bank_name)) > 0
        and length(trim(s.account_name)) > 0
        and length(trim(s.account_number)) > 0
        and length(trim(s.reception_whatsapp)) > 0
    )
  for update of r;

  if not found then
    raise exception 'That room is no longer listed or available.';
  end if;

  if exists (
    select 1 from public.reservations b
    where b.hotel_id = p_hotel_id
      and b.room_number = p_room_number
      and b.status in ('booked', 'checked_in', 'pending_payment')
      and (b.status != 'pending_payment' or b.hold_expires_at > now())
      and b.check_in < p_check_out
      and b.check_out > p_check_in
  ) then
    raise exception 'That room already has a booking during the selected dates.';
  end if;

  insert into public.reservations (
    hotel_id, guest_name, email, phone, room_number, check_in, check_out, amount,
    amount_paid, payment_method, payment_status, status, created_at,
    booking_source, hold_expires_at
  )
  values (
    p_hotel_id, trim(p_guest_name), trim(p_email), trim(p_phone), p_room_number,
    p_check_in, p_check_out, (p_check_out - p_check_in)::bigint * v_rate,
    0, 'Transfer', 'pending', 'pending_payment', now(), 'online',
    now() + interval '30 minutes'
  )
  returning id into v_reservation_id;

  return v_reservation_id;
end;
$$;
revoke all on function public.create_online_booking(uuid, text, text, text, text, date, date) from public;
grant execute on function public.create_online_booking(uuid, text, text, text, text, date, date)
  to anon, authenticated, service_role;

create function public.create_online_booking(
  p_guest_name text,
  p_email text,
  p_phone text,
  p_room_number text,
  p_check_in date,
  p_check_out date
)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select public.create_online_booking(
    '00000000-0000-0000-0000-000000000001'::uuid,
    p_guest_name, p_email, p_phone, p_room_number, p_check_in, p_check_out
  )
$$;
revoke all on function public.create_online_booking(text, text, text, text, date, date) from public;
grant execute on function public.create_online_booking(text, text, text, text, date, date)
  to anon, authenticated, service_role;

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
    and (
      hotel_id = (select public.current_user_hotel_id())
      or coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    )
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
      hotel_id, reservation_id, room_number, amount, balance, method, received_by, created_at
    )
    values (
      v_reservation.hotel_id, v_reservation.id, v_reservation.room_number,
      v_reservation.amount, 0, 'Transfer',
      left(trim(coalesce(p_received_by, 'Reception')), 120), now()
    );
  end if;
  return true;
end;
$$;
revoke all on function public.confirm_online_booking(uuid, text) from public, anon;
grant execute on function public.confirm_online_booking(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
