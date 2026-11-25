"""A tiny git-over-HTTPS client: the channel between the PC and the runner.

Both ends keep one connection to github.com open and exchange small commits on refs that are not
branches (refs/rig/<session>/in and .../out). Nothing listens anywhere and nothing is exposed:
each side only talks to github.com, with the login it already has. Plain `git push` does the same
job but starts two processes and two TLS handshakes per call; this is one request per push.
Standard library only (it also runs on the macOS runner).
"""
import base64
import hashlib
import http.client
import ssl
import struct
import time
import zlib

ZERO = "0" * 40
HOST = "github.com"


class WireError(Exception):
    pass


class AuthError(WireError):
    pass


def _pkt(text):
    data = text if isinstance(text, bytes) else text.encode()
    return b"%04x" % (len(data) + 4) + data


FLUSH, DELIM = b"0000", b"0001"


def _read_pkts(data):
    """Yields each packet's payload; None for flush, delimiter and response-end."""
    pos = 0
    while pos + 4 <= len(data):
        size = int(data[pos:pos + 4], 16)
        if size < 4:
            yield None
            pos += 4
        else:
            yield data[pos + 4:pos + size]
            pos += size


def _sha(kind, body):
    return hashlib.sha1(b"%s %d\0" % (kind.encode(), len(body)) + body).hexdigest()


_KIND_NUM = {"commit": 1, "tree": 2, "blob": 3, "tag": 4}
_NUM_KIND = {v: k for k, v in _KIND_NUM.items()}


def _pack(objects):
    out = [b"PACK", struct.pack(">II", 2, len(objects))]
    for kind, body in objects:
        size = len(body)
        byte = (_KIND_NUM[kind] << 4) | (size & 15)
        size >>= 4
        head = bytearray()
        while size:
            head.append(byte | 0x80)
            byte = size & 0x7F
            size >>= 7
        head.append(byte)
        out.append(bytes(head))
        out.append(zlib.compress(body, 6))
    data = b"".join(out)
    return data + hashlib.sha1(data).digest()


def _apply_delta(base, delta):
    pos = 0

    def varint():
        nonlocal pos
        value = shift = 0
        while True:
            b = delta[pos]
            pos += 1
            value |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                return value

    varint()
    varint()
    out = []
    while pos < len(delta):
        op = delta[pos]
        pos += 1
        if op & 0x80:
            off = size = 0
            for i in range(4):
                if op & (1 << i):
                    off |= delta[pos] << (8 * i)
                    pos += 1
            for i in range(3):
                if op & (1 << (4 + i)):
                    size |= delta[pos] << (8 * i)
                    pos += 1
            size = size or 0x10000
            out.append(base[off:off + size])
        else:
            out.append(delta[pos:pos + op])
            pos += op
    return b"".join(out)


def _unpack(data):
    """{sha: (kind, body)} for a self-contained pack."""
    if data[:4] != b"PACK":
        raise WireError("the server sent no pack")
    count = struct.unpack(">I", data[8:12])[0]
    pos, objects, by_offset, pending = 12, {}, {}, []
    for _ in range(count):
        start = pos
        byte = data[pos]
        pos += 1
        num = (byte >> 4) & 7
        while byte & 0x80:
            byte = data[pos]
            pos += 1
        base = None
        if num == 6:  # offset delta
            byte = data[pos]
            pos += 1
            off = byte & 0x7F
            while byte & 0x80:
                byte = data[pos]
                pos += 1
                off = ((off + 1) << 7) | (byte & 0x7F)
            base = start - off
        elif num == 7:
            base = data[pos:pos + 20].hex()
            pos += 20
        inflater = zlib.decompressobj()
        body = inflater.decompress(data[pos:])
        pos = len(data) - len(inflater.unused_data)
        if base is None:
            kind = _NUM_KIND[num]
            objects[_sha(kind, body)] = (kind, body)
            by_offset[start] = (kind, body)
        else:
            pending.append((start, base, body))
    while pending:
        left = []
        for start, base, delta in pending:
            source = by_offset.get(base) if isinstance(base, int) else objects.get(base)
            if source is None:
                left.append((start, base, delta))
                continue
            body = _apply_delta(source[1], delta)
            objects[_sha(source[0], body)] = (source[0], body)
            by_offset[start] = (source[0], body)
        if len(left) == len(pending):
            raise WireError("the pack has an unresolved delta")
        pending = left
    return objects


def _tree(objects, files):
    """Adds the trees and blobs for {path: bytes} to `objects`; returns the root tree's sha."""
    entries, subdirs = [], {}
    for path, body in files.items():
        head, _, rest = path.partition("/")
        if rest:
            subdirs.setdefault(head, {})[rest] = body
        else:
            objects.append(("blob", body))
            entries.append((head, b"100644", _sha("blob", body)))
    for name, sub in subdirs.items():
        entries.append((name, b"40000", _tree(objects, sub)))
    entries.sort(key=lambda e: e[0] + ("/" if e[1] == b"40000" else ""))
    body = b"".join(mode + b" " + name.encode() + b"\0" + bytes.fromhex(sha) for name, mode, sha in entries)
    objects.append(("tree", body))
    return _sha("tree", body)


