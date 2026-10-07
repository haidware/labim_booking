begin;

alter table public.hotels
  add column if not exists address text not null default '',
  add column if not exists city text not null default '',
  add column if not exists state text not null default '';

notify pgrst, 'reload schema';
commit;
