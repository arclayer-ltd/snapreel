#!/bin/bash
# The whole website on this Linux runner, with its own throwaway Supabase (database, sign-in, storage, a mail
# box) made from the repo's migrations, and made-up videos and people. Nothing real is used or reached.
# Usage: site_local.sh SOURCE_DIR WORK_DIR   (leaves WORK_DIR/links.json; the site is on http://localhost:3000)
set -euo pipefail
SRC=$(cd "$1" && pwd); mkdir -p "$2"; W=$(cd "$2" && pwd); HERE=$(cd "$(dirname "$0")" && pwd)
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}" SUPABASE_TELEMETRY_DISABLED=1 NEXT_TELEMETRY_DISABLED=1

( cd "$SRC/web" && npm ci --no-audit --no-fund > "$W/npm.log" 2>&1 ) & NPM=$!
bash "$HERE/find_artifact.sh" ui-media-small "$W/media" || echo "no sample videos stored (rig.py media makes them)"

rm -rf "$W/db" && mkdir -p "$W/db/supabase" && cp -r "$SRC/supabase/." "$W/db/supabase/"
cd "$W/db"
npm install -g --silent supabase > /dev/null 2>&1 || true
CLI="supabase"; command -v supabase > /dev/null || CLI="npx --yes supabase"
# Supabase's own projects come with this function; a local one does not, and a migration mentions it.
cat > supabase/migrations/20000101000000_rig.sql <<'SQL'
create or replace function public.rls_auto_enable() returns event_trigger language plpgsql as $$ begin end $$;
SQL
mkdir -p supabase/mail
echo '<p>Your Snapreel code is {{ .Token }}</p>' > supabase/mail/code.html
cat > supabase/config.toml <<'TOML'
project_id = "snapreel-rig"
[api]
enabled = true
port = 54321
schemas = ["public", "graphql_public"]
extra_search_path = ["public", "extensions"]
max_rows = 1000
[db]
port = 54322
[local_smtp]
enabled = true
port = 54324
[storage]
enabled = true
file_size_limit = "500MiB"
[auth]
enabled = true
site_url = "http://localhost:3000"
additional_redirect_urls = ["http://localhost:3000/**"]
enable_signup = true
[auth.email]
enable_signup = true
enable_confirmations = false
max_frequency = "1s"
otp_length = 6
otp_expiry = 600
[auth.rate_limit]
email_sent = 1000
sign_in_sign_ups = 1000
token_verifications = 1000
token_refresh = 1000
[auth.email.template.magic_link]
subject = "Your Snapreel code"
content_path = "./supabase/mail/code.html"
[auth.email.template.confirmation]
subject = "Your Snapreel code"
content_path = "./supabase/mail/code.html"
TOML
CLI="$CLI --workdir $W/db"
# Two tries: the images come from a public registry that sometimes drops a download.
$CLI start -x studio,realtime,imgproxy,edge-runtime,logflare,vector,postgres-meta,supavisor > "$W/supabase.log" 2>&1 \
  || { sleep 5; $CLI start -x studio,realtime,imgproxy,edge-runtime,logflare,vector,postgres-meta,supavisor > "$W/supabase.log" 2>&1; } \
  || { tail -30 "$W/supabase.log"; exit 1; }
$CLI status -o env > "$W/supabase.env" 2> /dev/null
set -a; . "$W/supabase.env"; set +a
wait $NPM || { tail -30 "$W/npm.log"; exit 1; }

export NEXT_PUBLIC_SUPABASE_URL="$API_URL" NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}"
export SUPABASE_SECRET_KEY="${SECRET_KEY:-$SERVICE_ROLE_KEY}" VIEWER_COOKIE_SECRET=$(openssl rand -hex 32)
export SITE_URL=http://localhost:3000
cd "$SRC/web"
npm run build > "$W/build.log" 2>&1 || { tail -40 "$W/build.log"; exit 1; }
nohup npm start -- -p 3000 > "$W/site.log" 2>&1 < /dev/null &
for _ in $(seq 1 90); do curl -sf -o /dev/null http://localhost:3000/ && break; sleep 1; done
python3 "$HERE/web_seed.py" "$W" || { tail -20 "$W/site.log"; echo "the made-up videos could not all be made; going on with what there is"; }
