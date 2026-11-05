begin;

update storage.buckets
set allowed_mime_types = array[
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/quicktime'
]
where id = 'room-photos';

notify pgrst, 'reload schema';

commit;
