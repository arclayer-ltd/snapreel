#!/usr/bin/env bash
# Snapreel Pro end-to-end smoke test against a running deployment (production by default).
#
#   bash scripts/pro-smoke.sh                       # https://snapreel.video
#   RESOLVE_IP=76.76.21.21 bash scripts/pro-smoke.sh  # pin one Vercel IP (for BASE's host) (the owner's carrier blocks some)
#   BASE=http://localhost:3000 bash scripts/pro-smoke.sh
#   BASE=https://<preview>.vercel.app BYPASS_HEADER_FILE=<file> bash scripts/pro-smoke.sh   # a protected preview
#
# Needs curl, ffmpeg, node and web/.env.local from `vercel env pull` (NEXT_PUBLIC_SUPABASE_URL,
# NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY). Secrets are read into header files in a private temp
# folder and never printed. It makes two throwaway users at Resend's test inbox (delivered+…@resend.dev, so alert
# emails go nowhere real), runs the whole sharing flow, then deletes everything it made, even when a step fails.
# One real email goes out: the abuse report to support@snapreel.video (its details say it's a smoke test).
set -uo pipefail

BASE="${BASE:-https://snapreel.video}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/web/.env.local}"
NODE="${NODE:-node}"
TMP="$(mktemp -d)"
chmod 700 "$TMP"
RESOLVE=()
[ -n "${RESOLVE_IP:-}" ] && RESOLVE=(--resolve "${BASE#https://}:443:$RESOLVE_IP")
# A protected Vercel preview: BYPASS_HEADER_FILE holds "x-vercel-protection-bypass: <secret>". It's sent only to $BASE.
BYPASS=()
[ -n "${BYPASS_HEADER_FILE:-}" ] && BYPASS=(-H "@$BYPASS_HEADER_FILE")

envget() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
SB="$(envget NEXT_PUBLIC_SUPABASE_URL)"
PK="$(envget NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)"
[ -n "$SB" ] && [ -n "$PK" ] && [ -n "$(envget SUPABASE_SECRET_KEY)" ] || { echo "Missing Supabase values in $ENV_FILE"; exit 2; }
STORAGE="${SB/.supabase.co/.storage.supabase.co}"
printf 'apikey: %s\n' "$(envget SUPABASE_SECRET_KEY)" > "$TMP/admin.h"
printf 'apikey: %s\n' "$PK" > "$TMP/pub.h"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Safari/605.1.15"

PASS=0
FAIL=0
CODE=""
OUT=""
USERS=()
FILES=()
ok() { echo "PASS  $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $*"; FAIL=$((FAIL + 1)); }

