begin;

create or replace function public.prevent_room_reservation_overlap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status not in ('booked', 'checked_in', 'pending_payment')
     or (
       new.status = 'pending_payment'
       and (new.hold_expires_at is null or new.hold_expires_at <= now())
     ) then
    return new;
  end if;

  perform 1
  from public.rooms r
  where r.hotel_id = new.hotel_id
    and r.number = new.room_number
  for update;

  if exists (
    select 1
    from public.reservations existing
    where existing.hotel_id = new.hotel_id
      and existing.room_number = new.room_number
      and existing.id is distinct from new.id
      and existing.status in ('booked', 'checked_in', 'pending_payment')
      and (
        existing.status != 'pending_payment'
        or existing.hold_expires_at > now()
      )
      and existing.check_in < new.check_out
      and existing.check_out > new.check_in
  ) then
    raise exception 'That room already has a booking during the selected dates.';
  end if;

  return new;
end;
$$;

drop trigger if exists reservations_prevent_room_overlap
  on public.reservations;

create trigger reservations_prevent_room_overlap
before insert or update of hotel_id, room_number, check_in, check_out,
  status, hold_expires_at
on public.reservations
for each row
execute function public.prevent_room_reservation_overlap();

notify pgrst, 'reload schema';
commit;
