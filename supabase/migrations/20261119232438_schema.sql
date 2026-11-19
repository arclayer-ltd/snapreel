-- Snapreel Pro: tables, enums and indexes (docs/pro/API.md, "Database").
-- The project was created with "Grant API access to new tables automatically" off, so every grant is explicit
-- (see 20261119232452_rls.sql). anon gets nothing; public pages read through the server with the secret key.

create type public.video_kind as enum ('screen', 'camera', 'audio');
create type public.video_status as enum ('uploading', 'ready', 'failed');
create type public.video_access as enum ('link', 'password');
create type public.subscription_status as enum ('active', 'in_grace', 'expired', 'revoked');
create type public.store_environment as enum ('Production', 'Sandbox');
create type public.push_environment as enum ('production', 'sandbox');
create type public.device_kind as enum ('phone', 'tablet', 'desktop');
create type public.report_reason as enum ('spam', 'abuse', 'illegal', 'copyright', 'other');

-- One row per auth user, made by the trigger in 20261119232520_functions.sql.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  brand_color text check (brand_color ~ '^#[0-9A-Fa-f]{6}$'),
  brand_logo_path text,
  email_alerts boolean not null default true,
  created_at timestamptz not null default now()
);

-- Written only by the server (StoreKit verification and App Store Server Notifications).
create table public.subscriptions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  product_id text not null,
  original_transaction_id text not null unique,
  status public.subscription_status not null,
  expires_at timestamptz,
  environment public.store_environment not null,
  updated_at timestamptz not null default now()
);

create table public.videos (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  slug text not null unique check (slug ~ '^[0-9A-Za-z]{10}$'),
  local_id uuid not null,
  title text not null default '' check (char_length(title) <= 200),
  kind public.video_kind not null,
  duration_s numeric not null check (duration_s >= 0),
  width integer not null default 0 check (width >= 0),
  height integer not null default 0 check (height >= 0),
  size_bytes bigint not null default 0 check (size_bytes between 0 and 2147483648),
  status public.video_status not null default 'uploading',
  uploaded_bytes bigint not null default 0 check (uploaded_bytes >= 0),
  transcript jsonb,
  access public.video_access not null default 'link',
  password_hash text,
  expires_at timestamptz,
  allow_download boolean not null default false,
  allow_comments boolean not null default true,
  allow_reactions boolean not null default true,
  cta jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Set when the owner stops sharing: the files and activity are deleted at once and the row stays as a
  -- tombstone (slug only) so the link says "removed" instead of "not found". The daily cron purges it after 30 days.
  deleted_at timestamptz
);
-- One live link per phone video. A stopped link frees the local ID for a new one.
create unique index videos_owner_local_live on public.videos (owner_id, local_id) where deleted_at is null;
create index videos_owner_created on public.videos (owner_id, created_at desc);
create index videos_status_created on public.videos (status, created_at) where deleted_at is null;
create index videos_expires on public.videos (expires_at) where expires_at is not null;

-- One row per viewing session (a page load that played). Unique viewers are distinct session_id values.
create table public.views (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  session_id text not null check (char_length(session_id) <= 64),
  viewer_user_id uuid references auth.users (id) on delete set null,
  viewer_name text check (char_length(viewer_name) <= 60),
  country text check (country ~ '^[A-Z]{2}$'),
  device public.device_kind,
  referrer_host text check (char_length(referrer_host) <= 255),
  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  watched_s numeric not null default 0,
  max_position_s numeric not null default 0,
  buckets bit(100) not null default repeat('0', 100)::bit(100),
  counted boolean not null default false,
  completed boolean not null default false
);
create index views_video_session on public.views (video_id, session_id, last_seen_at desc);
create index views_video_counted on public.views (video_id) where counted;
create index views_viewer_user on public.views (viewer_user_id) where viewer_user_id is not null;

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  session_id text not null check (char_length(session_id) <= 64),
  author_user_id uuid references auth.users (id) on delete set null,
  author_name text not null check (char_length(author_name) between 1 and 60),
  body text not null check (char_length(body) between 1 and 1000),
  at_s numeric check (at_s >= 0),
  parent_id uuid references public.comments (id) on delete cascade,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index comments_video_created on public.comments (video_id, created_at);
create index comments_parent on public.comments (parent_id) where parent_id is not null;
create index comments_author_user on public.comments (author_user_id) where author_user_id is not null;

create table public.reactions (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  session_id text not null check (char_length(session_id) <= 64),
  author_user_id uuid references auth.users (id) on delete set null,
  author_name text check (char_length(author_name) <= 60),
  emoji text not null check (char_length(emoji) between 1 and 16),
  at_s numeric not null default 0 check (at_s >= 0),
  created_at timestamptz not null default now()
);
create index reactions_video_created on public.reactions (video_id, created_at);
create index reactions_author_user on public.reactions (author_user_id) where author_user_id is not null;

-- A blocked viewer can't comment or react on any of that owner's videos.
create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  session_id text check (char_length(session_id) <= 64),
  user_id uuid references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  check (session_id is not null or user_id is not null)
);
create unique index blocks_owner_session on public.blocks (owner_id, session_id) where session_id is not null;
create unique index blocks_owner_user on public.blocks (owner_id, user_id) where user_id is not null;
create index blocks_user on public.blocks (user_id) where user_id is not null;

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.videos (id) on delete cascade,
  reason public.report_reason not null,
  details text not null default '' check (char_length(details) <= 2000),
  email text check (char_length(email) <= 320),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index reports_video on public.reports (video_id);
create index reports_open on public.reports (created_at) where resolved_at is null;

-- APNs device tokens for alert pushes (topic co.arclayer.snapreel).
create table public.devices (
  token text primary key check (token ~ '^[0-9a-f]{32,400}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  environment public.push_environment not null default 'production',
  app_version text check (char_length(app_version) <= 40),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index devices_user on public.devices (user_id);

-- One alert per event: the dedupe key is unique, so a second insert for the same event fails and nothing is sent.
create table public.notification_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  video_id uuid references public.videos (id) on delete cascade,
  dedupe_key text not null unique,
  created_at timestamptz not null default now()
);
create index notification_log_user on public.notification_log (user_id);
create index notification_log_video on public.notification_log (video_id) where video_id is not null;
create index notification_log_created on public.notification_log (created_at);

-- Fixed-window counters for the public endpoints' rate limits. Not exposed through the Data API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table private.rate_limits (
  key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (key, window_start)
);
create index rate_limits_window on private.rate_limits (window_start);