# api METHOD URL [JSON] [extra curl args...]: sets CODE and OUT.
api() {
  local method=$1 url=$2 data=${3-}
  shift 2
  [ $# -gt 0 ] && shift
  local args=(-sS -o "$TMP/out" -w '%{http_code}' -X "$method" "${RESOLVE[@]}" -H "user-agent: ${CALL_UA:-$UA}")
  [[ "$url" == "$BASE"* ]] && args+=("${BYPASS[@]}")
  [ -n "$data" ] && args+=(-H 'content-type: application/json' --data-binary "$data")
  rm -f "$TMP/out" # a call that never connects mustn't show the answer before it (it may hold a token)
  CODE=$(curl "${args[@]}" "$@" "$url" 2>"$TMP/curl.err") || CODE="curl:$(head -c 120 "$TMP/curl.err")"
  OUT=$(cat "$TMP/out" 2>/dev/null || true)
}
# Supabase refuses secret keys from browser user agents, so admin calls identify as a script.
admin() { CALL_UA="snapreel-pro-smoke/1.0" api "$1" "$SB$2" "${3-}" -H @"$TMP/admin.h"; }
as_a() { api "$1" "$BASE$2" "${3-}" -H "authorization: Bearer $TOKEN_A"; }
as_b() { api "$1" "$BASE$2" "${3-}" -H "authorization: Bearer $TOKEN_B"; }
viewer() { api "$1" "$BASE$2" "${3-}" -b "$TMP/viewer.jar" -c "$TMP/viewer.jar"; }
# A second browser, for "Don't count my views".
viewer2() { api "$1" "$BASE$2" "${3-}" -b "$TMP/viewer2.jar" -c "$TMP/viewer2.jar"; }
# j 'expr': evaluates a JS expression over the last response as `v`.
j() { "$NODE" -e 'let v;try{v=JSON.parse(require("fs").readFileSync(0,"utf8"))}catch{v=null};const r=(()=>'"$1"')();process.stdout.write(r===undefined||r===null?"":String(r))' <<<"$OUT"; }
expect() {
  if [ "$CODE" = "$1" ]; then ok "$2 ($CODE)"; else bad "$2: got $CODE, want $1: $(head -c 300 <<<"$OUT")"; fi
}
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3: got '$1', want '$2'"; fi; }
b64() { printf %s "$1" | base64 | tr -d '\n'; }

cleanup() {
  for uid in "${USERS[@]}"; do
    [ -n "$uid" ] || continue
    if [ ${#FILES[@]} -gt 0 ]; then
      local list
      list=$(printf '"%s",' "${FILES[@]}")
      admin DELETE "/storage/v1/object/videos" "{\"prefixes\":[${list%,}]}" >/dev/null
    fi
    admin DELETE "/auth/v1/admin/users/$uid"
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

signin() { # signin EMAIL -> prints access token (user made by admin first)
  admin POST /auth/v1/admin/generate_link "{\"type\":\"magiclink\",\"email\":\"$1\"}"
  local otp
  otp=$(j 'v.email_otp || (v.properties && v.properties.email_otp)')
  api POST "$SB/auth/v1/verify" "{\"type\":\"email\",\"email\":\"$1\",\"token\":\"$otp\"}" -H @"$TMP/pub.h"
  j 'v.access_token'
}

tus_upload() { # tus_upload FILE OBJECT CONTENT_TYPE: 6 MB chunks, as the app does
  local file=$1 object=$2 type=$3 size loc offset=0 chunk=$((6 * 1024 * 1024)) n code
  size=$(wc -c <"$file" | tr -d ' ')
  loc=$(curl -sS -D - -o /dev/null -X POST "$STORAGE/storage/v1/upload/resumable" \
    -H "authorization: Bearer $TOKEN_A" -H @"$TMP/pub.h" -H "tus-resumable: 1.0.0" -H "upload-length: $size" -H "x-upsert: true" \
    -H "upload-metadata: bucketName $(b64 videos),objectName $(b64 "$object"),contentType $(b64 "$type"),cacheControl $(b64 3600)" |
    tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')
  [ -n "$loc" ] || { echo "TUS create failed for $object"; return 1; }
  FILES+=("$object")
  while [ "$offset" -lt "$size" ]; do
    n=$((size - offset < chunk ? size - offset : chunk))
    tail -c +$((offset + 1)) "$file" | head -c "$n" >"$TMP/chunk"
    # x-upsert on every PATCH too: without it a file that already exists answers 409 for ever.
    code=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "$loc" -H "authorization: Bearer $TOKEN_A" -H @"$TMP/pub.h" \
      -H "tus-resumable: 1.0.0" -H "x-upsert: true" -H "upload-offset: $offset" -H "content-type: application/offset+octet-stream" --data-binary @"$TMP/chunk")
    [ "$code" = 204 ] || { echo "TUS chunk at $offset failed: $code"; return 1; }
    offset=$((offset + n))
    CHUNKS=$((CHUNKS + 1))
  done
}

echo "== Snapreel Pro smoke test against $BASE ${RESOLVE_IP:+(pinned to $RESOLVE_IP)}"
RAND=$("$NODE" -e 'process.stdout.write(require("crypto").randomBytes(4).toString("hex"))')

# Leftovers from an earlier run that was killed before its cleanup (older than 15 minutes): delete their files
# and accounts so nothing piles up.
admin GET "/auth/v1/admin/users?per_page=1000"
for stale in $(j 'v.users.filter(u => /^delivered\+smoke-.*@resend\.dev$/.test(u.email) && Date.now() - Date.parse(u.created_at) > 15 * 60e3).map(u => u.id).join(" ")'); do
  admin POST "/storage/v1/object/list/videos" "{\"prefix\":\"$stale/\",\"limit\":100}"
  for folder in $(j 'v.map(o => o.name).join(" ")'); do
    admin POST "/storage/v1/object/list/videos" "{\"prefix\":\"$stale/$folder/\",\"limit\":100}"
    files=$(j "v.map(o => '\"$stale/$folder/' + o.name + '\"').join(',')")
    [ -n "$files" ] && admin DELETE "/storage/v1/object/videos" "{\"prefixes\":[$files]}"
  done
  admin DELETE "/auth/v1/admin/users/$stale"
  echo "      removed a leftover smoke-test user ($CODE)"
done

PROD=0
[ "$BASE" = "https://snapreel.video" ] && PROD=1
skip() { echo "SKIP  $* (only against https://snapreel.video)"; }

# --- Service checks
api GET "$BASE/api/health"
expect 200 "GET /api/health"
if [ $PROD = 1 ]; then check "$(j 'v.ok && v.configured')" "true" "health says APNs is configured"; else skip "APNs configured"; fi
api GET "$BASE/.well-known/apple-app-site-association"
expect 200 "apple-app-site-association"
check "$(j 'v.applinks.details[0].appIDs[0]')" "N3DBKUVJS5.co.arclayer.snapreel" "AASA app ID"

# --- The Send Email hook, called directly with a Standard Webhooks signature (as Supabase signs it)
HOOK_EMAIL="delivered+smoke-hook-$RAND@resend.dev"
HOOK_BODY="{\"user\":{\"id\":\"00000000-0000-4000-8000-000000000000\",\"email\":\"$HOOK_EMAIL\"},\"email_data\":{\"token\":\"123456\",\"email_action_type\":\"magiclink\"}}"
envget SUPABASE_AUTH_HOOK_SECRET | "$NODE" -e '
  const fs = require("fs"), crypto = require("crypto");
  const secret = fs.readFileSync(0, "utf8").trim().replace(/^v1,whsec_/, "");
  const [out, body] = process.argv.slice(1);
  const id = "msg_" + crypto.randomBytes(8).toString("hex"), ts = Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac("sha256", Buffer.from(secret, "base64")).update(`${id}.${ts}.${body}`).digest("base64");
  fs.writeFileSync(out, `webhook-id: ${id}\nwebhook-timestamp: ${ts}\nwebhook-signature: v1,${sig}\n`);
' "$TMP/hook.h" "$HOOK_BODY"
api POST "$BASE/api/auth/send-email" "$HOOK_BODY" -H @"$TMP/hook.h"
expect 200 "Send Email hook sends a signed code email through Resend"
api POST "$BASE/api/auth/send-email" "$HOOK_BODY" -H "webhook-id: msg_x" -H "webhook-timestamp: $(date +%s)" -H "webhook-signature: v1,AAAA"
expect 401 "Send Email hook refuses a bad signature"

# --- Sign-in email end to end (Supabase Auth -> the deployed hook -> Resend)
if [ $PROD = 1 ]; then
  OTP_EMAIL="delivered+smoke-otp-$RAND@resend.dev"
  api POST "$SB/auth/v1/otp" "{\"email\":\"$OTP_EMAIL\",\"create_user\":true}" -H @"$TMP/pub.h"
  expect 200 "POST /auth/v1/otp sends a code through the hook"
  admin POST /auth/v1/admin/generate_link "{\"type\":\"magiclink\",\"email\":\"$OTP_EMAIL\"}"
  USERS+=("$(j 'v.id || (v.user && v.user.id)')")
else
  skip "POST /auth/v1/otp through the deployed hook"
  USERS+=("")
fi

# --- Two throwaway users
EMAIL_A="delivered+smoke-a-$RAND@resend.dev"
EMAIL_B="delivered+smoke-b-$RAND@resend.dev"
admin POST /auth/v1/admin/users "{\"email\":\"$EMAIL_A\",\"email_confirm\":true,\"user_metadata\":{\"full_name\":\"Smoke Owner\"}}"
expect 200 "admin creates user A"
UID_A=$(j 'v.id')
USERS+=("$UID_A")
admin POST /auth/v1/admin/users "{\"email\":\"$EMAIL_B\",\"email_confirm\":true}"
expect 200 "admin creates user B"
UID_B=$(j 'v.id')
USERS+=("$UID_B")
TOKEN_A=$(signin "$EMAIL_A")
TOKEN_B=$(signin "$EMAIL_B")
[ -n "$TOKEN_A" ] && [ -n "$TOKEN_B" ] && ok "email-code sign-in for both users" || { bad "email-code sign-in"; exit 1; }

as_a GET /api/me
expect 200 "GET /api/me"
check "$(j 'v.plan.tier + "/" + v.usage.linkLimit + "/" + v.user.displayName')" "free/25/Smoke Owner" "Free plan, 25 links, profile name from metadata"
api GET "$BASE/api/me" "" -H "authorization: Bearer not-a-token"
expect 401 "bad bearer token is refused"

# --- Media made with ffmpeg: a noisy 1280x720 clip at 30 Mbit/s (about 8 MB) so the video needs two 6 MB TUS chunks
ffmpeg -v error -f lavfi -i "testsrc2=size=1280x720:rate=30,noise=alls=60:allf=t+u" -f lavfi -i "sine=frequency=440:sample_rate=44100" \
  -t 2 -c:v libx264 -preset ultrafast -b:v 30M -maxrate 30M -bufsize 60M -pix_fmt yuv420p -c:a aac -movflags +faststart -shortest "$TMP/video.mp4"
ffmpeg -v error -i "$TMP/video.mp4" -frames:v 1 -q:v 4 "$TMP/poster.jpg"
ffmpeg -v error -i "$TMP/video.mp4" -t 1 -an -vf scale=480:-2 -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$TMP/preview.mp4"
SIZE=$(wc -c <"$TMP/video.mp4" | tr -d ' ')
echo "      video.mp4 is $SIZE bytes"

LOCAL_ID=$("$NODE" -e 'process.stdout.write(require("crypto").randomUUID())')
CREATE="{\"localId\":\"$LOCAL_ID\",\"title\":\"Smoke test $RAND\",\"kind\":\"screen\",\"durationS\":2,\"width\":1280,\"height\":720,\"sizeBytes\":$SIZE,\"transcript\":{\"locale\":\"en-GB\",\"segments\":[{\"start\":0,\"duration\":1,\"text\":\"Hello from the smoke test\"},{\"start\":1,\"duration\":1,\"text\":\"Second line\"}]}}"

as_a POST /api/videos "{\"localId\":\"$LOCAL_ID\",\"title\":\"too long\",\"kind\":\"screen\",\"durationS\":301,\"width\":1280,\"height\":720,\"sizeBytes\":1}"
expect 402 "Free can't share a 301 s video"
check "$(j 'v.reason')" "duration" "402 reason is duration"
as_a POST /api/videos "$CREATE"
expect 201 "POST /api/videos makes the link"
VID=$(j 'v.id')
SLUG=$(j 'v.slug')
VPATH=$(j 'v.upload.videoPath')
PPATH=$(j 'v.upload.posterPath')
RPATH=$(j 'v.upload.previewPath')
check "$(j 'v.url')" "https://snapreel.video/v/$SLUG" "link URL"
check "$VPATH" "$UID_A/$VID/video.mp4" "upload path is under the user's folder"
as_a POST /api/videos "$CREATE"
expect 200 "same localId returns the existing link"
check "$(j 'v.id')" "$VID" "same video ID"

viewer GET "/api/public/v/$SLUG"
expect 200 "public link works while uploading"
check "$(j 'v.status + "/" + (v.videoUrl === null)')" "uploading/true" "no video URL before upload"
as_a PATCH "/api/videos/$VID" '{"status":"ready"}'
expect 409 "ready is refused until the files are up"

CHUNKS=0
tus_upload "$TMP/video.mp4" "$VPATH" video/mp4 && tus_upload "$TMP/poster.jpg" "$PPATH" image/jpeg &&
  tus_upload "$TMP/preview.mp4" "$RPATH" video/mp4 && ok "TUS upload of video, poster and preview ($CHUNKS chunks)" || bad "TUS upload"
# User B tries to upload into A's folder: refused at TUS create or, at the latest, on the first chunk.
EVIL=$(curl -sS -D "$TMP/evil.h" -o /dev/null -w '%{http_code}' -X POST "$STORAGE/storage/v1/upload/resumable" \
  -H "authorization: Bearer $TOKEN_B" -H @"$TMP/pub.h" -H "tus-resumable: 1.0.0" -H "upload-length: 4" \
  -H "upload-metadata: bucketName $(b64 videos),objectName $(b64 "$UID_A/$VID/evil.mp4"),contentType $(b64 video/mp4)")
if [ "$EVIL" = 201 ]; then
  EVIL_URL=$(tr -d '\r' <"$TMP/evil.h" | awk 'tolower($1)=="location:"{print $2}')
  printf 'evil' >"$TMP/evil"
  EVIL=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "$EVIL_URL" -H "authorization: Bearer $TOKEN_B" -H @"$TMP/pub.h" \
    -H "tus-resumable: 1.0.0" -H "upload-offset: 0" -H "content-type: application/offset+octet-stream" --data-binary @"$TMP/evil")
  if [ "$EVIL" != 204 ]; then ok "user B can't upload into A's folder (chunk refused: $EVIL)"; else
    bad "user B uploaded into A's folder"
    FILES+=("$UID_A/$VID/evil.mp4")
  fi
else
  ok "user B can't upload into A's folder (create refused: $EVIL)"
fi

CHUNKS=0
tus_upload "$TMP/poster.jpg" "$PPATH" image/jpeg && ok "TUS overwrites a file that is already there" || bad "TUS over an existing file"
TUS_AGAIN=$(curl -sS -o "$TMP/out" -w '%{http_code}' -X PATCH "$(curl -sS -D - -o /dev/null -X POST "$STORAGE/storage/v1/upload/resumable" \
  -H "authorization: Bearer $TOKEN_A" -H @"$TMP/pub.h" -H "tus-resumable: 1.0.0" -H "upload-length: 4" -H "x-upsert: true" \
  -H "upload-metadata: bucketName $(b64 videos),objectName $(b64 "$PPATH"),contentType $(b64 image/jpeg)" | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')" \
  -H "authorization: Bearer $TOKEN_A" -H @"$TMP/pub.h" -H "tus-resumable: 1.0.0" -H "upload-offset: 0" -H "content-type: application/offset+octet-stream" --data-binary abcd)
check "$TUS_AGAIN" "409" "TUS without x-upsert on the chunk is 409 (build 47's loop)"

# --- The app's way: S3 multipart pieces with the session token, one at a time from the end, and what can go wrong
printf %s "$TOKEN_A" >"$TMP/token_a"
printf %s "$TOKEN_B" >"$TMP/token_b"
chmod 600 "$TMP/token_a" "$TMP/token_b"
ANON=$(grep -oE 'anonKey = "[^"]+"' "$ROOT/Snapreel/Services/Cloud/CloudConfig.swift" | cut -d'"' -f2)
if S3_OUT=$(SB="$SB" ANON="$ANON" TOKEN_FILE="$(cygpath -m "$TMP/token_a" 2>/dev/null || echo "$TMP/token_a")" \
  OTHER_TOKEN_FILE="$(cygpath -m "$TMP/token_b" 2>/dev/null || echo "$TMP/token_b")" \
  "$NODE" "$ROOT/scripts/s3-upload.mjs" "$(cygpath -m "$TMP/video.mp4" 2>/dev/null || echo "$TMP/video.mp4")" "$VPATH" 3 checks 2>&1); then
  ok "S3 multipart upload over the existing video"
else
  bad "S3 multipart upload"
fi
echo "$S3_OUT" | sed 's/^/      /'
PASS=$((PASS + $(grep -c '^PASS' <<<"$S3_OUT")))
FAIL=$((FAIL + $(grep -c '^FAIL' <<<"$S3_OUT")))

# --- Upload progress (one cheap call) and what "ready" checks
as_a POST "/api/videos/$VID/progress" "{\"uploadedBytes\":1000000,\"totalBytes\":4000000}"
expect 204 "POST progress"
viewer GET "/api/public/v/$SLUG"
check "$(j 'v.uploadProgress')" "0.25" "the watch page shows it"
as_b POST "/api/videos/$VID/progress" "{\"uploadedBytes\":3000000,\"totalBytes\":4000000}"
expect 204 "B's progress call is accepted"
viewer GET "/api/public/v/$SLUG"
check "$(j 'v.uploadProgress')" "0.25" "and changes nothing of A's"
as_a POST "/api/videos/$VID/progress" "{\"uploadedBytes\":-1}"
expect 400 "negative progress is refused"
as_a PATCH "/api/videos/$VID" '{"uploadedBytes":2000000}'
expect 200 "build 47's uploadedBytes still works"
as_a PATCH "/api/videos/$VID" "{\"status\":\"ready\",\"sizeBytes\":$((SIZE + 1))}"
expect 409 "ready with another size than what is stored is refused"
check "$(j 'v.error + "/" + v.missing.join() + "/" + v.storedBytes')" "upload_incomplete/video.mp4/$SIZE" "and says which file"
# A finished upload whose "ready" call was lost: asking to upload again repairs the link instead.
as_a POST /api/videos "$CREATE"
expect 200 "asking to upload again when the video is stored"
check "$(j 'v.status')" "ready" "repairs the link"
as_a PATCH "/api/videos/$VID" '{"status":"uploading"}'
# A missing or empty preview doesn't hold the video back.
admin DELETE "/storage/v1/object/videos" "{\"prefixes\":[\"$RPATH\"]}"
as_a PATCH "/api/videos/$VID" "{\"status\":\"ready\",\"sizeBytes\":$SIZE}"
expect 200 "ready without a preview"
viewer GET "/api/public/v/$SLUG"
check "$(j 'v.status + "/" + (v.videoUrl !== null) + "/" + v.previewUrl')" "ready/true/null" "the link plays without a preview"
CHUNKS=0
tus_upload "$TMP/preview.mp4" "$RPATH" video/mp4 && ok "preview back in place" || bad "preview again"

as_a PATCH "/api/videos/$VID" '{"status":"ready","title":"Smoke test ready"}'
expect 200 "PATCH status ready (as build 47 sends it)"
check "$(j 'v.status + "/" + v.sizeBytes')" "ready/$SIZE" "ready with the stored size"

# --- Public watch flow
viewer GET "/api/public/v/$SLUG"
expect 200 "GET /api/public/v/{slug}"
check "$(j 'v.title + "/" + v.ownerName + "/" + v.showBadge + "/" + v.allowDownload')" "Smoke test ready/Smoke Owner/true/false" "public fields for a Free owner"
VIDEO_URL=$(j 'v.videoUrl')
api GET "$VIDEO_URL" "" -r 0-1023
[ "$CODE" = 206 ] || [ "$CODE" = 200 ] && ok "signed video URL streams ($CODE)" || bad "signed video URL: $CODE"
viewer GET "/api/public/v/$SLUG/captions.vtt"
expect 200 "captions.vtt"
check "$(head -1 <<<"$OUT" | tr -d '\r')" "WEBVTT" "captions are WebVTT"
api GET "$BASE/api/oembed?url=https%3A%2F%2Fsnapreel.video%2Fv%2F$SLUG&format=json"
expect 200 "oEmbed"
check "$(j 'v.type + "/" + v.provider_name')" "video/Snapreel" "oEmbed type and provider"
api GET "$BASE/api/public/v/$SLUG/poster.jpg"
expect 302 "poster.jpg redirects to a signed URL"

viewer POST "/api/public/v/$SLUG/view" '{"event":"start","positionS":0,"watched":[0,1,2,3,4,5,6,7,8,9]}'
expect 200 "view beacon: start"
VIEW_ID=$(j 'v.viewId')
[ -n "$VIEW_ID" ] && ok "start returns a viewId" || bad "no viewId"
sleep 2
viewer POST "/api/public/v/$SLUG/view" "{\"event\":\"end\",\"positionS\":2,\"viewId\":\"$VIEW_ID\",\"watched\":[$(seq -s, 10 99)]}"
expect 200 "view beacon: end"
check "$(j 'v.viewId')" "$VIEW_ID" "same view row"

# --- "Don't count my views" (cookie sr_nocount): a second browser opts out, then watches it all
viewer2 POST /api/public/view-opt-out '{"optOut":true}'
expect 200 "view opt-out"
check "$(j 'v.optOut')" "true" "opt-out answer"
grep -q $'sr_nocount\t1' "$TMP/viewer2.jar" && ok "opt-out sets sr_nocount=1" || bad "no sr_nocount cookie"
api POST "$BASE/api/public/view-opt-out" '{"optOut":true}' -H "origin: https://evil.example"
expect 403 "opt-out refuses another site's origin"
viewer2 POST "/api/public/v/$SLUG/view" "{\"event\":\"start\",\"positionS\":0,\"watched\":[$(seq -s, 0 99)]}"
expect 200 "opted-out view beacon is accepted"
check "$(j 'v.viewId')" "" "opted-out view gets no viewId"
viewer2 POST "/api/public/v/$SLUG/view" "{\"event\":\"end\",\"positionS\":2,\"watched\":[$(seq -s, 0 99)]}"
check "$(j 'v.viewId')" "" "opted-out end beacon records nothing"
grep -q $'\tsr_vs\t' "$TMP/viewer2.jar" && ok "opted-out browser keeps its sr_vs ID" || bad "opted-out browser has no sr_vs"
admin GET "/rest/v1/views?video_id=eq.$VID&select=session_id"
check "$(j 'v.length')" "1" "only the counted viewer has a view row"
viewer2 POST /api/public/view-opt-out '{"optOut":false}'
check "$(j 'v.optOut')" "false" "opt back in"
grep -q $'sr_nocount\t1' "$TMP/viewer2.jar" && bad "sr_nocount still set after opting back in" || ok "opting back in clears sr_nocount"

viewer POST "/api/public/v/$SLUG/comments" '{"name":"Smoke Viewer","body":"Nice one","atS":1,"website":""}'
expect 201 "comment"
COMMENT_ID=$(j 'v.id')
viewer POST "/api/public/v/$SLUG/comments" '{"name":"Bot","body":"spam","atS":1,"website":"http://spam.example"}'
expect 201 "honeypot comment looks accepted"
# Comment word filter (App Review 1.2): held for the owner, never shown to viewers.
viewer POST "/api/public/v/$SLUG/comments" '{"name":"Smoke Troll","body":"Smoke test: this is s h i t","atS":1,"website":""}'
expect 201 "comment matching the word filter"
check "$(j 'v.held')" "true" "it's held"
HELD_ID=$(j 'v.id')
viewer POST "/api/public/v/$SLUG/comments" "{\"name\":\"Smoke Viewer\",\"body\":\"Reply\",\"atS\":null,\"parentId\":\"$HELD_ID\",\"website\":\"\"}"
expect 400 "can't reply to a held comment"
# JSON escape for 👍: Windows mangles non-ASCII command-line arguments.
viewer POST "/api/public/v/$SLUG/reactions" '{"emoji":"\ud83d\udc4d","atS":1}'
expect 201 "reaction"
viewer POST "/api/public/v/$SLUG/reactions" '{"emoji":"not an emoji","atS":1}'
expect 400 "non-emoji reaction is refused"
viewer POST "/api/public/v/$SLUG/report" '{"reason":"other","details":"Automated smoke test (scripts/pro-smoke.sh). Please ignore.","email":null}'
expect 204 "report"
viewer GET "/api/public/v/$SLUG/activity"
expect 200 "public activity"
check "$(j 'v.comments.length + "/" + v.reactions.length')" "1/1" "one comment (honeypot not stored, held one hidden), one reaction"
check "$(j 'v.comments.some((c) => c.id === "'"$HELD_ID"'" || c.held)')" "false" "public activity leaves the held comment out"

# --- Owner views
as_a GET "/api/videos/$VID/insights"
expect 200 "insights (Free)"
check "$(j 'v.views + "/" + v.uniqueViewers + "/" + v.dropoff')" "1/1/null" "Free insights: counts only"
as_a GET /api/videos
expect 200 "GET /api/videos"
check "$(j 'v.length + "/" + v[0].views + "/" + v[0].commentCount')" "1/1/2" "list shows the view and both comments (one held)"
as_a GET "/api/videos/$VID/activity"
check "$(j 'v.comments[0] && v.comments[0].authorName')" "Smoke Viewer" "owner activity has the comment"
check "$(j '(v.comments.find((c) => c.id === "'"$HELD_ID"'") || {}).held')" "true" "owner activity has the held comment, marked held"

# --- Isolation: user B can't see or touch A's video
as_b GET "/api/videos/$VID"
expect 404 "B can't read A's video"
as_b PATCH "/api/videos/$VID" '{"title":"pwned"}'
expect 404 "B can't edit A's video"
as_b DELETE "/api/videos/$VID"
expect 404 "B can't delete A's video"
as_b DELETE "/api/comments/$COMMENT_ID"
expect 404 "B can't delete A's comments"
as_b POST "/api/comments/$HELD_ID/approve"
expect 404 "B can't approve A's held comment"

# --- The owner approves the held comment, then deletes it
as_a POST "/api/comments/$HELD_ID/approve"
expect 200 "owner approves the held comment"
check "$(j 'v.id + "/" + v.held')" "$HELD_ID/false" "approved comment is no longer held"
viewer GET "/api/public/v/$SLUG/activity"
check "$(j 'v.comments.some((c) => c.id === "'"$HELD_ID"'")')" "true" "approved comment is public"
as_a DELETE "/api/comments/$HELD_ID"
expect 204 "owner deletes the approved comment"

# --- Pro features: refused on Free, then granted (as App Store verification would) and used
as_a PATCH "/api/videos/$VID" '{"access":"password","password":"open sesame"}'
expect 402 "password is a Pro feature"
check "$(j 'v.reason')" "pro_feature" "402 reason is pro_feature"
admin POST /rest/v1/subscriptions "{\"user_id\":\"$UID_A\",\"product_id\":\"co.arclayer.snapreel.pro.yearly\",\"original_transaction_id\":\"smoke-$RAND\",\"status\":\"active\",\"expires_at\":\"$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%SZ)\",\"environment\":\"Sandbox\"}" -H "prefer: return=minimal"
expect 201 "grant Pro (test subscription row)"
as_a GET /api/me
check "$(j 'v.plan.tier + "/" + v.usage.linkLimit')" "pro/null" "plan is Pro, unlimited links"
as_a GET "/api/videos/$VID/insights"
check "$(j 'v.dropoff.length + "/" + v.avgPercent + "/" + (v.viewers[0] && v.viewers[0].name)')" "100/100/Smoke Viewer" "Pro insights: drop-off, average, named viewer"
as_a PATCH "/api/videos/$VID" '{"access":"password","password":"open sesame","allowDownload":true,"cta":{"label":"Book a call","url":"https://snapreel.video"}}'
expect 200 "Pro sets password, downloads and CTA"
check "$(j 'v.hasPassword + "/" + v.allowDownload + "/" + v.cta.label')" "true/true/Book a call" "settings saved"
viewer GET "/api/public/v/$SLUG"
expect 401 "password link without unlock"
check "$(j 'v.error')" "password" "error is password"
viewer POST "/api/public/v/$SLUG/unlock" '{"password":"wrong"}'
expect 401 "wrong password"
viewer POST "/api/public/v/$SLUG/unlock" '{"password":"open sesame"}'
expect 204 "right password sets the unlock cookie"
viewer GET "/api/public/v/$SLUG"
expect 200 "unlocked link plays"
check "$(j 'v.showBadge + "/" + v.allowDownload + "/" + v.cta.url')" "false/true/https://snapreel.video" "Pro: no badge, downloads, CTA"
as_a PATCH "/api/videos/$VID" "{\"expiresAt\":\"$(date -u -d '-1 minute' +%Y-%m-%dT%H:%M:%SZ)\"}"
expect 200 "set an expiry in the past"
viewer GET "/api/public/v/$SLUG"
expect 410 "expired link"
check "$(j 'v.error')" "expired" "error is expired"
as_a PATCH "/api/videos/$VID" '{"expiresAt":null,"access":"link"}'
expect 200 "clear expiry and password"

# --- Moderation: block the commenter, delete the comment
as_a POST /api/blocks "{\"commentId\":\"$COMMENT_ID\"}"
expect 204 "block the commenter"
viewer POST "/api/public/v/$SLUG/comments" '{"name":"Smoke Viewer","body":"Again","atS":1,"website":""}'
expect 403 "blocked viewer can't comment"
as_a DELETE "/api/comments/$COMMENT_ID"
expect 204 "owner deletes the comment"
viewer GET "/api/public/v/$SLUG/activity"
check "$(j 'v.comments.length')" "0" "deleted comment is gone"

# --- Devices, purchases, Apple notifications
as_a POST /api/devices "{\"token\":\"$(printf 'ab%.0s' $(seq 1 32))\",\"environment\":\"production\",\"appVersion\":\"smoke\"}"
expect 204 "register a device"
as_a DELETE "/api/devices/$(printf 'ab%.0s' $(seq 1 32))"
expect 204 "remove the device"
as_a POST /api/purchases/verify '{"signedTransaction":"eyJhbGciOiJFUzI1NiJ9.e30.c2ln"}'
expect 400 "forged StoreKit transaction is refused"
api POST "$BASE/api/appstore/notifications" '{"signedPayload":"eyJhbGciOiJFUzI1NiJ9.e30.c2ln"}'
expect 400 "forged App Store notification is refused"
api GET "$BASE/api/cron/daily"
expect 401 "cron needs its secret"

# --- Stop sharing, then delete both accounts
as_a DELETE "/api/videos/$VID"
expect 204 "stop sharing"
viewer GET "/api/public/v/$SLUG"
expect 410 "stopped link says removed"
check "$(j 'v.error')" "removed" "error is removed"
# The bucket itself is checked: Supabase's CDN may keep answering an already-issued signed URL for about a minute.
admin POST "/storage/v1/object/list/videos" "{\"prefix\":\"$UID_A/$VID/\",\"limit\":100}"
check "$OUT" "[]" "the video's files are deleted from the bucket"
for who in A B; do
  token_var="TOKEN_$who"
  api POST "$BASE/api/account/delete" "{}" -H "authorization: Bearer ${!token_var}"
  expect 204 "delete account $who"
done
as_a GET /api/me
expect 401 "deleted account can't sign in"
admin GET "/auth/v1/admin/users/$UID_A"
expect 404 "auth user A is gone"
admin GET "/rest/v1/videos?select=id&owner_id=eq.$UID_A"
check "$OUT" "[]" "no video rows left for A"
admin GET "/rest/v1/subscriptions?select=user_id&user_id=eq.$UID_A"
check "$OUT" "[]" "no subscription row left for A"
USERS=("${USERS[0]}") # A and B are already deleted; the trap removes the OTP user

echo
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
