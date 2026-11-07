begin;

alter table public.shortlet_listings
  add column if not exists video_path text not null default '';

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'shortlet-videos',
  'shortlet-videos',
  true,
  104857600,
  array['video/mp4', 'video/quicktime']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

notify pgrst, 'reload schema';

commit;
