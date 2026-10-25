begin;

create table if not exists public.whatsapp_handoff_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  reservation_id text not null,
  hotel_name text not null,
  guest_name text not null,
  message_text text not null,
  status text not null default 'handoff_requested'
    check (status = 'handoff_requested'),
  created_at timestamptz not null default now()
);

create index if not exists whatsapp_handoff_events_hotel_created_idx
  on public.whatsapp_handoff_events (hotel_id, created_at desc);

alter table public.whatsapp_handoff_events enable row level security;
revoke all on public.whatsapp_handoff_events from anon, authenticated;
grant select on public.whatsapp_handoff_events to authenticated;
grant all on public.whatsapp_handoff_events to service_role;

drop policy if exists "Directors read their hotel's WhatsApp handoffs"
  on public.whatsapp_handoff_events;
create policy "Directors read their hotel's WhatsApp handoffs"
  on public.whatsapp_handoff_events
  for select to authenticated
  using (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'director'
    and hotel_id = (
      select profiles.hotel_id
      from public.profiles
      where profiles.id = (select auth.uid())
    )
  );

commit;
