-- Snapreel Pro: grants and row-level security.
-- anon gets nothing. Owners (authenticated) may read their own rows and change only the columns that carry no
-- plan rule; everything with a plan rule (password, expiry, downloads, call-to-action, branding, status) goes
-- through the API, which runs with the secret key (service_role) and checks the plan first.

alter table public.profiles enable row level security;
alter table public.subscriptions enable row level security;
alter table public.videos enable row level security;
alter table public.views enable row level security;
alter table public.comments enable row level security;
alter table public.reactions enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.devices enable row level security;
alter table public.notification_log enable row level security;
alter table private.rate_limits enable row level security;

-- Grants. Start from nothing so a dashboard default can't leak a table to anon.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all tables in schema private from anon, authenticated;

grant usage on schema public to service_role;
grant usage on schema private to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant select, insert, update, delete on private.rate_limits to service_role;

grant select on public.profiles to authenticated;
grant update (display_name, email_alerts) on public.profiles to authenticated;

grant select on public.subscriptions to authenticated;

grant select, delete on public.videos to authenticated;
grant update (title, allow_comments, allow_reactions) on public.videos to authenticated;

grant select, delete on public.views to authenticated;
grant select, delete on public.reactions to authenticated;
grant select, delete on public.comments to authenticated;
grant update (deleted_at) on public.comments to authenticated;

grant select, delete on public.blocks to authenticated;
grant select, delete on public.devices to authenticated;
grant select on public.notification_log to authenticated;
-- public.reports: no grant to authenticated. Reports carry the reporter's email and are read only by the server.

-- Policies. (select auth.uid()) is evaluated once per statement instead of once per row.

create policy "profiles: owner reads" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles: owner updates" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "subscriptions: owner reads" on public.subscriptions
  for select to authenticated using (user_id = (select auth.uid()));

create policy "videos: owner reads" on public.videos
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "videos: owner updates" on public.videos
  for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "videos: owner deletes" on public.videos
  for delete to authenticated using (owner_id = (select auth.uid()));

create policy "views: video owner reads" on public.views
  for select to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));
create policy "views: video owner deletes" on public.views
  for delete to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));

create policy "comments: video owner reads" on public.comments
  for select to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));
create policy "comments: video owner updates" on public.comments
  for update to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));
create policy "comments: video owner deletes" on public.comments
  for delete to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));

create policy "reactions: video owner reads" on public.reactions
  for select to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));
create policy "reactions: video owner deletes" on public.reactions
  for delete to authenticated
  using (exists (select 1 from public.videos v where v.id = video_id and v.owner_id = (select auth.uid())));

create policy "blocks: owner reads" on public.blocks
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "blocks: owner deletes" on public.blocks
  for delete to authenticated using (owner_id = (select auth.uid()));

create policy "devices: owner reads" on public.devices
  for select to authenticated using (user_id = (select auth.uid()));
create policy "devices: owner deletes" on public.devices
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "notification_log: owner reads" on public.notification_log
  for select to authenticated using (user_id = (select auth.uid()));