class Wire:
    def __init__(self, repo, token, timeout=30):
        self.path = "/" + repo + ".git/"
        self.auth = "Basic " + base64.b64encode(b"x-access-token:" + token.encode()).decode()
        self.timeout = timeout
        self.conn = None
        self.known = {}  # ref -> sha, for the refs this side writes
        self.notes = []  # what was slow or failed, for finding out why a command took long

    def _post(self, service, body, retries=5):
        headers = {
            "Authorization": self.auth,
            "Content-Type": "application/x-%s-request" % service,
            "Accept": "application/x-%s-result" % service,
            "User-Agent": "git/ui-rig",
        }
        if service == "git-upload-pack":
            headers["Git-Protocol"] = "version=2"
        last = None
        for attempt in range(retries):
            begun = time.time()
            try:
                if self.conn is None:
                    self.conn = http.client.HTTPSConnection(HOST, timeout=self.timeout,
                                                            context=ssl.create_default_context())
                self.conn.request("POST", self.path + service, body, headers)
                reply = self.conn.getresponse()
                data = reply.read()
                if reply.status == 200:
                    if time.time() - begun > 1.5:
                        self.note("%s took %.1f s" % (service, time.time() - begun))
                    return data
                if reply.status in (401, 403, 404) and b"rate limit" not in data.lower():
                    raise AuthError("GitHub refused (HTTP %d): check `gh auth status`" % reply.status)
                last = "HTTP %d %s" % (reply.status, data[:120])
                wait = float(reply.getheader("Retry-After") or 0) or (2 ** attempt)
            except (OSError, http.client.HTTPException) as error:
                last = "%s: %s" % (type(error).__name__, error)
                wait = 0.3 * (2 ** attempt)
            self.close()
            self.note("%s: %s after %.1f s" % (service, last, time.time() - begun))
            time.sleep(min(wait, 30))
        raise WireError("could not reach GitHub (%s)" % last)

    def note(self, text):
        self.notes = self.notes[-30:] + ["%s %s" % (time.strftime("%H:%M:%S"), text)]

    def close(self):
        if self.conn is not None:
            self.conn.close()
        self.conn = None

    def refs(self, prefix):
        body = (_pkt("command=ls-refs\n") + _pkt("agent=git/ui-rig\n") + _pkt("object-format=sha1\n") + DELIM
                + _pkt("ref-prefix %s\n" % prefix) + FLUSH)
        found = {}
        for pkt in _read_pkts(self._post("git-upload-pack", body)):
            if pkt and b" " in pkt:
                sha, ref = pkt.decode().strip().split(" ", 1)
                found[ref] = sha
        return found

    def ref(self, name):
        return self.refs(name).get(name)

    def fetch(self, sha):
        """{path: bytes} of the commit `sha`."""
        body = (_pkt("command=fetch\n") + _pkt("agent=git/ui-rig\n") + _pkt("object-format=sha1\n") + DELIM
                + _pkt("no-progress\n") + _pkt("deepen 1\n") + _pkt("want %s\n" % sha) + _pkt("done\n") + FLUSH)
        pack, in_pack = [], False
        for pkt in _read_pkts(self._post("git-upload-pack", body)):
            if pkt is None:
                continue
            if not in_pack:
                if pkt.startswith(b"ERR"):
                    raise WireError(pkt.decode(errors="replace"))
                in_pack = pkt.strip() == b"packfile"
            elif pkt[:1] == b"\x01":
                pack.append(pkt[1:])
            elif pkt[:1] == b"\x03":
                raise WireError(pkt[1:].decode(errors="replace"))
        objects = _unpack(b"".join(pack))
        root = objects[sha][1].split(b"\n", 1)[0].split()[1].decode()
        files = {}

        def walk(tree, prefix):
            body, pos = objects[tree][1], 0
            while pos < len(body):
                space = body.index(b" ", pos)
                end = body.index(b"\0", space)
                mode, name = body[pos:space], body[space + 1:end].decode()
                child = body[end + 1:end + 21].hex()
                pos = end + 21
                if mode == b"40000":
                    walk(child, prefix + name + "/")
                else:
                    files[prefix + name] = objects[child][1]

        walk(root, "")
        return files

    def push(self, ref, files, message="rig"):
        """Replaces `ref` with one parentless commit holding `files`; returns its sha."""
        objects = []
        tree = _tree(objects, files)
        who = "ui-rig <ui-rig@users.noreply.github.com> %d +0000" % int(time.time())
        commit = ("tree %s\nauthor %s\ncommitter %s\n\n%s\n" % (tree, who, who, message)).encode()
        objects.append(("commit", commit))
        sha = _sha("commit", commit)
        unique = list({_sha(k, b): (k, b) for k, b in objects}.values())
        self._update(ref, sha, _pack(unique))
        return sha

    def delete(self, ref):
        self._update(ref, ZERO, b"")

    def _update(self, ref, new, pack):
        for attempt in range(6):
            old = self.known.get(ref)
            if old is None or attempt:
                old = self.ref(ref) or ZERO
                if old == new:
                    break
            line = "%s %s %s\0 report-status agent=git/ui-rig" % (old, new, ref)
            if new == ZERO:
                line = "%s %s %s\0 report-status delete-refs agent=git/ui-rig" % (old, new, ref)
            reply = self._post("git-receive-pack", _pkt(line) + FLUSH + pack)
            text = reply.decode(errors="replace")
            if "ok " + ref in text:
                break
            self.note("push refused: %s" % text.strip()[:160])
            if attempt == 5:
                raise WireError("GitHub did not take the update of %s: %s" % (ref, text.strip()[:300]))
            time.sleep(0.5 * 2 ** attempt)
        if new == ZERO:
            self.known.pop(ref, None)
        else:
            self.known[ref] = new
