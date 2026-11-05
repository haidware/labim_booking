begin;

alter table public.online_room_listings
  add column if not exists video_path text not null default '';

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'room-photos',
  'room-photos',
  true,
  104857600,
  array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

notify pgrst, 'reload schema';

commit;
