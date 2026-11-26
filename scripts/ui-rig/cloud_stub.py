"""The practice server: answers for Snapreel's online services inside the runner, so sign-in, links,
uploads and Pro screens can be tried with made-up accounts and nothing leaves the runner.

The runner's /etc/hosts sends the real host names here (port 443, a certificate made on the runner
that only its simulators trust). Follows docs/pro/API.md. Any email works; the code is 123456.
Control (127.0.0.1:8899): POST /net/online|offline|slow|error, POST /plan/free|pro, GET /state.

    sudo python3 cloud_stub.py --cert cert.pem --key key.pem --site snapreel.video [--site-ip 1.2.3.4]
"""
import argparse
import base64
import hashlib
import http.client
import json
import os
import shutil
import tempfile
import urllib.parse
import random
import re
import ssl
import string
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CODE = "123456"
# What was uploaded, kept so the practice watch page can play it.
FILES = os.environ.get("RIG_FILES") or tempfile.mkdtemp(prefix="practice-files-")
LOCK = threading.RLock()
S = {"net": "online", "plan": "free", "users": {}, "tokens": {}, "videos": {}, "uploads": {}, "objects": {},
     "requests": []}


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def b64(data):
    return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    site, site_ip = "snapreel.video", ""

    def log_message(self, *args):
        pass

    # ---- plumbing

    def reply(self, status, body=None, headers=None):
        data = b"" if body is None else body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("X-Practice-Server", "yes")
        if body is not None and not (headers or {}).get("Content-Type"):
            self.send_header("Content-Type", "application/json")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        with LOCK:
            S["requests"].append("%s %s%s -> %d" % (self.command, self.headers.get("Host", ""), self.path.split("?")[0], status))
            del S["requests"][:-400]

    def body(self):
        if getattr(self, "_body", None) is None:
            size = int(self.headers.get("Content-Length") or 0)
            self._body = self.rfile.read(size) if size else b""
        return self._body

    def json(self):
        try:
            return json.loads(self.body() or b"{}")
        except ValueError:
            return {}

    def fail(self, status, code, message="", **extra):
        self.reply(status, dict({"error": code, "message": message}, **extra))

    def user(self):
        token = (self.headers.get("Authorization") or "").replace("Bearer ", "")
        return S["users"].get(S["tokens"].get(token))

    def handle_any(self):
        self._body = None
        net = S["net"]
        if net == "offline":
            self.close_connection = True
            try:
                self.connection.close()
            except OSError:
                pass
            return
        if net == "slow":
            time.sleep(4)
        if net == "error":
            self.body()
            return self.fail(500, "server_error", "Something went wrong.")
        host = (self.headers.get("Host") or "").split(":")[0]
        path = self.path.split("?")[0]
        try:
            streams = "/upload/resumable" in path or ("/storage/v1/" in path and self.command in ("PUT", "POST")
                                                      and int(self.headers.get("Content-Length") or 0) > 1_000_000)
            if not streams:
                self.body()
            if "supabase" in host:
                return self.supabase(path)
            if path.startswith("/api/"):
                return self.api(path[4:])
            if path.startswith("/v/"):
                return self.watch(path[3:].strip("/"))
            if path.startswith("/practice-files/"):
                return self.serve_file(urllib.parse.unquote(path[len("/practice-files/"):]))
            return self.proxy()
        except (BrokenPipeError, ConnectionResetError):
            pass

    do_GET = do_POST = do_PATCH = do_PUT = do_DELETE = do_HEAD = do_OPTIONS = handle_any

    # ---- sign-in and file uploads

    def session(self, email):
        with LOCK:
            user = next((u for u in S["users"].values() if u["email"] == email), None)
            if user is None:
                user = {"id": str(uuid.uuid4()), "email": email, "displayName": None, "emailAlerts": True, "brandColor": None}
                S["users"][user["id"]] = user
            token = "%s.%s.%s" % (b64({"alg": "none"}), b64({"sub": user["id"], "n": random.random()}), "practice")
            refresh = uuid.uuid4().hex
            S["tokens"][token] = user["id"]
            S["tokens"]["r:" + refresh] = user["id"]
        return {"access_token": token, "refresh_token": refresh, "token_type": "bearer", "expires_in": 3600,
                "expires_at": int(time.time()) + 3600, "user": {"id": user["id"], "email": email}}

    def supabase(self, path):
        if path.startswith("/auth/v1/"):
            what = path[len("/auth/v1/"):]
            data = self.json()
            if what == "otp":
                email = data.get("email", "")
                if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
                    return self.reply(422, {"error_code": "email_address_invalid", "msg": "Email address is invalid"})
                return self.reply(200, {})
            if what == "verify":
                if data.get("token") != CODE:
                    return self.reply(403, {"error_code": "otp_expired", "msg": "Token has expired or is invalid"})
                return self.reply(200, self.session(data.get("email", "tester@example.com")))
            if what == "token":
                if data.get("refresh_token"):
                    owner = S["users"].get(S["tokens"].get("r:" + data["refresh_token"]))
                    if not owner:
                        return self.reply(400, {"error": "invalid_grant"})
                    return self.reply(200, self.session(owner["email"]))
                return self.reply(200, self.session("apple-tester@example.com"))
            if what == "logout":
                return self.reply(204)
            if what == "user":
                owner = self.user()
                return self.reply(200, {"id": owner["id"], "email": owner["email"]}) if owner else self.reply(401, {})
            return self.reply(404, {})
        if "/upload/resumable" in path:
            return self.tus(path)
        if path.startswith("/storage/v1/s3/"):
            return self.s3(urllib.parse.unquote(path[len("/storage/v1/s3/"):]))
        if path.startswith("/storage/v1/object/info/"):
            return self.object_info(urllib.parse.unquote(path[len("/storage/v1/object/info/"):]))
        if path.startswith("/storage/v1/object/"):
            return self.object_upload(urllib.parse.unquote(path[len("/storage/v1/object/"):]))
        self.body()
        return self.reply(404, {})

    # ---- stored files

    @staticmethod
    def disk(name):
        return os.path.join(FILES, hashlib.sha1(name.encode()).hexdigest())

    def receive(self, target):
        """Writes the request's body to `target`; returns (size, md5) or None when the sender went away."""
        left, digest = int(self.headers.get("Content-Length") or 0), hashlib.md5()
        if getattr(self, "_body", None) is not None:
            data = self._body
            with open(target, "wb") as f:
                f.write(data)
            return len(data), hashlib.md5(data).hexdigest()
        size = left
        with open(target, "wb") as f:
            while left > 0:
                got = self.rfile.read(min(left, 262144))
                if not got:
                    return None
                f.write(got)
                digest.update(got)
                left -= len(got)
                if S["net"] == "slow":
                    time.sleep(0.15)
        self._body = b""
        return size, digest.hexdigest()

    def store(self, name, source, size, kind=None):
        os.replace(source, self.disk(name))
        with LOCK:
            S["objects"][name] = size
            S.setdefault("types", {})[name] = kind or self.headers.get("Content-Type") or "application/octet-stream"

    def object_upload(self, rest):
        """`POST|PUT /storage/v1/object/<bucket>/<name>`: a whole small file in one request."""
        if self.command not in ("POST", "PUT"):
            self.body()
            return self.reply(404, {"statusCode": "404", "error": "not_found", "message": "Object not found"})
        if not self.user():
            self.body()
            return self.reply(400, {"statusCode": "403", "error": "Unauthorized", "message": "jwt expired"})
        bucket, _, name = rest.partition("/")
        if name in S["objects"] and self.headers.get("x-upsert") != "true":
            self.body()
            return self.reply(400, {"statusCode": "409", "error": "Duplicate", "message": "The resource already exists"})
        temp = self.disk(name) + ".part"
        got = self.receive(temp)
        if got is None:
            return
        self.store(name, temp, got[0])
        return self.reply(200, {"Key": "%s/%s" % (bucket, name), "Id": str(uuid.uuid4())})

    def object_info(self, rest):
        """`GET /storage/v1/object/info/authenticated/<bucket>/<name>`."""
        if rest.startswith("authenticated/"):
            rest = rest[len("authenticated/"):]
        elif rest.startswith("public/"):
            rest = rest[len("public/"):]
        if not self.user():
            return self.reply(400, {"statusCode": "403", "error": "Unauthorized", "message": "jwt expired"})
        bucket, _, name = rest.partition("/")
        if name not in S["objects"]:
            return self.reply(400, {"statusCode": "404", "error": "not_found", "message": "Object not found"})
        return self.reply(200, {"id": hashlib.sha1(name.encode()).hexdigest(), "name": name, "bucket_id": bucket,
                                "size": S["objects"][name], "content_type": S.get("types", {}).get(name),
                                "created_at": now(), "updated_at": now()})

    def s3_error(self, status, code, message):
        self.body()
        xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Error><Code>%s</Code><Message>%s</Message></Error>" % (code, message)
        return self.reply(status, xml.encode(), {"Content-Type": "application/xml"})

    def s3(self, rest):
        """Storage's S3 endpoint, multipart only: create (`POST ?uploads`), pieces (`PUT ?partNumber&uploadId`),
        join (`POST ?uploadId`) and abort (`DELETE ?uploadId`). Signatures are not checked; the session token is."""
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query, keep_blank_values=True)
        token = (query.get("X-Amz-Security-Token") or [""])[0]
        if S["users"].get(S["tokens"].get(token)) is None:
            return self.s3_error(403, "AccessDenied", "Invalid JWT: signature verification failed")
        bucket, _, name = rest.partition("/")
        upload_id = (query.get("uploadId") or [""])[0]
        if self.command == "POST" and "uploads" in query:
            upload_id = uuid.uuid4().hex
            os.makedirs(os.path.join(FILES, "multipart", upload_id), exist_ok=True)
            with LOCK:
                S["uploads"][upload_id] = {"name": name, "parts": {}, "type": self.headers.get("Content-Type")}
            xml = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><InitiateMultipartUploadResult><Bucket>%s</Bucket><Key>%s</Key>"
                   "<UploadId>%s</UploadId></InitiateMultipartUploadResult>" % (bucket, name, upload_id))
            return self.reply(200, xml.encode(), {"Content-Type": "application/xml"})
        upload = S["uploads"].get(upload_id)
        if upload is None or upload.get("name") != name:
            return self.s3_error(404, "NoSuchUpload", "The specified upload does not exist")
        if self.command == "PUT":
            try:
                number = int((query.get("partNumber") or ["0"])[0])
            except ValueError:
                number = 0
            if not 1 <= number <= 10000:
                return self.s3_error(400, "InvalidPartNumber", "Part number must be between 1 and 10000")
            target = os.path.join(FILES, "multipart", upload_id, "%05d" % number)
            got = self.receive(target + ".part")
            if got is None:
                return
            os.replace(target + ".part", target)
            with LOCK:
                upload["parts"][number] = got
            return self.reply(200, b"", {"ETag": '"%s"' % got[1]})
        if self.command == "DELETE":
            with LOCK:
                S["uploads"].pop(upload_id, None)
            shutil.rmtree(os.path.join(FILES, "multipart", upload_id), ignore_errors=True)
            return self.reply(204)
        if self.command != "POST":
            return self.s3_error(405, "MethodNotAllowed", "Not supported here")
        listed = [(int(n), e.strip('"').lower()) for n, e in re.findall(
            r"<PartNumber>\s*(\d+)\s*</PartNumber>\s*<ETag>\s*(?:&quot;|\")?([0-9a-fA-F]*)(?:&quot;|\")?\s*</ETag>",
            self.body().decode(errors="replace"))]
        if not listed:
            return self.s3_error(400, "MalformedXML", "The XML you provided was not well-formed")
        if [n for n, _ in listed] != sorted(n for n, _ in listed):
            return self.s3_error(400, "InvalidPartOrder", "The list of parts was not in ascending order")
        for number, etag in listed:
            have = upload["parts"].get(number)
            if have is None or have[1] != etag:
                return self.s3_error(400, "InvalidPart", "One or more of the specified parts could not be found")
        for number, _ in listed[:-1]:
            if upload["parts"][number][0] < 5 * 1024 * 1024:
                return self.s3_error(400, "EntityTooSmall", "Your proposed upload is smaller than the minimum allowed")
        temp = self.disk(name) + ".join"
        with open(temp, "wb") as out:
            for number, _ in listed:
                with open(os.path.join(FILES, "multipart", upload_id, "%05d" % number), "rb") as piece:
                    shutil.copyfileobj(piece, out, 1 << 20)
        size = sum(upload["parts"][n][0] for n, _ in listed)
        self.store(name, temp, size, upload.get("type"))
        with LOCK:
            S["uploads"].pop(upload_id, None)
        shutil.rmtree(os.path.join(FILES, "multipart", upload_id), ignore_errors=True)
        etag = hashlib.md5(b"".join(bytes.fromhex(e) for _, e in listed)).hexdigest() + "-%d" % len(listed)
        xml = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><CompleteMultipartUploadResult><Location>%s</Location><Bucket>%s</Bucket>"
               "<Key>%s</Key><ETag>\"%s\"</ETag></CompleteMultipartUploadResult>" % (name, bucket, name, etag))
        return self.reply(200, xml.encode(), {"Content-Type": "application/xml"})

    def serve_file(self, name):
        """A stored file for the practice watch page, with byte ranges (Safari asks for them before it plays)."""
        path = self.disk(name)
        if name not in S["objects"] or not os.path.exists(path):
            return self.reply(404, b"", {"Content-Type": "text/plain"})
        size = os.path.getsize(path)
        start, end, status = 0, size - 1, 200
        match = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range") or "")
        if match and size:
            if match.group(1):
                start = int(match.group(1))
                end = min(int(match.group(2)), size - 1) if match.group(2) else size - 1
            else:
                start = max(0, size - int(match.group(2) or 0))
            status = 206
        length = max(0, end - start + 1)
        self.send_response(status)
        self.send_header("X-Practice-Server", "yes")
        self.send_header("Content-Type", S.get("types", {}).get(name) or "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(path, "rb") as f:
            f.seek(start)
            while length > 0:
                chunk = f.read(min(length, 1 << 20))
                if not chunk:
                    break
                self.wfile.write(chunk)
                length -= len(chunk)

    def tus(self, path):
        base = "/storage/v1/upload/resumable"
        if not self.user():
            self.body()
            return self.reply(403, {"message": "jwt expired"})
        if self.command == "POST":
            meta = {}
            for pair in (self.headers.get("Upload-Metadata") or "").split(","):
                key, _, value = pair.strip().partition(" ")
                meta[key] = base64.b64decode(value or "").decode(errors="replace")
            uid = uuid.uuid4().hex
            S["uploads"][uid] = {"size": int(self.headers.get("Upload-Length") or 0), "at": 0, "name": meta.get("objectName", uid)}
            return self.reply(201, None, {"Location": "https://%s%s/%s" % (self.headers.get("Host"), base, uid),
                                          "Tus-Resumable": "1.0.0", "Upload-Offset": "0"})
        upload = S["uploads"].get(path.rsplit("/", 1)[1])
        if upload is None:
            self.body()
            return self.reply(404, {})
        if self.command == "HEAD":
            return self.reply(200, None, {"Upload-Offset": str(upload["at"]), "Upload-Length": str(upload["size"]),
                                          "Tus-Resumable": "1.0.0"})
        if int(self.headers.get("Upload-Offset") or 0) != upload["at"]:
            self.body()
            return self.reply(409, {})
        temp = self.disk(upload["name"]) + ".tus"
        got = self.receive(temp + ".chunk")
        if got is None:
            return
        with open(temp, "ab") as out, open(temp + ".chunk", "rb") as chunk:
            shutil.copyfileobj(chunk, out, 1 << 20)
        os.remove(temp + ".chunk")
        upload["at"] += got[0]
        if upload["at"] >= upload["size"]:
            self.store(upload["name"], temp, upload["size"])
        return self.reply(204, None, {"Upload-Offset": str(upload["at"]), "Tus-Resumable": "1.0.0"})

    # ---- the API

    def me(self, user):
        pro = S["plan"] == "pro"
        return {"user": {k: user[k] for k in ("id", "email", "displayName", "emailAlerts", "brandColor")},
                "plan": {"tier": "pro" if pro else "free", "productId": "co.arclayer.snapreel.pro.yearly" if pro else None,
                         "expiresAt": "2027-06-01T00:00:00.000Z" if pro else None},
                "usage": {"activeLinks": sum(v["owner"] == user["id"] for v in S["videos"].values()),
                          "linkLimit": None if pro else 25, "maxDurationS": 7200 if pro else 300,
                          "quality": "1080p" if pro else "720p"}}

    def detail(self, v):
        return {k: v[k] for k in v if k not in ("owner", "activity", "password")}

    def api(self, path):
        if path.startswith("/live-activity") or path.startswith("/health"):
            return self.reply(200, {"ok": True})
        if path.startswith("/public/"):
            return self.public(path[len("/public/"):])
        user = self.user()
        if not user:
            return self.fail(401, "unauthorized")
        data, method = self.json(), self.command
        if path == "/me":
            if method == "PATCH":
                user.update({k: v for k, v in data.items() if k in ("displayName", "emailAlerts", "brandColor")})
            return self.reply(200, self.me(user))
        if path == "/videos" and method == "GET":
            mine = [v for v in S["videos"].values() if v["owner"] == user["id"]]
            return self.reply(200, [self.detail(v) for v in sorted(mine, key=lambda v: v["createdAt"], reverse=True)])
        if path == "/videos" and method == "POST":
            usage = self.me(user)["usage"]
            old = next((v for v in S["videos"].values() if v["owner"] == user["id"] and v["localId"] == data.get("localId")), None)
            if old is None:
                if usage["linkLimit"] and usage["activeLinks"] >= usage["linkLimit"]:
                    return self.reply(402, {"error": "limit", "reason": "links"})
                if float(data.get("durationS") or 0) > usage["maxDurationS"] + 1:
                    return self.reply(402, {"error": "limit", "reason": "duration"})
                vid = str(uuid.uuid4())
                slug = "".join(random.choice(string.ascii_letters + string.digits) for _ in range(10))
                old = {"id": vid, "slug": slug, "url": "https://%s/v/%s" % (self.site, slug), "localId": data.get("localId"),
                       "title": data.get("title") or "Untitled", "kind": data.get("kind") or "screen",
                       "durationS": data.get("durationS") or 0, "status": "uploading", "posterUrl": None, "createdAt": now(),
                       "views": 0, "uniqueViewers": 0, "lastViewedAt": None, "commentCount": 0, "access": "link",
                       "expiresAt": None, "hasPassword": False, "allowDownload": False, "allowComments": True,
                       "allowReactions": True, "cta": None, "width": data.get("width") or 0, "height": data.get("height") or 0,
                       "sizeBytes": data.get("sizeBytes") or 0, "owner": user["id"],
                       "activity": {"comments": [], "reactions": []}}
                S["videos"][vid] = old
            base = "%s/%s/" % (user["id"], old["id"])
            return self.reply(201, dict(self.detail(old), upload={
                "bucket": "videos", "videoPath": base + "video.mp4", "posterPath": base + "poster.jpg",
                "previewPath": base + "preview.mp4"}, limits={"maxDurationS": usage["maxDurationS"],
                                                              "maxLongSide": 1920 if S["plan"] == "pro" else 1280}))
        match = re.fullmatch(r"/videos/([^/]+)(/insights|/activity)?", path)
        if match:
            v = S["videos"].get(match.group(1))
            if v is None or v["owner"] != user["id"]:
                return self.fail(404, "not_found")
            if match.group(2) == "/insights":
                basic = {"views": v["views"], "uniqueViewers": v["uniqueViewers"]}
                if S["plan"] == "pro":
                    basic.update(avgPercent=64, completionRate=0.4, dropoff=[max(0, v["views"] - i // 30) for i in range(100)],
                                 countries=[{"code": "GB", "count": v["views"]}] if v["views"] else [],
                                 viewers=[{"name": "Sam", "anonymous": False, "country": "GB", "device": "phone",
                                           "firstSeenAt": now(), "lastSeenAt": now(), "percent": 64}] if v["views"] else [])
                return self.reply(200, basic)
            if match.group(2) == "/activity":
                return self.reply(200, v["activity"])
            if method == "DELETE":
                del S["videos"][v["id"]]
                return self.reply(204)
            if method == "PATCH":
                if data.get("status") == "ready":
                    base = "%s/%s/" % (user["id"], v["id"])
                    missing = [n for n in ("video.mp4", "poster.jpg", "preview.mp4") if base + n not in S["objects"]]
                    if missing:
                        return self.fail(409, "missing_files", ", ".join(missing))
                pro_only = {"password", "expiresAt", "allowDownload", "cta"} & {k for k, val in data.items() if val is not None}
                if pro_only and S["plan"] != "pro":
                    return self.reply(402, {"error": "limit", "reason": "pro_feature"})
                for key in ("title", "status", "access", "expiresAt", "allowDownload", "allowComments", "allowReactions", "cta"):
                    if key in data:
                        v[key] = data[key]
                if data.get("password"):
                    v["hasPassword"], v["access"] = True, "password"
                if data.get("access") == "link":
                    v["hasPassword"] = False
            return self.reply(200, self.detail(v))
        if path.startswith("/comments/"):
            cid = path.split("/")[2]
            for v in S["videos"].values():
                for c in list(v["activity"]["comments"]):
                    if c["id"] == cid:
                        if path.endswith("/approve"):
                            c["held"] = False
                            return self.reply(200, c)
                        v["activity"]["comments"].remove(c)
                        v["commentCount"] -= 1
                        return self.reply(204)
            return self.fail(404, "not_found")
        if path == "/purchases/verify":
            S["plan"] = "pro"
            return self.reply(200, {"plan": self.me(user)["plan"]})
        if path == "/account/delete":
            for vid in [k for k, v in S["videos"].items() if v["owner"] == user["id"]]:
                del S["videos"][vid]
            S["users"].pop(user["id"], None)
            return self.reply(204)
        if path.startswith("/blocks") or path.startswith("/devices"):
            return self.reply(204)
        return self.fail(404, "not_found")

    def public(self, rest):
        match = re.match(r"v/([^/]+)", rest)
        v = next((v for v in S["videos"].values() if match and v["slug"] == match.group(1)), None)
        if v is None:
            return self.fail(404, "not_found")
        return self.reply(200, self.detail(v))

    def visit(self, v):
        """Opening the practice watch page counts as a view, with a comment and a reaction the first time."""
        v["views"] += 1
        v["uniqueViewers"] = 1
        v["lastViewedAt"] = now()
        if not v["activity"]["comments"]:
            v["activity"]["comments"].append({"id": str(uuid.uuid4()), "authorName": "Sam", "isOwner": False,
                                              "body": "Nice and clear, thank you!", "atS": 3.0, "parentId": None,
                                              "createdAt": now(), "held": False})
            v["activity"]["comments"].append({"id": str(uuid.uuid4()), "authorName": "Guest", "isOwner": False,
                                              "body": "This one waits for your approval", "atS": None, "parentId": None,
                                              "createdAt": now(), "held": True})
            v["activity"]["reactions"].append({"id": str(uuid.uuid4()), "emoji": "\U0001F44D", "atS": 2.0,
                                               "authorName": "Sam", "createdAt": now()})
            v["commentCount"] = 2

    def watch(self, slug):
        v = next((v for v in S["videos"].values() if v["slug"] == slug.split("/")[0]), None)
        if v is None:
            text = "<h1>Practice watch page</h1><p>There is no such link.</p>"
            return self.reply(404, ("<meta name=viewport content='width=device-width'>" + text).encode(), {"Content-Type": "text/html"})
        self.visit(v)
        text = "<meta name=viewport content='width=device-width'><h1>Practice watch page</h1><p>%s (%s)</p>" % (
            v["title"].replace("<", "&lt;"), v["status"])
        video = "%s/%s/video.mp4" % (v["owner"], v["id"])
        if video in S["objects"]:
            poster = "%s/%s/poster.jpg" % (v["owner"], v["id"])
            text += "<video controls playsinline style='width:100%%' src='/practice-files/%s'%s></video>" % (
                urllib.parse.quote(video), " poster='/practice-files/%s'" % urllib.parse.quote(poster) if poster in S["objects"] else "")
        else:
            text += "<p>The video is not there yet.</p>"
        return self.reply(200, text.encode(), {"Content-Type": "text/html; charset=utf-8"})

    def proxy(self):
        """Other pages (terms, privacy, home) come from the real site, read-only and without cookies."""
        if self.command not in ("GET", "HEAD") or not self.site_ip:
            return self.fail(404, "not_found")
        try:
            context = ssl.create_default_context()
            conn = http.client.HTTPSConnection(self.site, timeout=15, context=context)
            import socket
            raw = socket.create_connection((self.site_ip, 443), timeout=15)
            conn.sock = context.wrap_socket(raw, server_hostname=self.site)
            conn.request(self.command, self.path, headers={"Host": self.site, "User-Agent": self.headers.get("User-Agent", "rig"),
                                                           "Accept": self.headers.get("Accept", "*/*")})
            answer = conn.getresponse()
            data = answer.read()
            keep = {k: val for k, val in answer.getheaders() if k.lower() in ("content-type", "location", "cache-control")}
            self.reply(answer.status, data, keep)
        except OSError:
            self.fail(502, "unreachable")


class Control(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, status, text):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.send(200, json.dumps({k: S[k] for k in ("net", "plan", "requests")} | {
            "links": [v["url"] for v in S["videos"].values()], "files": len(S["objects"])}))

    def do_POST(self):
        parts = self.path.strip("/").split("/")
        choices = {"net": ("online", "offline", "slow", "error"), "plan": ("free", "pro")}
        if len(parts) != 2 or parts[0] not in choices or parts[1] not in choices[parts[0]]:
            return self.send(400, "choose one of: " + "; ".join("%s %s" % (k, "|".join(v)) for k, v in choices.items()))
        S[parts[0]] = parts[1]
        notes = {"offline": "Snapreel's server now drops every connection (the phone itself stays online)",
                 "slow": "the server now takes 4 s to answer", "error": "the server now answers every request with an error",
                 "online": "the server works normally", "free": "the practice account is Free", "pro": "the practice account is Pro"}
        self.send(200, notes[parts[1]])


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 64

    def handle_error(self, request, client_address):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert")
    parser.add_argument("--key")
    parser.add_argument("--site", default="snapreel.video")
    parser.add_argument("--site-ip", default="")
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--control", type=int, default=8899)
    args = parser.parse_args()
    Handler.site, Handler.site_ip = args.site, args.site_ip
    server = Server(("127.0.0.1", args.port), Handler)
    if args.cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        # Handshakes happen in each connection's own thread, not in the accept loop.
        server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print("practice server on 127.0.0.1:%d" % args.port, flush=True)
    Server(("127.0.0.1", args.control), Control).serve_forever()


if __name__ == "__main__":
    main()
