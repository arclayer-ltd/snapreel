"""Use the Snapreel iPhone app on a simulator in the cloud, from this PC. See README.md beside this file.

    python scripts/ui-rig/rig.py start mia --device small
    python scripts/ui-rig/rig.py do "launch fresh"
    python scripts/ui-rig/rig.py tap "Get started"
    python scripts/ui-rig/rig.py stop mia
"""
import argparse
import json
import os
import random
import re
import shlex
import subprocess
import sys
import tempfile
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from gitwire import AuthError, Wire, WireError  # noqa: E402

REPO = os.environ.get("RIG_REPO", "arclayer-ltd/snapreel")
OUT = os.environ.get("RIG_OUT") or os.path.join(tempfile.gettempdir(), "snapreel-rig")
RUNNERS = {"27": "xcode-27", "26": "macos-26", "18": "macos-15", "16": "macos-26"}
IOS_EXACT = {"16": "16.4"}
DEVICES = ("small", "se", "normal", "large", "iphonex")
OWN = ("start", "status", "list", "stop", "do", "look", "batch", "build", "media", "clean", "time", "reload", "image", "help")


def die(text, code=1):
    print("ERROR: " + text)
    sys.exit(code)


def gh(*args, check=True):
    try:
        out = subprocess.run(["gh"] + list(args), capture_output=True, text=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        die("the GitHub command line tool (gh) is not installed or not on the path")
    if check and out.returncode != 0:
        die("gh %s: %s" % (" ".join(args[:3]), (out.stderr or out.stdout).strip()[:400]))
    return out.stdout


def wire():
    token = os.environ.get("RIG_TOKEN") or gh("auth", "token").strip()
    if not token:
        die("not signed in to GitHub; run `gh auth login` first")
    return Wire(REPO, token)


# ---- what this PC remembers about each session ------------------------------------------------

def folder(sid):
    path = os.path.join(OUT, sid)
    os.makedirs(path, exist_ok=True)
    return path


def remember(sid, **values):
    path = os.path.join(folder(sid), "session.json")
    known = recall(sid)
    known.update(values)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(known, f)


def recall(sid):
    try:
        with open(os.path.join(OUT, sid, "session.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def known_sessions():
    if not os.path.isdir(OUT):
        return []
    return [s for s in sorted(os.listdir(OUT)) if recall(s) and not recall(s).get("over")]


def which(sid):
    if sid:
        return sid
    if os.environ.get("RIG_SESSION"):
        return os.environ["RIG_SESSION"]
    live = known_sessions()
    if len(live) == 1:
        return live[0]
    if not live:
        die("no session yet. Start one: python scripts/ui-rig/rig.py start NAME")
    die("several sessions are open (%s). Say which: python scripts/ui-rig/rig.py -s NAME ..." % ", ".join(live))


# ---- starting ---------------------------------------------------------------------------------

def bundle(extra=None):
    """The files of the throwaway branch: the workflow, the rig and any scripts."""
    files = {}
    with open(os.path.join(ROOT, ".github", "workflows", "ui-live.yml"), "rb") as f:
        files[".github/workflows/ui-live.yml"] = f.read().replace(b"\r\n", b"\n")
    for name in os.listdir(HERE):
        path = os.path.join(HERE, name)
        if os.path.isfile(path) and name.endswith((".py", ".sh", ".json", ".swift")):
            with open(path, "rb") as f:
                files["scripts/ui-rig/" + name] = f.read().replace(b"\r\n", b"\n")
    files.update(extra or {})
    return files


def cancel_runs(w, title):
    """Ends the run behind a session and removes its throwaway branch."""
    for line in gh("run", "list", "-R", REPO, "--branch", "ui-rig/" + title, "--json", "databaseId,status", "--jq",
                   '.[] | select(.status != "completed") | .databaseId', check=False).split():
        gh("run", "cancel", line, "-R", REPO, check=False)
        print("cancelled run " + line)
    if w.ref("refs/heads/ui-rig/" + title):
        w.delete("refs/heads/ui-rig/" + title)


def launch_job(name, settings, extra=None, again=False):
    w = wire()
    ref = "refs/heads/ui-rig/" + name
    if again and w.ref(ref):
        cancel_runs(w, name)
    if w.ref(ref):
        die("a session called %s is already starting or running; choose another name or stop it" % name)
    w.push(ref, bundle(extra), json.dumps(settings))
    return w


def check_ref(ref):
    out = subprocess.run(["gh", "api", "repos/%s/commits/%s" % (REPO, ref.replace("/", "%2F")), "--jq", ".sha"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        die('there is no branch or commit "%s" on GitHub (push it first)' % ref)
    return out.stdout.strip()


def cmd_start(a):
    names = a.names or ["t%04d" % random.randint(0, 9999)]
    phones = []
    for name in names:
        sid, _, device = name.partition(":")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,30}", sid):
            die("session names use small letters, digits and dashes: " + sid)
        phone = {"sid": sid, "device": device or a.device, "theme": a.theme}
        if a.photos:
            phone["photos"] = [p for p in a.photos.split(",") if p]
        phones.append(phone)
    kind = "web" if a.web else "phone"
    settings = {"title": "+".join(p["sid"] for p in phones), "job": kind, "phones": phones, "app_ref": check_ref(a.app),
                "app_name": a.app, "minutes": a.minutes, "idle": a.idle, "timeout": min(355, a.minutes + 75), "cloud": a.cloud,
                "kind": "live"}
    if a.web:
        for phone in phones:
            phone.update(device=a.web)
    else:
        if a.ios not in RUNNERS:
            die("--ios is one of " + ", ".join(RUNNERS))
        settings.update(runner=a.runner or RUNNERS[a.ios], ios=IOS_EXACT.get(a.ios, a.ios))
    w = wire()
    for phone in phones:
        sid = phone["sid"]
        if w.refs("refs/rig/%s/" % sid):
            if not a.again:
                note = read_status(w, sid)
                if note and note.get("state") not in ("ended", "failed") and time.time() - note.get("at", 0) < 3600:
                    die("a session called %s exists; stop it or choose another name (or add --again to replace it)" % sid)
            delete_refs(w, sid)
        w.push("refs/rig/%s/out/status" % sid, {"status.json": json.dumps(
            {"state": "queued", "note": "waiting for a free runner", "at": time.time(), "started": time.time()}).encode()}, "queued")
    launch_job(settings["title"], settings, again=a.again)
    for phone in phones:
        remember(phone["sid"], over=False, title=settings["title"], started=time.time(), count=0, kind=kind)
        print("session %s asked for (%s, app %s)" % (phone["sid"], phone["device"], a.app))
    if a.no_wait:
        print("check on it with: python scripts/ui-rig/rig.py status %s" % names[0])
        return
    wait_ready(w, [p["sid"] for p in phones], a.wait)


def read_status(w, sid):
    sha = w.ref("refs/rig/%s/out/status" % sid)
    return json.loads(w.fetch(sha)["status.json"]) if sha else None


def wait_ready(w, sids, minutes):
    end, last = time.time() + minutes * 60, {}
    waiting = list(sids)
    started = time.time()
    while waiting:
        for sid in list(waiting):
            status = read_status(w, sid) or {}
            note = "%s: %s" % (status.get("state"), status.get("note"))
            if note != last.get(sid):
                last[sid] = note
                print("  [%4.0f s] %s %s" % (time.time() - started, sid, note), flush=True)
            if status.get("state") == "ready":
                waiting.remove(sid)
                print("READY: %s is an %s with iOS %s, %s points, until %s" % (
                    sid, status.get("device"), status.get("ios"), "x".join(map(str, status.get("size", []))),
                    time.strftime("%H:%M", time.localtime(status.get("ends", 0)))), flush=True)
                if status.get("missing"):
                    print("but:%s; `rig.py -s %s photo NAME` tries again" % (status["missing"], sid))
            elif status.get("state") in ("failed", "ended"):
                remember(sid, over=True)
                die("session %s did not start: %s\nRun log: gh run list -R %s --branch ui-rig/%s" % (
                    sid, status.get("note"), REPO, recall(sid).get("title", sid)))
        if time.time() > end:
            die("still not ready after %d minutes (Mac runners may all be busy); it will go on starting. "
                "Check with: rig.py status" % minutes)
        if waiting:
            time.sleep(4)


# ---- using ------------------------------------------------------------------------------------

def step_limit(line):
    words = line.split()
    numbers = [float(w) for w in words[1:] if re.fullmatch(r"[\d.]+", w)]
    if not words:
        return 0
    if words[0] in ("wait", "waitfor", "gone", "background", "perf", "settle"):
        return 30 + (numbers[-1] if numbers else 20)
    return {"photo": 900, "launch": 240, "scrollto": 240, "video": 240, "log": 180}.get(words[0], 45)


def send(sid, steps, opts=None, limit=None):
    """Sends steps, waits for the answer: (answer, {file: path}, seconds)."""
    w = wire()
    started = time.time()
    request = {"id": uuid.uuid4().hex, "steps": steps, "opts": opts or {}, "sent": time.time()}
    out_ref, in_ref = "refs/rig/%s/out" % sid, "refs/rig/%s/in" % sid
    refs = w.refs("refs/rig/%s/" % sid)
    seen = {ref: sha for ref, sha in refs.items() if ref.startswith(out_ref)}
    w.known.update((in_ref + "/%d" % lane, refs.get(in_ref + "/%d" % lane, "0" * 40)) for lane in range(4))
    if not seen:
        remember(sid, over=True)
        die("there is no session called %s (it may have ended); open sessions: %s" % (sid, ", ".join(known_sessions()) or "none"))
    w.push_fast(in_ref, {"req.json": json.dumps(request).encode()})
    limit = limit or 200 + sum(step_limit(s) for s in steps)
    while True:
        answer = None
        for ref, sha in w.refs(out_ref + "/").items():
            if seen.get(ref) == sha:
                continue
            seen[ref] = sha
            files = w.fetch(sha)
            if "res.json" in files:
                answer = json.loads(files.pop("res.json"))
                if answer.get("id") == request["id"]:
                    break
                answer = None
            elif "status.json" in files:
                status = json.loads(files["status.json"])
                if status.get("state") in ("ended", "failed"):
                    remember(sid, over=True)
                    die("session %s is over: %s" % (sid, status.get("note")))
        if answer:
            break
        if time.time() - started > limit:
            status = read_status(w, sid) or {}
            if status.get("state") in ("ended", "failed"):
                remember(sid, over=True)
                die("session %s is over: %s" % (sid, status.get("note")))
            die("no answer after %d s. The session is %s (%s). Try `rig.py -s %s look`, or stop it and start another." % (
                limit, status.get("state", "gone"), status.get("note", ""), sid))
        time.sleep(0.15)
    count = int(recall(sid).get("count", 0)) + 1
    remember(sid, count=count)
    saved = {}
    for name, data in files.items():
        path = os.path.join(folder(sid), "%03d-%s" % (count, name))
        with open(path, "wb") as f:
            f.write(data)
        saved[name] = path
    with open(os.path.join(folder(sid), "history.txt"), "a", encoding="utf-8") as f:
        for r in answer["results"]:
            f.write("%03d %s %s -> %s%s\n" % (count, time.strftime("%H:%M:%S"), r["step"], "" if r["ok"] else "FAILED: ",
                                              r.get("text", "").split("\n")[0]))
    return answer, saved, time.time() - started


def show(answer, saved, took, quiet=False):
    bad = False
    for number, r in enumerate(answer["results"], 1):
        mark = "ok" if r["ok"] else "not done" if r.get("skipped") else "FAILED"
        bad = bad or not r["ok"]
        note = "" if r.get("changed", True) else "   [the screen did not change]"
        print("%d. %s: %s  -> %s%s" % (number, mark, r["step"], r.get("text", ""), note))
        if r.get("hang"):
            print("   *** HANG at %s (%s): main thread busy %d%%. %s" % (r["hang"]["at"], r["hang"]["reason"], r["hang"]["busy"],
                                                                        r["hang"].get("note", "")))
            print("   " + "\n   ".join(r["hang"]["stack"].split("\n")[-14:]))
        if r.get("crash"):
            print("   *** CRASH: Snapreel closed itself")
            print("   " + "\n   ".join(r["crash"][0].split("\n")[:16]))
        if r.get("gone"):
            print("   *** " + r["gone"])
        if r.get("trace") and os.environ.get("RIG_DEBUG"):
            print(r["trace"])
    for name in sorted(saved):
        if name != "shot.jpg":
            print("file: " + saved[name])
    state = []
    if answer.get("running") is False:
        state.append("Snapreel is not running")
    if answer.get("keyboard"):
        state.append("keyboard open")
    if answer.get("cpu") is not None:
        state.append("CPU %s%%" % answer["cpu"])
    if answer.get("memory") is not None:
        state.append("memory %s MB" % answer["memory"])
    if answer.get("answer_time") is not None:
        state.append("the app answered in %.1f s" % answer["answer_time"])
    if answer.get("slow_mac"):
        state.append("the Mac was slow %d time(s)" % answer["slow_mac"])
    if answer.get("crashes"):
        state.append("%d crash(es) so far" % answer["crashes"])
    if answer.get("hangs"):
        state.append("%d hang(s) so far" % answer["hangs"])
    if "shot.jpg" in saved:
        print("screen: %s  (%s points; 1 pixel = 1 point)" % (saved["shot.jpg"], "x".join(map(str, answer["size"]))))
    print("state: %s  [%s; %.1f s there and back]" % ("; ".join(state) or "fine", answer.get("app") or "?", took))
    if answer.get("tree") and not quiet:
        print("on screen:")
        for line in answer["tree"]:
            print("  " + line)
    return 2 if bad else 0


def cmd_do(a):
    sid = which(a.session)
    steps = [s for s in a.steps if s.strip()]
    if a.file:
        with open(a.file, encoding="utf-8") as f:
            steps += [l.strip() for l in f if l.strip() and not l.strip().startswith("#")]
    if not steps:
        die('give at least one step, for example: rig.py do "tap Settings" "swipe up"')
    opts = {"shots": "each" if a.each else "none" if a.no_shot else "last", "tree": not a.no_tree, "carry_on": a.carry_on}
    sys.exit(show(*send(sid, steps, opts), quiet=a.quiet))


def cmd_step(sid, words):
    """`rig.py tap Settings` is `rig.py do "tap Settings"`."""
    sid = which(sid)
    line = words[0] if len(words) == 1 else " ".join(shlex.quote(w) for w in words)
    if words[0] == "look":
        line = "shot"
    sys.exit(show(*send(sid, [line])))


def cmd_status(a):
    w = wire()
    for sid in ([a.name] if a.name else known_sessions()) or [None]:
        if sid is None:
            print("no open sessions on this PC")
            return
        status = read_status(w, sid)
        if status is None:
            print("%s: gone" % sid)
            remember(sid, over=True)
        else:
            print("%s: %s, %s (%d s ago)%s" % (sid, status.get("state"), status.get("note"), time.time() - status.get("at", time.time()),
                                              ", until " + time.strftime("%H:%M", time.localtime(status["ends"])) if status.get("ends") else ""))
            if status.get("state") in ("ended", "failed"):
                remember(sid, over=True)


def cmd_list(a):
    w = wire()
    found = sorted({r.split("/")[2] for r in w.refs("refs/rig/")})
    for sid in found:
        status = read_status(w, sid) or {}
        print("%-16s %-8s %s" % (sid, status.get("state", "?"), status.get("note", "")))
    if not found:
        print("no sessions on GitHub")


def delete_refs(w, sid):
    for ref in list(w.refs("refs/rig/%s/" % sid)):
        try:
            w.delete(ref)
        except WireError as error:
            print("left behind on GitHub: %s (%s); `rig.py clean` removes it later" % (ref, error))


def stop_one(w, sid):
    refs = w.refs("refs/rig/%s/" % sid)
    title = recall(sid).get("title", sid)
    if refs:
        w.push_fast("refs/rig/%s/in" % sid, {"req.json": json.dumps({"id": "stop", "stop": True, "steps": []}).encode()})
        end = time.time() + 25
        while time.time() < end:
            status = read_status(w, sid) or {}
            if status.get("state") in ("ended", "failed"):
                break
            time.sleep(1.5)
        else:
            # Not listening (still queued or starting): end its run instead, unless it hosts other phones.
            if "+" not in title:
                cancel_runs(w, title)
        delete_refs(w, sid)
    remember(sid, over=True)
    print("%s is stopped" % sid)


def cmd_stop(a):
    w = wire()
    names = known_sessions() if a.all else a.names or [which(None)]
    for sid in names:
        stop_one(w, sid)


def cmd_clean(a):
    """Deletes what ended sessions left on GitHub."""
    w = wire()
    running = set(gh("run", "list", "-R", REPO, "--workflow", "ui-live.yml", "--json", "headBranch,status", "--jq",
                     '.[] | select(.status != "completed") | .headBranch', check=False).split())
    busy = {s for b in running for s in b.replace("ui-rig/", "").split("+")}
    for ref in list(w.refs("refs/rig/")):
        if ref.split("/")[2] not in busy:
            w.delete(ref)
            print("deleted " + ref)
    for ref in list(w.refs("refs/heads/ui-rig/")):
        if ref.replace("refs/heads/", "") not in running:
            w.delete(ref)
            print("deleted " + ref)


def follow_run(branch, what):
    print("%s: waiting for the run" % what)
    started = time.time()
    run_id = None
    for _ in range(30):
        since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started - 60))
        run_id = gh("run", "list", "-R", REPO, "--branch", branch, "-L", "5", "--json", "databaseId,createdAt", "--jq",
                    '[.[] | select(.createdAt >= "%s")] | .[0].databaseId // empty' % since, check=False).strip()
        if run_id:
            break
        time.sleep(3)
    if not run_id:
        die("GitHub did not start a run for " + branch)
    print("https://github.com/%s/actions/runs/%s" % (REPO, run_id))
    last = ""
    while True:
        state = gh("run", "view", run_id, "-R", REPO, "--json", "status,conclusion", "--jq", '.status + " " + .conclusion', check=False).strip()
        if state != last:
            print("  [%s] %s" % (time.strftime("%H:%M:%S"), state), flush=True)
            last = state
        if state.startswith("completed"):
            return run_id, state.endswith("success")
        time.sleep(15)


def cmd_build(a):
    sha = check_ref(a.app)
    name = "build-" + sha[:10]
    launch_job(name, {"title": name, "job": "phone", "kind": "build", "phones": [], "app_ref": sha, "app_name": a.app, "minutes": 1,
                      "idle": 1, "timeout": 60, "cloud": "off", "runner": "xcode-27", "ios": ""})
    if a.no_wait:
        print("building %s (%s)" % (a.app, sha[:10]))
        return
    _, ok = follow_run("ui-rig/" + name, "build of %s" % a.app)
    if not ok:
        die("the build failed; open the run above, step \"The app\"")
    print("built and stored; sessions with --app %s start from it" % a.app)


def cmd_image(a):
    """Makes and stores a prepared phone, so that sessions with this device and iOS start quickly."""
    name = "image-%s-%s" % (a.device, a.ios)
    launch_job(name, {"title": name, "job": "image", "phones": [{"sid": name, "device": a.device, "theme": "light"}], "app_ref": "main",
                      "minutes": 60, "idle": 60, "timeout": 90, "cloud": "off", "runner": RUNNERS[a.ios],
                      "ios": IOS_EXACT.get(a.ios, a.ios)}, again=True)
    if a.no_wait:
        print("making a prepared phone (%s, iOS %s)" % (a.device, a.ios))
        return
    _, ok = follow_run("ui-rig/" + name, "prepared phone " + name)
    delete_refs(wire(), name)
    if not ok:
        die("the phone could not be prepared; see the run above")


def cmd_media(a):
    launch_job("media", {"title": "media", "job": "media", "phones": [], "app_ref": "main", "runner": "ubuntu-latest", "timeout": 60})
    _, ok = follow_run("ui-rig/media", "sample videos")
    if not ok:
        die("making the sample videos failed; see the run above")


def cmd_batch(a):
    sid = a.name or "b%04d" % random.randint(0, 9999)
    with open(a.script, "rb") as f:
        script = f.read().replace(b"\r\n", b"\n")
    settings = {"title": sid, "job": "phone", "kind": "batch", "phones": [{"sid": sid, "device": a.device, "theme": a.theme}],
                "app_ref": check_ref(a.app), "app_name": a.app, "minutes": a.minutes, "idle": 60, "timeout": a.minutes + 45,
                "cloud": a.cloud, "runner": RUNNERS[a.ios], "ios": IOS_EXACT.get(a.ios, a.ios)}
    if a.photos:
        settings["phones"][0]["photos"] = [p for p in a.photos.split(",") if p]
    launch_job(sid, settings, {"steps-%s.txt" % sid: script})
    run_id, ok = follow_run("ui-rig/" + sid, "batch " + sid)
    place = os.path.join(folder(sid), "batch")
    gh("run", "download", run_id, "-R", REPO, "-D", place, check=False)
    w = wire()
    delete_refs(w, sid)
    remember(sid, over=True)
    print("results: " + place)
    for base, _, files in os.walk(place):
        if "report.md" in files:
            with open(os.path.join(base, "report.md"), encoding="utf-8") as f:
                print(f.read())
    if not ok:
        die("the run did not finish cleanly; see agent-%s.log in the results" % sid)


def cmd_reload(a):
    """For whoever works on the rig: sends this folder's files to a running session."""
    sid, w = which(a.session), wire()
    files = {n.split("/")[-1]: d for n, d in bundle().items() if n.startswith("scripts/ui-rig/")}
    for name, data in files.items():
        if name.endswith(".py"):
            compile(data, name, "exec")  # a file that does not even parse would end the session
    files["req.json"] = json.dumps({"id": uuid.uuid4().hex, "reload": True, "steps": []}).encode()
    before = (read_status(w, sid) or {}).get("at", 0)
    w.push_fast("refs/rig/%s/in" % sid, files)
    for _ in range(60):
        status = read_status(w, sid) or {}
        if status.get("at", 0) > before:
            print("%s: %s, %s" % (sid, status.get("state"), status.get("note")))
            return
        time.sleep(1)
    die("no sign of the session after the reload")


def cmd_time(a):
    """How long a command takes there and back."""
    sid = which(a.session)
    for label, steps, opts in (("look (picture and list)", ["shot"], {}), ("bare", ["wait 0"], {"shots": "none", "tree": False})):
        times = []
        for _ in range(a.count):
            answer, _, took = send(sid, steps, opts)
            times.append((took, answer["took"]))
        times.sort()
        print("%s: %s s there and back (of which %s s on the phone)" % (
            label, ", ".join("%.1f" % t for t, _ in times), ", ".join("%.1f" % p for _, p in times)))


def main():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    # Git Bash rewrites "/pricing" into a Windows path; put it back.
    argv = [re.sub(r"^[A-Za-z]:/Program Files/Git/", "/", v) for v in sys.argv[1:]]
    session = None
    if len(argv) >= 2 and argv[0] in ("-s", "--session"):
        session, argv = argv[1], argv[2:]
    if not argv or argv[0] in ("help", "-h", "--help"):
        print(__doc__)
        with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
            print(f.read())
        return
    if argv[0] not in OWN or argv[0] == "look":
        return cmd_step(session, argv)
    parser = argparse.ArgumentParser(prog="rig.py")
    subs = parser.add_subparsers(dest="command")

    def phone_options(p):
        p.add_argument("--device", default="iphonex", choices=DEVICES, help="iphonex, small (both 375x812), se, normal, large")
        p.add_argument("--ios", default="16", help="16 (oldest supported, fastest here), 18, 26 or 27 (newest)")
        p.add_argument("--app", default="main", help="branch or commit of the app")
        p.add_argument("--theme", default="light", choices=("light", "dark"))
        p.add_argument("--photos", default="", help="samples to put in Photos at the start, e.g. short,4min")
        p.add_argument("--minutes", type=int, default=120, help="the session ends after this long")
        p.add_argument("--cloud", default="stub", choices=("stub", "off"), help="stub: practice server; off: every online service unreachable")

    p = subs.add_parser("start")
    p.add_argument("names", nargs="*", help="session names; name:device for several on one runner")
    phone_options(p)
    p.add_argument("--web", default="", choices=("", "phone", "desktop"), help="a Chrome browser instead of a phone")
    p.add_argument("--idle", type=int, default=20, help="the session ends after this many minutes without a command")
    p.add_argument("--runner", default="")
    p.add_argument("--wait", type=int, default=40)
    p.add_argument("--no-wait", action="store_true")
    p.add_argument("--again", action="store_true")
    p.set_defaults(run=cmd_start)
    p = subs.add_parser("do")
    p.add_argument("steps", nargs="*")
    p.add_argument("--file")
    p.add_argument("--each", action="store_true", help="a picture after every step")
    p.add_argument("--no-shot", action="store_true")
    p.add_argument("--no-tree", action="store_true")
    p.add_argument("--quiet", action="store_true", help="do not print the list of what is on screen")
    p.add_argument("--carry-on", action="store_true", help="go on after a step that fails")
    p.set_defaults(run=cmd_do)
    p = subs.add_parser("status")
    p.add_argument("name", nargs="?")
    p.set_defaults(run=cmd_status)
    subs.add_parser("list").set_defaults(run=cmd_list)
    p = subs.add_parser("stop")
    p.add_argument("names", nargs="*")
    p.add_argument("--all", action="store_true", help="every session this PC started")
    p.set_defaults(run=cmd_stop)
    subs.add_parser("clean").set_defaults(run=cmd_clean)
    p = subs.add_parser("build")
    p.add_argument("--app", default="main")
    p.add_argument("--no-wait", action="store_true")
    p.set_defaults(run=cmd_build)
    p = subs.add_parser("image")
    p.add_argument("--device", default="small", choices=DEVICES)
    p.add_argument("--ios", default="27", choices=sorted(RUNNERS))
    p.add_argument("--no-wait", action="store_true")
    p.set_defaults(run=cmd_image)
    subs.add_parser("media").set_defaults(run=cmd_media)
    p = subs.add_parser("batch")
    p.add_argument("script")
    p.add_argument("--name", default="")
    phone_options(p)
    p.set_defaults(run=cmd_batch)
    subs.add_parser("reload").set_defaults(run=cmd_reload)
    p = subs.add_parser("time")
    p.add_argument("--count", type=int, default=5)
    p.set_defaults(run=cmd_time)
    a = parser.parse_args(argv)
    a.session = session
    a.run(a)


if __name__ == "__main__":
    try:
        main()
    except AuthError as error:
        die(str(error))
    except WireError as error:
        die(str(error) + ". Check this PC's internet connection and try again.")
    except KeyboardInterrupt:
        sys.exit(130)
