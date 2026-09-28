-- Supabase Auth owns passwords. Never add password columns to public tables.
-- The Manager workflow should call a server-side Edge Function using the
-- Supabase service role to invite/create Director and Reception users.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('manager', 'director', 'reception')),
  display_name text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
on public.profiles for select
using (auth.uid() = id);

create policy "Managers can view workspace profiles"
on public.profiles for select
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'manager');

-- Do not add client insert/update policies here. The Manager account workflow
-- should validate role creation in a server-side Edge Function, then use the
-- Supabase Admin API. Passwords remain inside Supabase Auth.
