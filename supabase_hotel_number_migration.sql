begin;

alter table public.hotels
  add column if not exists hotel_number integer;

create sequence if not exists public.hotels_hotel_number_seq as integer;

with existing_max as (
  select coalesce(max(hotel_number), 0) as value
  from public.hotels
),
unnumbered as (
  select
    hotels.id,
    row_number() over (order by hotels.created_at, hotels.id)
      + existing_max.value as assigned_number
  from public.hotels
  cross join existing_max
  where hotels.hotel_number is null
)
update public.hotels
set hotel_number = unnumbered.assigned_number
from unnumbered
where public.hotels.id = unnumbered.id;

select setval(
  'public.hotels_hotel_number_seq',
  greatest(coalesce(max(hotel_number), 1), 1),
  coalesce(max(hotel_number), 0) > 0
)
from public.hotels;

alter table public.hotels
  alter column hotel_number
    set default nextval('public.hotels_hotel_number_seq'),
  alter column hotel_number set not null;

alter sequence public.hotels_hotel_number_seq
  owned by public.hotels.hotel_number;

create unique index if not exists hotels_hotel_number_idx
  on public.hotels (hotel_number);

notify pgrst, 'reload schema';
commit;
