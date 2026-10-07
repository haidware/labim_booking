begin;

alter table public.online_booking_settings
  add column if not exists reception_email text not null default '';

notify pgrst, 'reload schema';

commit;
