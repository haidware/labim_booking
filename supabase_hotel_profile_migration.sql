begin;

alter table public.hotels
  add column if not exists description text not null default '',
  add column if not exists photo_paths jsonb not null default '[]'::jsonb;

notify pgrst, 'reload schema';

commit;
