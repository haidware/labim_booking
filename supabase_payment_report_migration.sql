begin;

alter table public.whatsapp_handoff_events
  add column if not exists payer_account_name text not null default '',
  add column if not exists payer_account_number text not null default '',
  add column if not exists amount bigint not null default 0;

alter table public.whatsapp_handoff_events
  alter column status set default 'payment_reported';

alter table public.whatsapp_handoff_events
  drop constraint if exists whatsapp_handoff_events_status_check;
alter table public.whatsapp_handoff_events
  add constraint whatsapp_handoff_events_status_check
  check (status in ('handoff_requested', 'payment_reported'));

commit;
