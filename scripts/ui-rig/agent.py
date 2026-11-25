"""The runner's side of the rig: takes steps from one session's git ref, does them on the phone (or in
the browser), and sends back pictures, the list of what is on screen, and anything that went wrong.

    agent.py --sid a1 --kind phone --options options.json --work DIR [--script steps.txt]

Steps are a fixed vocabulary (see README.md); nothing that arrives here is ever run as a command.
With --script it does the steps from the file instead (batch mode) and writes a report into DIR/out.
"""
import argparse
import base64
import difflib
import json
import os
import re
import shlex
import subprocess
import sys
import threading
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gitwire import Wire, WireError  # noqa: E402
from ios_driver import Hang, IOSDriver, StepError  # noqa: E402

HELP = ("tap doubletap press drag swipe scrollto pinch rotate type key clear back home open reopen background switcher "
        "tray orient theme textsize contrast allow deny ask photo launch kill wait waitfor gone shot full zoom tree video "
        "log crashes hangs perf hangcheck net plan store links mail clipboard settle")


def seconds(text, default):
    return float(text) if text else default


class Steps:
    """Runs one step at a time on a driver. Each method returns the text shown to the tester."""

    def __init__(self, driver, media_dir, control):
        self.d, self.media_dir, self.control = driver, media_dir, control
        self.files = {}

    def run(self, line):
        try:
            words = shlex.split(line, comments=False)
        except ValueError:
            words = line.split(None, 1)  # an apostrophe, as in: tap Don't save
        if not words:
            return ""
        verb, args = words[0].lower(), words[1:]
        method = getattr(self, "do_" + verb.replace("-", "_"), None)
        if method is None:
            close = difflib.get_close_matches(verb, HELP.split(), 1)
            raise StepError('no step is called "%s"%s. Steps: %s' % (verb, ', did you mean "%s"?' % close[0] if close else "", HELP))
        return method(args)

    @staticmethod
    def _need(args, count, usage):
        if len(args) < count:
            raise StepError("usage: " + usage)

    # ---- fingers

    def do_tap(self, a):
        self._need(a, 1, 'tap "Label" | tap @12 | tap 120,300')
        name = " ".join(a)
        try:
            x, y, what = self.d.point(name)
        except StepError:
            pressed = self.d.press_alert(name) if hasattr(self.d, "press_alert") else None
            if pressed:
                return 'pressed "%s" in the system message' % pressed
            raise
        self.d.tap(x, y)
        return "tapped " + what

    def do_doubletap(self, a):
        self._need(a, 1, 'doubletap "Label"|@12|x,y')
        x, y, what = self.d.point(" ".join(a))
        self.d.tap(x, y, times=2)
        return "double-tapped " + what

    def do_press(self, a):
        self._need(a, 1, 'press "Label"|@12|x,y [seconds]')
        hold = 1.2
        if len(a) > 1 and re.fullmatch(r"[\d.]+", a[-1]):
            hold = float(a.pop())
        x, y, what = self.d.point(" ".join(a))
        self.d.tap(x, y, hold=hold)
        return "held %s for %.1f s" % (what, hold)

    def do_drag(self, a):
        self._need(a, 2, 'drag FROM TO [seconds]   or   drag FROM by 40,-10 [seconds]')
        x1, y1, what = self.d.point(a[0])
        rest = a[1:]
        if rest[0] == "by":
            dx, dy = [float(v) for v in rest[1].split(",")]
            x2, y2, rest = x1 + dx, y1 + dy, rest[2:]
        else:
            x2, y2, _ = self.d.point(rest[0])
            rest = rest[1:]
        self.d.drag(x1, y1, x2, y2, seconds(rest[0] if rest else "", 0.6))
        return "dragged %s to %d,%d" % (what, x2, y2)

    def do_swipe(self, a):
        self._need(a, 1, "swipe up|down|left|right [on TARGET] [short|long]")
        way = a[0]
        if way not in ("up", "down", "left", "right"):
            raise StepError("swipe up, down, left or right")
        amount, rest = 0.5, a[1:]
        if rest and rest[-1] in ("short", "long"):
            amount = 0.25 if rest.pop() == "short" else 0.8
        x = y = None
        if rest:
            if rest[0] == "on":
                rest = rest[1:]
            x, y, _ = self.d.point(" ".join(rest))
        self.d.swipe(way, x, y, amount)
        return "swiped " + way

    def do_scrollto(self, a):
        self._need(a, 1, 'scrollto "Label"')
        name = " ".join(a)
        for way in ("up",) * 9 + ("down",) * 14:
            self.d.read_tree()
            if self.d.matches(name):
                return 'found "%s"' % name
            before = [(e["label"], round(e["y"])) for e in self.d.elements]
            self.d.swipe(way, None, None, 0.45)
            time.sleep(0.5)
            self.d.read_tree()
            if way == "up" and [(e["label"], round(e["y"])) for e in self.d.elements] == before:
                break
        for _ in range(14):
            if self.d.matches(name):
                return 'found "%s"' % name
            self.d.swipe("down", None, None, 0.45)
            time.sleep(0.5)
            self.d.read_tree()
        raise StepError('scrolled the whole screen and did not see "%s"' % name)

    def do_pinch(self, a):
        self._need(a, 2, 'pinch TARGET 2.0 (bigger) | 0.5 (smaller)')
        scale = float(a.pop())
        x, y, what = self.d.point(" ".join(a))
        self.d.pinch(x, y, scale)
        return "pinched %s by %.2f" % (what, scale)

    def do_rotate(self, a):
        self._need(a, 2, "rotate TARGET 45 (degrees, two fingers)")
        turn = float(a.pop())
        x, y, what = self.d.point(" ".join(a))
        self.d.pinch(x, y, 1.0, turn)
        return "turned %s by %.0f degrees" % (what, turn)

    # ---- keyboard

    def do_type(self, a):
        self._need(a, 1, 'type "some text" (tap the field first)')
        self.d.type_text(" ".join(a))
        return "typed"

    def do_key(self, a):
        self._need(a, 1, "key return|delete|space")
        self.d.key(a[0].lower())
        return "pressed " + a[0]

    def do_clear(self, a):
        count = int(a[0]) if a else 60
        for _ in range(0, count, 20):
            self.d.type_text("\b" * min(20, count))
        return "deleted up to %d characters before the cursor" % count

    # ---- getting around

    def do_back(self, a):
        self.d.back()
        return "went back"

    def do_home(self, a):
        self.d.home()
        return "left the hung app for another one" if getattr(self.d, "hung", False) else "pressed Home"

    def do_open(self, a):
        self._need(a, 1, "open https://... | open photos|safari|settings|files|snapreel")
        if ":" in a[0]:
            self.d.open_url(a[0])
        else:
            self.d.open_app(a[0])
        return "opened " + a[0]

    def do_reopen(self, a):
        self.d.activate()
        time.sleep(1)
        return "opened Snapreel again"

    def do_background(self, a):
        pause = seconds(a[0] if a else "", 5)
        self.d.home()
        time.sleep(pause)
        self.d.activate()
        time.sleep(1)
        return "left the app for %.0f s and came back" % pause

    def do_switcher(self, a):
        self.d.app_switcher()
        return "opened the app switcher"

    def do_tray(self, a):
        width, height = self.d.size
        self.d.drag(width * 0.3, 2, width * 0.3, height * 0.7, 0.4, 0)
        return "pulled down the notifications"

    def do_orient(self, a):
        self._need(a, 1, "orient portrait|landscape|landscape-right")
        self.d.orient(a[0])
        return "turned the phone to " + a[0]

    def do_launch(self, a):
        self.d.launch(a[0] if a else "", a[1] if len(a) > 1 else "")
        return "launched Snapreel" + (" (%s)" % " ".join(a) if a else "")

    def do_kill(self, a):
        self.d.kill()
        return "closed Snapreel (as if swiped away)"

    # ---- phone settings

    def do_theme(self, a):
        self._need(a, 1, "theme light|dark")
        self.d.theme(a[0])
        return "the phone is now " + a[0]

    def do_textsize(self, a):
        self._need(a, 1, "textsize xs|s|m|l|xl|xxl|xxxl|ax1..ax5")
        self.d.text_size(a[0].lower())
        return "text size " + a[0]

    def do_contrast(self, a):
        self._need(a, 1, "contrast on|off")
        self.d.contrast(a[0])
        return "increased contrast " + a[0]

    def _permission(self, verb, a):
        self._need(a, 1, verb + " photos|microphone|camera|speech|all")
        self.d.permission(verb, a[0].lower())
        return "%s: %s (iOS may close the app when this changes; `launch` opens it again)" % (a[0], verb)

    def do_allow(self, a):
        return self._permission("allow", a)

    def do_deny(self, a):
        return self._permission("deny", a)

    def do_ask(self, a):
        return self._permission("ask", a)

    def do_photo(self, a):
        listing = sorted(f for f in os.listdir(self.media_dir)) if os.path.isdir(self.media_dir) else []
        names = {os.path.splitext(f)[0]: f for f in listing}
        big = self._media_catalogue()
        if not a:
            return "videos and pictures you can add: " + ", ".join(sorted(set(names) | set(big)))
        there = [n for n in a if n in getattr(self.d, "preloaded", set())]
        a = [n for n in a if n not in there]
        if not a:
            return "%s: already in Photos" % ", ".join(there)
        for name in a:
            if name not in names and name in big:
                self._download_media(big[name])
                names = {os.path.splitext(f)[0]: f for f in os.listdir(self.media_dir)}
            if name not in names:
                raise StepError("no sample is called %s; there are: %s" % (name, ", ".join(sorted(set(names) | set(big)))))
            self.d.add_photo(os.path.join(self.media_dir, names[name]))
        return "added %s to Photos" % ", ".join(a)

    def _media_catalogue(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "media.json")
        with open(path) as f:
            return {m["name"]: m for m in json.load(f)["samples"]}

    def _download_media(self, item):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "get_media.sh")
        os.makedirs(self.media_dir, exist_ok=True)
        out = subprocess.run(["bash", script, item["pack"], self.media_dir], capture_output=True, text=True, timeout=900)
        if out.returncode != 0:
            raise StepError("the sample could not be fetched: " + (out.stderr or out.stdout)[-300:])

    def do_net(self, a):
        self._need(a, 1, "net online|offline|slow|error")
        return self._control("net", a[0])

    def do_plan(self, a):
        self._need(a, 1, "plan free|pro")
        return self._control("plan", a[0])

    def _control(self, key, value):
        if not self.control:
            raise StepError("this session has no practice server (it was started with --cloud off)")
        return self.control(key, value)

    def do_store(self, a):
        places = self.d.practice_store()
        return "put the practice store in %d places; `launch` and open the Pro page: it works if the prices are 6.11 and 41.11" % len(places)

    def do_links(self, a):
        """The made-up links of the practice website."""
        with open(self.d.opt.get("links", "")) as f:
            data = json.load(f)
        return "\n".join("%-30s open %s" % (k, v) for k, v in data["links"].items()) + "".join(
            "\n(not made: %s)" % p.split(":")[0] for p in data["problems"])

    def do_mail(self, a):
        """The newest emails the practice website sent."""
        import urllib.request
        base = self.d.opt.get("mail")
        if not base:
            raise StepError("this session has no mail box")
        with urllib.request.urlopen(base + "/api/v1/messages?limit=5", timeout=10) as reply:
            found = json.load(reply).get("messages", [])
        return "\n".join("%s to %s: %s: %s" % (m["Created"][11:19], ", ".join(t["Address"] for t in m["To"]), m["Subject"],
                                              m.get("Snippet", "")) for m in found) or "no mail yet"

    def do_clipboard(self, a):
        if a:
            subprocess.run(["xcrun", "simctl", "pbcopy", self.d.udid], input=" ".join(a), text=True, timeout=20)
            return "put that on the clipboard"
        out = subprocess.run(["xcrun", "simctl", "pbpaste", self.d.udid], capture_output=True, text=True, timeout=20).stdout
        return "clipboard: " + (out.strip() or "(empty)")

    # ---- waiting and looking

    def do_wait(self, a):
        time.sleep(min(seconds(a[0] if a else "", 2), 120))
        return "waited"

    def do_settle(self, a):
        self.d.settle(seconds(a[0] if a else "", 5))
        return "waited for the screen to stop moving"

    def do_waitfor(self, a):
        self._need(a, 1, 'waitfor "Label" [seconds]')
        limit = 20.0
        if len(a) > 1 and re.fullmatch(r"[\d.]+", a[-1]):
            limit = float(a.pop())
        started, name = time.time(), " ".join(a)
        while time.time() - started < min(limit, 600):
            self.d.read_tree()
            if self.d.matches(name):
                return '"%s" appeared after %.1f s' % (name, time.time() - started)
            time.sleep(0.5)
        raise StepError('"%s" did not appear within %.0f s' % (name, limit))

    def do_gone(self, a):
        self._need(a, 1, 'gone "Label" [seconds]')
        limit = 20.0
        if len(a) > 1 and re.fullmatch(r"[\d.]+", a[-1]):
            limit = float(a.pop())
        started, name = time.time(), " ".join(a)
        while time.time() - started < min(limit, 600):
            self.d.read_tree()
            if not self.d.matches(name):
                return '"%s" went away after %.1f s' % (name, time.time() - started)
            time.sleep(0.5)
        raise StepError('"%s" is still there after %.0f s' % (name, limit))

    def do_shot(self, a):
        return "picture taken"

    def do_full(self, a):
        self.files["full.jpg"] = self.d.screenshot("full.jpg", full=True)
        return "full-resolution picture: full.jpg"

    def do_zoom(self, a):
        self._need(a, 1, "zoom x,y,width,height")
        x, y, w, h = [float(v) for v in " ".join(a).replace(" ", ",").split(",") if v]
        self.files["zoom.jpg"] = self.d.zoom(x, y, w, h)
        return "close-up: zoom.jpg"

    def do_tree(self, a):
        self.d.read_tree()
        self.files["tree.txt"] = "\n".join(self.d.tree_lines(True)).encode()
        return "\n".join(self.d.tree_lines(bool(a))) if a else "%d things on screen (listed below; full list in tree.txt)" % len(self.d.elements)

    def do_video(self, a):
        self._need(a, 1, "video start|stop")
        if a[0] == "start":
            self.d.video_start()
            return "recording the screen"
        self.files["video.mp4"] = self.d.video_stop()
        return "recording: video.mp4"

    # ---- health

    def do_log(self, a):
        count = 60
        if a and a[0].isdigit():
            count = int(a.pop(0))
        lines = self.d.log_tail(min(count, 2000), " ".join(a))
        return "\n".join(l[:400] for l in lines) or "(nothing logged)"

    def do_crashes(self, a):
        self.d.new_crashes()
        for crash in self.d.crashes:
            self.files["crash-" + crash["file"]] = crash["text"].encode()
        return "\n\n".join("%s\n%s" % (c["file"], c["summary"]) for c in self.d.crashes) or "no crashes so far"

    def do_hangs(self, a):
        for number, hang in enumerate(self.d.hangs, 1):
            self.files["hang-%d.txt" % number] = hang["text"].encode()
        return "\n\n".join("%d. %s %s: main thread busy %d%%\n%s" % (i, h["at"], h["reason"], h["busy"], h["stack"])
                           for i, h in enumerate(self.d.hangs, 1)) or "no hangs so far"

    def do_perf(self, a):
        return self.d.perf(min(seconds(a[0] if a else "", 5), 60))

    def do_words(self, a):
        """For whoever works on the rig: the words read from the picture, and each layer's share of them."""
        words = self.d._read_words()
        node = self.d._http("GET", "/session/%s/source%s" % (self.d.session, self.d.SOURCE), timeout=30)["value"]
        found, layers = self.d._flatten(node)
        return json.dumps([[w[0]] + [round(v) for v in w[1:]] for w in words or []]) + "\n" + "\n".join(
            "%s %s %r %d,%d %dx%d" % (e["layers"], e["kind"], e["label"][:40], e["x"], e["y"], e["w"], e["h"]) for e in found)

    def do_mac(self, a):
        """For whoever works on the rig: what keeps the Mac busy."""
        if a and a[0] == "net":
            script = ("tail -8 /etc/hosts; for h in $(awk '/supabase|snapreel/{print $2}' /etc/hosts); do echo == $h; "
                      "dscacheutil -q host -a name $h; done; lsof -nP -iTCP:443 -sTCP:LISTEN 2>&1 | head -3; "
                      "sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>&1 | head -3; curl -s http://127.0.0.1:8899/ | tail -c 700; "
                      "tail -5 $W/stub/stub.log")
            return subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=60).stdout
        out = subprocess.run("uptime; memory_pressure | tail -1; ps -Ao pcpu,rss,command -r | cut -c1-210 | head -22; "
                             "echo; echo in the phone: $(ps -Ao command | grep -c RuntimeRoot), on the Mac: $(ps -Ao command | grep -vc RuntimeRoot)",
                             shell=True, capture_output=True, text=True, timeout=60).stdout
        return out

    def do_hangcheck(self, a):
        span = min(seconds(a[0] if a else "", 2), 10)
        share = self.d.main_busy(span) if hasattr(self.d, "main_busy") else None
        if share is not None and share < 0.3:
            return "not stuck: main thread busy %d%% of %.0f s" % (round(share * 100), span)
        found = self.d.main_thread(int(span))
        if found is None:
            return "Snapreel is not running"
        self.files["sample.txt"] = found[2].encode()
        return "main thread busy %d%% of the time\n%s" % (round(found[0] * 100), found[1] if found[0] > 0.3 else "")


