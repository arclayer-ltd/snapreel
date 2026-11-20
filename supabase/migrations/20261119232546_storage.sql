-- Snapreel Pro: the private "videos" bucket. Layout videos/{userId}/{videoId}/{video.mp4,poster.jpg,preview.mp4}.
-- The app uploads with TUS (6 MB chunks, x-upsert: true) using the user's token, so owners may insert, update,
-- read and delete only under their own folder. Viewers never touch storage directly: the server hands out
-- signed URLs (2 hours) after the access checks.
-- The project's global upload limit must be at least 2 GB too (Storage settings; see docs/pro/BACKEND.md).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', false, 2147483648, array['video/mp4', 'image/jpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "videos bucket: owner reads own folder" on storage.objects
  for select to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "videos bucket: owner uploads to own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "videos bucket: owner overwrites own folder" on storage.objects
  for update to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "videos bucket: owner deletes own folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = (select auth.uid())::text);
