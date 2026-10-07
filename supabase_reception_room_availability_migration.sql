begin;

alter table public.online_room_listings
  add column if not exists photo_paths jsonb not null default '[]'::jsonb;

update public.online_room_listings
set photo_paths = jsonb_build_array(photo_path),
    enabled = true,
    updated_at = now()
where coalesce(photo_path, '') <> ''
  and (photo_paths is null or photo_paths = '[]'::jsonb);

create or replace function public.create_online_booking(
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
    and r.status = 'available'
    and l.enabled
    and coalesce(l.photo_path, '') <> ''
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

notify pgrst, 'reload schema';
commit;
