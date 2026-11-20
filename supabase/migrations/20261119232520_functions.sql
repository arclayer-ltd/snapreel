-- Snapreel Pro: triggers and SQL helpers. Every function pins search_path to '' and names its schemas.
-- Only service_role (the API) may call the helpers; anon and authenticated can't.

-- A profiles row for every new auth user. Sign in with Apple puts the name (first sign-in only) in the metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(left(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '')), 80), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function public.set_updated_at() from public, anon, authenticated;

create trigger videos_updated_at before update on public.videos
  for each row execute function public.set_updated_at();
create trigger subscriptions_updated_at before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- Pro while a subscription is active or in Apple's billing grace period and not past its expiry.
create or replace function public.is_pro(uid uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = uid
      and s.status in ('active', 'in_grace')
      and (s.expires_at is null or s.expires_at > now())
  );
$$;

-- Links that count toward Free's 25: shared, not stopped, not failed, not expired.
create or replace function public.active_link_count(uid uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer from public.videos v
  where v.owner_id = uid
    and v.deleted_at is null
    and v.status <> 'failed'
    and (v.expires_at is null or v.expires_at > now());
$$;

-- Fixed-window rate limit. Returns true while the caller is under p_max hits in the current window.
create or replace function public.rate_limit_hit(p_key text, p_window_s integer, p_max integer)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  w timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_s) * p_window_s);
  n integer;
begin
  insert into private.rate_limits as r (key, window_start, hits)
  values (p_key, w, 1)
  on conflict (key, window_start) do update set hits = r.hits + 1
  returning r.hits into n;
  return n <= p_max;
end;
$$;

-- View beacons. One row per viewing session; "start" opens a new row, "progress" and "end" update the
-- session's latest row (or the given view ID). A view counts once it has 5 s watched, 75% of the length,
-- or reaches the last second. watched_s is capped by wall-clock time since the row started (at 2x speed),
-- so a beacon can't claim more than could have been watched.
create or replace function public.record_view(
  p_video_id uuid,
  p_session_id text,
  p_event text,
  p_view_id uuid,
  p_viewer_user_id uuid,
  p_viewer_name text,
  p_country text,
  p_device public.device_kind,
  p_referrer_host text,
  p_position numeric,
  p_watched integer[],
  p_duration numeric
)
returns table (view_id uuid, counted boolean, newly_counted boolean, first_for_session boolean, percent integer)
language plpgsql
set search_path = ''
as $$
declare
  v public.views%rowtype;
  dur numeric := greatest(coalesce(p_duration, 0), 0.001);
  new_bits bit(100);
  ones integer;
  elapsed numeric;
  was_counted boolean;
begin
  select coalesce(string_agg(case when i = any (coalesce(p_watched, '{}')) then '1' else '0' end, '' order by i), repeat('0', 100))::bit(100)
    into new_bits
    from generate_series(0, 99) as i;

  if p_view_id is not null then
    select * into v from public.views w
      where w.id = p_view_id and w.video_id = p_video_id and w.session_id = p_session_id
      for update;
  end if;
  if v.id is null and p_event <> 'start' then
    select * into v from public.views w
      where w.video_id = p_video_id and w.session_id = p_session_id and w.last_seen_at > now() - interval '1 hour'
      order by w.last_seen_at desc
      limit 1
      for update;
  end if;
  if v.id is null then
    insert into public.views (video_id, session_id, viewer_user_id, viewer_name, country, device, referrer_host)
    values (p_video_id, p_session_id, p_viewer_user_id, p_viewer_name, p_country, p_device, p_referrer_host)
    returning * into v;
  end if;

  was_counted := v.counted;
  v.buckets := v.buckets | new_bits;
  ones := length(replace(v.buckets::text, '0', ''));
  elapsed := extract(epoch from (now() - v.started_at));
  v.max_position_s := greatest(v.max_position_s, least(greatest(coalesce(p_position, 0), 0), dur));
  v.watched_s := greatest(v.watched_s, least(dur, ones * dur / 100, elapsed * 2 + 1));
  v.counted := v.counted or v.watched_s >= 5 or v.watched_s >= 0.75 * dur or v.max_position_s >= dur - 1;
  v.completed := v.completed or v.max_position_s >= dur - 1 or ones >= 95;

  update public.views w set
    buckets = v.buckets,
    watched_s = v.watched_s,
    max_position_s = v.max_position_s,
    counted = v.counted,
    completed = v.completed,
    last_seen_at = now(),
    viewer_user_id = coalesce(p_viewer_user_id, w.viewer_user_id),
    viewer_name = coalesce(p_viewer_name, w.viewer_name)
  where w.id = v.id;

  view_id := v.id;
  counted := v.counted;
  newly_counted := v.counted and not was_counted;
  first_for_session := newly_counted and not exists (
    select 1 from public.views w
    where w.video_id = p_video_id and w.session_id = p_session_id and w.counted and w.id <> v.id
  );
  percent := ones;
  return next;
end;
$$;

-- Per-video numbers for the owner's list: counted views, unique viewers, last view, live comments.
create or replace function public.video_stats(p_video_ids uuid[])
returns table (video_id uuid, views integer, unique_viewers integer, last_viewed_at timestamptz, comment_count integer)
language sql
stable
set search_path = ''
as $$
  select ids.id,
    (select count(*)::integer from public.views w where w.video_id = ids.id and w.counted),
    (select count(distinct w.session_id)::integer from public.views w where w.video_id = ids.id and w.counted),
    (select max(w.last_seen_at) from public.views w where w.video_id = ids.id and w.counted),
    (select count(*)::integer from public.comments c where c.video_id = ids.id and c.deleted_at is null)
  from unnest(p_video_ids) as ids (id);
$$;

revoke execute on function public.is_pro(uuid) from public, anon, authenticated;
revoke execute on function public.active_link_count(uuid) from public, anon, authenticated;
revoke execute on function public.rate_limit_hit(text, integer, integer) from public, anon, authenticated;
revoke execute on function public.record_view(uuid, text, text, uuid, uuid, text, text, public.device_kind, text, numeric, integer[], numeric) from public, anon, authenticated;
revoke execute on function public.video_stats(uuid[]) from public, anon, authenticated;

grant execute on function public.is_pro(uuid) to service_role;
grant execute on function public.active_link_count(uuid) to service_role;
grant execute on function public.rate_limit_hit(text, integer, integer) to service_role;
grant execute on function public.record_view(uuid, text, text, uuid, uuid, text, text, public.device_kind, text, numeric, integer[], numeric) to service_role;
grant execute on function public.video_stats(uuid[]) to service_role;