class Agent:
    """Runs a list of steps and gathers the answer."""

    def __init__(self, driver, steps):
        self.d, self.steps = driver, steps

    def perform(self, lines, opts, keep=None):
        """{"results": [...], ...} and the files to send. `keep(i, line, shot)` gets each step's picture."""
        results, files, shot = [], {}, None
        self.steps.files = files
        each = opts.get("shots") == "each" or keep is not None
        started_all = time.time()
        for index, line in enumerate(lines):
            before = shot
            if each and before is None:
                before = self._quiet_shot()
            started = time.time()
            entry = {"step": line, "ok": True}
            try:
                entry["text"] = self.steps.run(line)
            except StepError as error:
                entry.update(ok=False, text=str(error))
            except Hang as error:
                entry.update(ok=False, text="the app did not answer (%s)" % error)
                self._report_hang(entry, 'during "%s"' % line)
            except Exception as error:  # the rig's own fault; say so instead of dying
                entry.update(ok=False, text="rig error: %s: %s" % (type(error).__name__, error), trace=traceback.format_exc()[-1500:])
            entry["seconds"] = round(time.time() - started, 1)
            if each:
                shot = self._quiet_shot(settle=True)
                if line.split()[0].lower() in ("tap", "doubletap", "press", "drag", "swipe", "pinch", "rotate", "key", "type"):
                    entry["changed"] = shot != before
                if keep:
                    keep(index, line, shot, entry)
                else:
                    files["step-%02d.jpg" % (index + 1)] = shot or b""
            self._check_app(entry)
            results.append(entry)
            if not entry["ok"] and not opts.get("carry_on"):
                for skipped in lines[index + 1:]:
                    results.append({"step": skipped, "ok": False, "text": "not done, because a step before it failed", "skipped": True})
                break
        answer = {"results": results}
        if not each and opts.get("shots") != "none":
            shot = self._quiet_shot(settle=True)
        if shot and opts.get("shots") != "none":
            files["shot.jpg"] = shot
        if opts.get("tree", True):
            self._tree_into(answer, results)
        use = self.d.usage()
        answer.update(size=list(self.d.size), keyboard=getattr(self.d, "keyboard", False), running=self.d.alive(),
                      cpu=use[0] if use else None, memory=use[1] if use else None, app=getattr(self.d, "app_label", ""),
                      slow_mac=getattr(self.d, "slow_mac", 0), took=round(time.time() - started_all, 1), crashes=len(self.d.crashes), hangs=len(self.d.hangs))
        return answer, {k: v for k, v in files.items() if v}

    def _quiet_shot(self, settle=False):
        try:
            return self.d.settle() if settle else self.d.screenshot()
        except (Hang, StepError, OSError, subprocess.SubprocessError):
            return None

    def _tree_into(self, answer, results):
        try:
            self.d.read_tree()
            answer["tree"] = self.d.tree_lines()
            answer["answer_time"] = round(self.d.answer_time, 1)
        except Hang as error:
            entry = {"step": "(look)", "ok": False, "text": "the app did not answer (%s)" % error}
            self._report_hang(entry, "after " + (results[-1]["step"] if results else "looking"))
            results.append(entry)
        except (StepError, OSError) as error:
            answer["tree"] = ["(the screen could not be read: %s)" % error]

    def _report_hang(self, entry, reason):
        if getattr(self.d, "hung", False):
            return  # reported when it began
        hang = self.d.check_hang(reason)
        if hang is None:
            entry["text"] += "; the app is slow to describe its screen, not hung" if self.d.alive() else "; Snapreel is not running"
        else:
            entry["hang"] = {k: hang[k] for k in ("at", "reason", "busy", "stack")}
            entry["hang"]["note"] = hang.get("note", "")
            self.steps.files["hang-%d.txt" % len(self.d.hangs)] = hang["text"].encode()

    def _check_app(self, entry):
        if self.d.kind != "phone" or self.d.pid is None or self.d.expected_gone or self.d.alive():
            return
        self.d.expected_gone = True
        fresh = self.d.wait_for_crash()
        if fresh:
            entry["crash"] = [c["summary"] for c in fresh]
            for crash in fresh:
                self.steps.files["crash-" + crash["file"]] = crash["text"].encode()
        else:
            entry["gone"] = "Snapreel is no longer running, and left no crash report (closed by iOS, or by a swipe in the app switcher)"


