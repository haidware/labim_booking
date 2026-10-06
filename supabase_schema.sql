-- Supabase Auth owns passwords; never store them in public tables.
-- Manager account creation is performed by the Flask server with the server-only
-- Supabase secret key. Normal business requests use the signed-in user's JWT and RLS.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('manager', 'director', 'reception')),
  username text not null unique,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.rooms (
  number text primary key,
  name text not null,
  beds integer not null check (beds > 0),
  rate bigint not null check (rate >= 0),
  status text not null check (status in ('available', 'booked', 'occupied', 'cleaning', 'unavailable')),
  updated_at timestamptz not null default now()
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  guest_name text not null,
  email text not null default '',
  phone text not null,
  room_number text not null references public.rooms(number),
  check_in date not null,
  check_out date not null,
  amount bigint not null check (amount >= 0),
  amount_paid bigint not null default 0 check (amount_paid >= 0),
  payment_method text not null check (payment_method in ('Cash', 'POS', 'Transfer')),
  payment_status text not null default 'pending' check (payment_status in ('pending', 'partial', 'paid')),
  status text not null default 'checked_in' check (status in ('booked', 'checked_in', 'checked_out')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (check_out > check_in),
  check (amount_paid <= amount)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  room_number text not null references public.rooms(number),
  amount bigint not null check (amount > 0),
  balance bigint not null check (balance >= 0),
  method text not null check (method in ('Cash', 'POS', 'Transfer')),
  received_by text not null,
  created_at timestamptz not null default now()
);

create index if not exists reservations_room_number_idx on public.reservations(room_number);
create index if not exists reservations_dates_idx on public.reservations(check_in, check_out);
create index if not exists payments_reservation_id_idx on public.payments(reservation_id);

alter table public.reservations alter column status set default 'checked_in';

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.reservations enable row level security;
alter table public.payments enable row level security;

revoke all on public.profiles, public.rooms, public.reservations, public.payments from anon;
revoke all on public.profiles, public.rooms, public.reservations, public.payments from authenticated;
grant select on public.profiles, public.rooms, public.reservations, public.payments to authenticated;
grant insert, update on public.rooms to authenticated;
grant insert, update on public.reservations to authenticated;
grant insert on public.payments to authenticated;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
for select to authenticated using ((select auth.uid()) = id);

drop policy if exists "Managers read workspace profiles" on public.profiles;
create policy "Managers read workspace profiles" on public.profiles
for select to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "Hotel roles read rooms" on public.rooms;
create policy "Hotel roles read rooms" on public.rooms
for select to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'director', 'reception'));

drop policy if exists "Managers register rooms" on public.rooms;
create policy "Managers register rooms" on public.rooms
for insert to authenticated
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

drop policy if exists "Reception updates rooms" on public.rooms;
create policy "Reception updates rooms" on public.rooms
for update to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception');

drop policy if exists "Hotel roles read reservations" on public.reservations;
create policy "Hotel roles read reservations" on public.reservations
for select to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'director', 'reception'));

drop policy if exists "Reception creates reservations" on public.reservations;
create policy "Reception creates reservations" on public.reservations
for insert to authenticated with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception');

drop policy if exists "Reception updates reservations" on public.reservations;
create policy "Reception updates reservations" on public.reservations
for update to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception');

drop policy if exists "Hotel roles read payments" on public.payments;
create policy "Hotel roles read payments" on public.payments
for select to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'role') in ('manager', 'director', 'reception'));

drop policy if exists "Reception records payments" on public.payments;
create policy "Reception records payments" on public.payments
for insert to authenticated with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'reception');
