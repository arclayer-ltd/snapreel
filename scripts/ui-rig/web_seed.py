"""Made-up people and videos for the local website (site_local.sh). Writes WORK/links.json: {name: page}."""
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

W = sys.argv[1]
API, SITE = os.environ["API_URL"], "http://localhost:3000"
SERVICE = os.environ["SUPABASE_SECRET_KEY"]
PUBLIC = os.environ["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"]
MEDIA = os.path.join(W, "media")
links, problems = {}, []


def call(method, url, body=None, token=None, key=None, kind="application/json", extra=None):
    data = body if isinstance(body, bytes) else None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        request.add_header("Content-Type", kind)
    if key:
        request.add_header("apikey", key)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    elif key and key.startswith("ey"):
        request.add_header("Authorization", "Bearer " + key)
    for name, value in (extra or {}).items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=60) as reply:
            text = reply.read()
            return json.loads(text) if text[:1] in (b"{", b"[") else text
    except urllib.error.HTTPError as error:
        raise RuntimeError("%s %s: HTTP %d %s" % (method, url, error.code, error.read()[:300]))


def attempt(what, work):
    try:
        return work()
    except Exception as error:
        problems.append("%s: %s" % (what, error))
        print("seed: %s: %s" % (what, error), flush=True)


def person(email, name):
    call("POST", API + "/auth/v1/admin/users", {"email": email, "password": "practice-only-1", "email_confirm": True}, key=SERVICE)
    session = call("POST", API + "/auth/v1/token?grant_type=password", {"email": email, "password": "practice-only-1"}, key=PUBLIC)
    attempt("name of " + email, lambda: call("PATCH", SITE + "/api/me", {"displayName": name}, token=session["access_token"]))
    return session["user"]["id"], session["access_token"]


def media(name):
    with open(os.path.join(MEDIA, name), "rb") as f:
        return f.read()


def video(token, title, clip, kind, seconds, width, height, finish=True, transcript=True):
    data = media(clip)
    body = {"localId": str(uuid.uuid4()), "title": title, "kind": kind, "durationS": seconds, "width": width, "height": height,
            "sizeBytes": len(data)}
    if transcript:
        body["transcript"] = {"locale": "en-GB", "segments": [
            {"start": i * 10, "duration": 6, "text": "We are at %d minutes and %d seconds. Here is the next part of the sample." % (
                i * 10 // 60, i * 10 % 60)} for i in range(int(seconds // 10) + 1)]}
    made = call("POST", SITE + "/api/videos", body, token=token)
    if finish:
        for key, content, what in (("videoPath", data, "video/mp4"), ("posterPath", media("picture.jpg"), "image/jpeg"),
                                   ("previewPath", media("short.mp4"), "video/mp4")):
            call("POST", "%s/storage/v1/object/%s/%s" % (API, made["upload"]["bucket"], made["upload"][key]), content, token=token,
                 key=PUBLIC, kind=what, extra={"x-upsert": "true"})
        call("PATCH", SITE + "/api/videos/" + made["id"], {"status": "ready"}, token=token)
    return made


def table(method, path, body, prefer="return=minimal"):
    return call(method, API + "/rest/v1/" + path, body, key=SERVICE, extra={"Prefer": prefer})


free_id, free = person("free@example.com", "Robin Free")
pro_id, pro = person("pro@example.com", "Alex Pro")
attempt("Pro plan", lambda: table("POST", "subscriptions", {
    "user_id": pro_id, "product_id": "co.arclayer.snapreel.pro.yearly", "original_transaction_id": "practice-1",
    "status": "active", "expires_at": "2028-01-01T00:00:00Z", "environment": "Sandbox"}))


def add(name, *args, **kw):
    made = attempt(name, lambda: video(*args, **kw))
    if made:
        links[name] = "v/" + made["slug"]
    return made


wide = add("wide", pro, "Launch plan walk-through", "landscape.mp4", "camera", 20, 1920, 1080)
add("tall", pro, "Checkout on the phone", "short.mp4", "screen", 12, 886, 1920)
add("voice", pro, "Voice note before Thursday", "square.mp4", "audio", 10, 0, 0)
locked = add("locked (password snapreel)", pro, "Numbers for the board", "landscape.mp4", "camera", 20, 1920, 1080)
button = add("with a button and downloads", pro, "Book a demo", "short.mp4", "screen", 12, 886, 1920)
expired = add("expired", pro, "Last week only", "short.mp4", "screen", 12, 886, 1920)
failed = add("failed", pro, "This one did not finish", "short.mp4", "screen", 12, 886, 1920, finish=False)
add("still uploading", pro, "On its way", "short.mp4", "screen", 12, 886, 1920, finish=False)
stopped = add("stopped", pro, "Not shared any more", "short.mp4", "screen", 12, 886, 1920)
add("from a Free account", free, "My first link", "landscape.mp4", "camera", 20, 1920, 1080)
add("a long title", free, "A very long title that somebody typed on the bus, with everything in it, so that it has to be cut or wrapped somewhere "
    "on every screen that shows it 🎬", "short.mp4", "screen", 12, 886, 1920, transcript=False)
if locked:
    attempt("password", lambda: call("PATCH", SITE + "/api/videos/" + locked["id"], {"access": "password", "password": "snapreel"}, token=pro))
if button:
    attempt("button", lambda: call("PATCH", SITE + "/api/videos/" + button["id"], {
        "cta": {"label": "Book a demo", "url": "https://example.com/demo"}, "allowDownload": True}, token=pro))
if expired:
    attempt("expiry", lambda: table("PATCH", "videos?id=eq." + expired["id"], {"expires_at": "2026-01-01T00:00:00Z"}))
if failed:
    attempt("failure", lambda: table("PATCH", "videos?id=eq." + failed["id"], {"status": "failed"}))
if stopped:
    attempt("stop sharing", lambda: call("DELETE", SITE + "/api/videos/" + stopped["id"], token=pro))
if wide:
    page = SITE + "/api/public/v/" + wide["slug"]
    for who, text, at in (("Sam", "Nice and clear, thank you!", 3), ("Priya", "Could you say more about the second part?", 11),
                          ("Guest", "Looks good to me", None)):
        attempt("comment", lambda: call("POST", page + "/comments", {"name": who, "body": text, "atS": at, "website": ""}))
    for emoji, at in (("👍", 2), ("🔥", 9), ("👏", 15)):
        attempt("reaction", lambda: call("POST", page + "/reactions", {"emoji": emoji, "atS": at, "name": "Sam"}))
    for seen in (30, 70, 100):
        attempt("view", lambda: call("POST", page + "/view", {"event": "start", "positionS": 0, "watched": list(range(seen)),
                                                              "referrer": "https://example.com/"}))
with open(os.path.join(W, "links.json"), "w") as f:
    json.dump({"links": links, "problems": problems}, f)
print("seed: %d links, %d problems" % (len(links), len(problems)))