def step_limit(line):
    """The longest a step may honestly take, in seconds."""
    words = line.split()
    numbers = [float(w) for w in words[1:] if re.fullmatch(r"[\d.]+", w)]
    if not words:
        return 0
    if words[0] in ("wait", "waitfor", "gone", "background", "perf", "settle"):
        return 30 + (numbers[-1] if numbers else 20)
    return {"photo": 900, "launch": 240, "scrollto": 240, "video": 240, "log": 180, "store": 120}.get(words[0], 45)


# ---- live mode -------------------------------------------------------------------------------

class Live:
    def __init__(self, wire, sid, work):
        self.wire, self.sid, self.work = wire, sid, work
        self.in_ref, self.out_ref = "refs/rig/%s/in" % sid, "refs/rig/%s/out" % sid
        self.done = set()
        self.state = {"state": "starting", "note": "", "started": time.time()}

    def status(self, note, state="starting", **extra):
        self.state.update(state=state, note=note, at=time.time(), **extra)
        print("[%s] %s: %s" % (self.sid, state, note), flush=True)
        try:
            self.wire.push(self.out_ref + "/status", {"status.json": json.dumps(self.state).encode()}, "status")
        except WireError as error:
            print("status not sent: %s" % error, flush=True)

    def reload(self, agent, files, deadline, idle_minutes):
        """For whoever works on the rig: new rig files for a running phone, without starting it again."""
        here = os.path.dirname(os.path.abspath(__file__))
        for name, data in files.items():
            if re.fullmatch(r"[a-z_]+\.(py|sh|json|storekit|swift)", name) and name != "req.json":
                with open(os.path.join(here, name), "wb") as f:
                    f.write(data)
        self.start_over(agent, deadline, idle_minutes)

    def start_over(self, agent, deadline, idle_minutes):
        """Replaces this program with a fresh copy of itself; the phone and the app stay as they are."""
        state = dict(agent.d.state(), minutes=(deadline - time.time()) / 60, idle=idle_minutes)
        with open(os.path.join(self.work, "resume.json"), "w") as f:
            json.dump(state, f)
        args = [a for a in sys.argv if a != "--resume"]
        os.execv(sys.executable, [sys.executable] + args + ["--resume"])

    def watchdog(self, agent, request, deadline, idle_minutes):
        """If the steps take far too long, says where they got stuck and starts over."""
        limit = 100 + sum(step_limit(s) for s in request["steps"])
        me = threading.main_thread().ident

        def bite():
            frame = sys._current_frames().get(me)
            where = [l.strip().replace("\n", " | ") for l in traceback.format_stack(frame)[-6:]]
            print("stuck:\n" + "\n".join(where), flush=True)
            answer = {"id": request["id"], "ends": deadline, "size": list(agent.d.size), "results": [
                {"step": "; ".join(request["steps"]), "ok": False,
                 "text": "stuck for %d s, so the rig started its own side again; the app was left as it is. Look again, and "
                         "`launch` if it does not answer. (%s)" % (limit, where[-1][:200])}]}
            try:
                fresh = Wire(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
                fresh.push_fast(self.out_ref, {"res.json": json.dumps(answer).encode()})
            except WireError as error:
                print("not sent: %s" % error, flush=True)
            self.start_over(agent, deadline, idle_minutes)

        timer = threading.Timer(limit, bite)
        timer.daemon = True
        timer.start()
        return timer

    def serve(self, agent, minutes, idle_minutes):
        deadline, last_seen = time.time() + minutes * 60, time.time()
        seen = self.wire.refs(self.in_ref + "/") if self.state.get("resumed") else {}
        self.status("ready", "ready", device=agent.d.device, ios=agent.d.ios, size=list(agent.d.size), ends=deadline)
        fails = 0
        while True:
            now = time.time()
            if now > deadline:
                return "the session's time is up"
            if now - last_seen > idle_minutes * 60:
                return "nothing to do for %d minutes" % idle_minutes
            try:
                refs = self.wire.refs(self.in_ref + "/")
                fails = 0
            except WireError as error:
                fails += 1
                print("poll failed: %s" % error, flush=True)
                if fails > 20:
                    return "GitHub could not be reached"
                time.sleep(3)
                continue
            fresh = [(ref, sha) for ref, sha in refs.items() if seen.get(ref) != sha]
            if fresh:
                ref, sha = fresh[0]
                seen[ref] = sha
                request = json.loads(self.wire.fetch(sha)["req.json"])
                if request["id"] in self.done:
                    continue  # the same steps, arrived on a second lane
                self.done.add(request["id"])
                last_seen = time.time()
                if request.get("stop"):
                    return "stopped by the tester"
                if request.get("reload"):
                    self.reload(agent, self.wire.fetch(sha), deadline, idle_minutes)
                print("[%s] %s" % (self.sid, "; ".join(request["steps"])[:300]), flush=True)
                got = time.time()
                guard = self.watchdog(agent, request, deadline, idle_minutes) if hasattr(agent.d, "state") else None
                try:
                    answer, files = agent.perform(request["steps"], request.get("opts", {}))
                except Exception as error:  # whatever goes wrong, the phone stays and the tester hears about it
                    traceback.print_exc()
                    answer, files = {"results": [{"step": "; ".join(request["steps"]), "ok": False, "text": "rig error: %s: %s" % (
                        type(error).__name__, str(error)[:300])}], "size": list(agent.d.size)}, {}
                if guard:
                    guard.cancel()
                answer.update(id=request["id"], ends=deadline, waited=round(got - request.get("sent", got), 1), wire=self.wire.notes)
                self.wire.notes = []
                files = dict(files)
                files["res.json"] = json.dumps(answer).encode()
                try:
                    self.wire.push_fast(self.out_ref, files)
                except WireError as error:
                    print("result not sent: %s" % error, flush=True)
                last_seen = time.time()
            else:
                quiet = time.time() - last_seen
                time.sleep(0.3 if quiet < 60 else 1.0 if quiet < 300 else 2.5)


def batch(agent, script, out, opts):
    """Does every step of `script`, with a picture after each, and writes report.json, report.md and the pictures."""
    os.makedirs(out, exist_ok=True)
    lines = [l.strip() for l in open(script, encoding="utf-8") if l.strip() and not l.strip().startswith("#")]
    rows = []

    def keep(index, line, shot, entry):
        name = "%03d.jpg" % (index + 1)
        if shot:
            with open(os.path.join(out, name), "wb") as f:
                f.write(shot)
        print("%3d %-5s %s  %s" % (index + 1, "ok" if entry["ok"] else "FAIL", line, entry.get("text", "")[:120]), flush=True)
        rows.append(name)

    try:
        agent.d.video_start()
    except Exception as error:
        print("no recording: %s" % error, flush=True)
    answer, files = agent.perform(lines, dict(opts, shots="each", carry_on=True), keep)
    try:
        files["video.mp4"] = agent.d.video_stop()
    except Exception as error:
        print("no recording: %s" % error, flush=True)
    agent.d.new_crashes()
    for crash in agent.d.crashes:
        files["crash-" + crash["file"]] = crash["text"].encode()
    files["app-log.txt"] = "\n".join(agent.d.log_tail(50000, "", 90)).encode()
    for name, data in files.items():
        with open(os.path.join(out, name), "wb") as f:
            f.write(data)
    with open(os.path.join(out, "report.json"), "w") as f:
        json.dump(answer, f, indent=1)
    md = ["# Batch run", "", "%d steps, %d failed, %d crashes, %d hangs" % (
        len(answer["results"]), sum(not r["ok"] for r in answer["results"]), len(agent.d.crashes), len(agent.d.hangs)), ""]
    for number, r in enumerate(answer["results"], 1):
        md.append("%d. %s `%s` %s (%.1f s%s)%s" % (
            number, "ok" if r["ok"] else "**FAILED**", r["step"], r.get("text", "").split("\n")[0], r.get("seconds", 0),
            "" if r.get("changed", True) else ", screen did not change",
            " **HANG**" if r.get("hang") else " **CRASH**" if r.get("crash") else ""))
    with open(os.path.join(out, "report.md"), "w") as f:
        f.write("\n".join(md) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sid", required=True)
    parser.add_argument("--kind", default="phone")
    parser.add_argument("--options", required=True)
    parser.add_argument("--work", required=True)
    parser.add_argument("--app", default="")
    parser.add_argument("--wda", default="")
    parser.add_argument("--wait-for", default="", help="a file that appears when the app and driver are in place")
    parser.add_argument("--script", default="")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--prepare", default="", help="make a prepared phone into this folder instead")
    parser.add_argument("--say", default="", help="only report this status and leave")
    args = parser.parse_args()
    with open(args.options, encoding="utf-8") as f:
        options = json.load(f)
    wire = Wire(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"])
    live = Live(wire, args.sid, args.work)
    if args.say:
        live.status(args.say, options.get("say_state", "starting"))
        return 0

    def make():
        if args.kind == "web":
            from web_driver import WebDriver
            return WebDriver(args.sid, options, args.work, live.status)
        return IOSDriver(args.sid, options, args.work, live.status)

    control = None
    if options.get("control"):
        import urllib.request

        def control(key, value):
            request = urllib.request.Request("%s/%s/%s" % (options["control"], key, value), method="POST", data=b"")
            try:
                with urllib.request.urlopen(request, timeout=10) as reply:
                    return reply.read().decode()
            except urllib.error.HTTPError as error:
                raise StepError(error.read().decode()[:300])

    if args.prepare:
        import glob
        driver = make()
        samples = [p for p in sorted(glob.glob(os.path.join(args.work, "media", "*"))) if p.endswith((".mp4", ".jpg"))]
        samples.sort(key=os.path.getsize)
        try:
            name = driver.prepare(args.wda, samples, args.prepare)
            with open(os.environ["GITHUB_OUTPUT"], "a") as f:
                f.write("name=%s\n" % name)
            live.status("made " + name, "ended")
            return 0
        except (StepError, subprocess.SubprocessError, OSError) as error:
            traceback.print_exc()
            live.status("the phone could not be prepared: %s" % error, "failed")
            return 1

    driver, why = make(), "ended"
    code = 0
    try:
        if args.resume:
            with open(os.path.join(args.work, "resume.json")) as f:
                state = json.load(f)
            options.update(minutes=state.pop("minutes"), idle=state.pop("idle"), photos=[])
            live.state["resumed"] = True
            driver.resume(state)
        elif args.kind == "phone":
            driver._create()
            driver._boot()  # while the app is fetched or built
            waited = time.time()
            while args.wait_for and not os.path.exists(args.wait_for):
                if os.path.exists(args.wait_for + ".failed"):
                    raise StepError("the app could not be built: " + open(args.wait_for + ".failed").read()[-1500:])
                if time.time() - waited > 2400:
                    raise StepError("the app took too long to build")
                if int(time.time() - waited) % 20 == 0:
                    live.status("the phone is on; waiting for the app to be built")
                time.sleep(1)
            driver.finish_start(args.app, args.wda)
        else:
            driver.start()
        agent = Agent(driver, Steps(driver, os.path.join(args.work, "media"), control))
        for media in options.get("photos", []):
            live.status("adding the sample %s to Photos" % media)
            try:
                agent.steps.run("photo " + media)
            except (StepError, subprocess.SubprocessError) as error:
                live.state["missing"] = live.state.get("missing", "") + " %s not in Photos (%s)" % (media, error)
        if args.script:
            live.status("running the script", "batch")
            batch(agent, args.script, os.path.join(args.work, "out"), {})
            why = "the script is done"
        else:
            why = live.serve(agent, float(options.get("minutes", 120)), float(options.get("idle", 20)))
    except StepError as error:
        why, code = "could not start: %s" % error, 1
    except Exception as error:
        traceback.print_exc()
        why, code = "the rig failed: %s: %s" % (type(error).__name__, error), 1
    finally:
        live.status(why, "failed" if code else "ended")
        driver.stop()
    return code


if __name__ == "__main__":
    sys.exit(main())
