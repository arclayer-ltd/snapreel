-- Comment word filter (App Review guideline 1.2). A viewer's comment whose name or text matches the server's short
-- word list (web/lib/server/moderation.ts) is stored with held = true. Viewers never see it; the video's owner sees
-- it marked as held in the dashboard and the app, and approves it (held = false, through the API) or deletes it.
-- Additive: every existing comment stays published.
alter table public.comments add column held boolean not null default false;

comment on column public.comments.held is
  'True while a comment that matched the word filter waits for the video owner. Public reads leave held comments out; only the API (service_role) clears it.';

-- No new grants. authenticated keeps select on its own videos' comments (which now includes held) and update on
-- deleted_at only, so an owner can't approve through PostgREST; approval goes through POST /api/comments/{id}/approve.
