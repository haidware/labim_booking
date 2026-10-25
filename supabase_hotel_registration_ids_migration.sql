begin;

create table if not exists public.hotel_registration_codes (
  hotel_number integer primary key
    default nextval('public.hotels_hotel_number_seq'),
  issued_at timestamptz not null default now(),
  redeemed_at timestamptz,
  hotel_id uuid unique references public.hotels(id)
);

alter table public.hotel_registration_codes enable row level security;
revoke all on public.hotel_registration_codes from anon, authenticated;
grant select, update on public.hotel_registration_codes to service_role;
grant usage, select on sequence public.hotels_hotel_number_seq to service_role;

create or replace function public.issue_hotel_registration_id()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  issued_number integer;
begin
  insert into public.hotel_registration_codes default values
  returning hotel_number into issued_number;

  return issued_number;
end;
$$;

revoke all on function public.issue_hotel_registration_id()
  from public, anon, authenticated;
grant execute on function public.issue_hotel_registration_id()
  to service_role;

create or replace function public.register_hotel_with_code(
  p_hotel_number integer,
  p_hotel_id uuid,
  p_name text,
  p_slug text,
  p_address text,
  p_city text,
  p_state text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1
  from public.hotel_registration_codes
  where hotel_number = p_hotel_number
    and redeemed_at is null
  for update;

  if not found then
    raise exception 'Hotel ID is invalid or has already been used.';
  end if;

  if p_hotel_id = '00000000-0000-0000-0000-000000000001'::uuid
    and not exists (
      select 1 from public.profiles
      where hotel_id = p_hotel_id
    )
  then
    update public.hotels
    set hotel_number = p_hotel_number,
        name = p_name,
        slug = p_slug,
        address = p_address,
        city = p_city,
        state = p_state,
        is_active = true
    where id = p_hotel_id;

    if not found then
      insert into public.hotels (
        id, hotel_number, name, slug, address, city, state, is_active, created_at
      ) values (
        p_hotel_id, p_hotel_number, p_name, p_slug, p_address, p_city, p_state,
        true, now()
      );
    end if;
  else
    insert into public.hotels (
      id, hotel_number, name, slug, address, city, state, is_active, created_at
    ) values (
      p_hotel_id, p_hotel_number, p_name, p_slug, p_address, p_city, p_state,
      true, now()
    );
  end if;

  update public.hotel_registration_codes
  set redeemed_at = now(),
      hotel_id = p_hotel_id
  where hotel_number = p_hotel_number
    and redeemed_at is null;

  return p_hotel_id;
end;
$$;

revoke all on function public.register_hotel_with_code(
  integer, uuid, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.register_hotel_with_code(
  integer, uuid, text, text, text, text, text
) to service_role;

notify pgrst, 'reload schema';
commit;
