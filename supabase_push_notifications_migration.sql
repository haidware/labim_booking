begin;

create table if not exists public.web_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  endpoint text not null,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  constraint web_push_subscriptions_endpoint_reservation_key
    unique (endpoint, reservation_id)
);

create index if not exists web_push_subscriptions_booking_idx
  on public.web_push_subscriptions (hotel_id, reservation_id);

alter table public.web_push_subscriptions enable row level security;
revoke all on public.web_push_subscriptions from anon, authenticated;
grant all on public.web_push_subscriptions to service_role;

commit;
