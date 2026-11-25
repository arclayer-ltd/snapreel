"""One simulated iPhone: boot it, put the app on it, and do what a finger, an eye and a Settings
app can do. Runs on the macOS runner. WebDriverAgent (Appium's, prebuilt, pinned by checksum) does
the touching and reads the accessibility tree; `simctl` does everything else. Standard library only.

Every coordinate is in points, and the screenshots sent back are scaled to one pixel per point, so
the picture's pixels are the numbers to tap.
"""
import base64
import glob
import hashlib
import http.client
import json
import math
import os
import re
import select
import shutil
import signal
import socket
import subprocess
import threading
import time

BUNDLE = "co.arclayer.snapreel"
WDA_BUNDLE = "com.facebook.WebDriverAgentRunner.xctrunner"
DEVICE_DIR = os.path.expanduser("~/Library/Developer/CoreSimulator/Devices")
REPORTS = os.path.expanduser("~/Library/Logs/DiagnosticReports")

# First name that the newest runtime accepts wins.
DEVICES = {
    "se": ["iPhone SE (3rd generation)", "iPhone SE (2nd generation)", "iPhone 8"],      # 375x667
    "small": ["iPhone 13 mini", "iPhone 12 mini", "iPhone 11 Pro", "iPhone X"],          # 375x812
    "iphonex": ["iPhone X", "iPhone XS", "iPhone 11 Pro", "iPhone 13 mini"],             # 375x812
    "normal": ["iPhone 17", "iPhone 16", "iPhone 15", "iPhone 14"],
    "large": ["iPhone 18 Pro Max", "iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 15 Pro Max",
              "iPhone 14 Pro Max"],
}

SYSTEM_APPS = {
    "photos": "com.apple.mobileslideshow", "safari": "com.apple.mobilesafari",
    "settings": "com.apple.Preferences", "files": "com.apple.DocumentsApp",
    "messages": "com.apple.MobileSMS", "snapreel": BUNDLE,
}

TEXT_SIZES = {
    "xs": "extra-small", "s": "small", "m": "medium", "l": "large", "default": "large", "xl": "extra-large",
    "xxl": "extra-extra-large", "xxxl": "extra-extra-extra-large", "ax1": "accessibility-medium",
    "ax2": "accessibility-large", "ax3": "accessibility-extra-large",
    "ax4": "accessibility-extra-extra-large", "ax5": "accessibility-extra-extra-extra-large",
}

# Background services the app never uses; without them a phone starts sooner and leaves the Mac's three cores to the app.
IDLE_JOBS = ["assistantd", "searchd", "corespotlightd", "photoanalysisd", "mediaanalysisd", "triald", "suggestd", "duetexpertd",
             "proactived", "healthd", "newsd", "weatherd", "ap.adprivacyd", "ap.promotedcontentd", "tipsd", "biomed",
             "intelligenceplatformd", "generativeexperiencesd", "modelmanagerd", "knowledgeconstructiond", "siriknowledged",
             "siriinferenced", "financed", "passd", "gamed", "homed", "sportsd", "stocksd", "milod", "routined", "navd",
             "maps.destinationd", "apsd", "itunescloudd", "bookdatastored", "remindd", "calaccessd", "appstored.updates"]

PERMISSIONS = {
    "photos": "photos", "photos-add": "photos-add", "microphone": "microphone", "mic": "microphone",
    "camera": "camera", "speech": "speech-recognition", "all": "all", "contacts": "contacts",
    "location": "location",
}

INTERACTIVE = {"Button", "Switch", "Slider", "TextField", "SecureTextField", "TextView", "SearchField", "Link",
               "Cell", "SegmentedControl", "Tab", "PickerWheel", "Toggle", "Stepper", "MenuItem", "Key"}


class StepError(Exception):
    """The step could not be done; the text says why in words a tester understands."""


class Hang(Exception):
    """The app stopped answering."""


def plain(t):
    """For comparing: no capitals, straight quotes."""
    return t.lower().replace("\u2019", "'").replace("\u2018", "'")


def run(*args, timeout=60, check=True, **kw):
    out = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout,
                         errors="replace", **kw)
    if check and out.returncode != 0:
        raise StepError("%s failed: %s" % (" ".join(map(str, args[:4])), (out.stderr or out.stdout).strip()[-300:]))
    return out.stdout


def simctl(*args, **kw):
    return run("xcrun", "simctl", *args, **kw)


class IOSDriver:
    kind = "phone"

    def __init__(self, sid, options, work, status):
        self.sid, self.opt, self.work, self.status = sid, options, work, status
        self.port = 8100 + int(options.get("index", 0))
        self.udid = None
        self.pid = None
        self.expected_gone = True
        self.session = None
        self.size = (375, 812)
        self.elements = []
        self.started = time.time()
        self.seen_reports = set(self._reports())
        self.crashes = []
        self.hangs = []
        self.video = None
        self.cpu_mark = None
        self.hang_after = float(options.get("hang_after", 8))
        self.conn = None
        self.wda_stuck = False  # the touch driver is still waiting for a hung app
        self.ocr, self.ocr_used, self.no_ocr, self.words = None, False, False, []
        self.photos_ready = False
        self.preloaded, self.restored = set(), False
        self.slow_mac = 0       # how often the Mac, not the app, was the slow one
        self.away = False       # a hung app was left for another one
        self.hung = False       # the app's main thread was busy and not answering when last looked at
        os.makedirs(work, exist_ok=True)

    # ---- setting up ------------------------------------------------------------------------

    def finish_start(self, app, wda):
        """After the phone is on: put the app and the touch driver on it."""
        self.app = app
        self.status("installing the app")
        if not (self.restored and simctl("get_app_container", self.udid, WDA_BUNDLE, check=False).strip()):
            self._put(wda)
        self._install()
        self._trust()
        self.status("starting the touch driver")
        self._start_wda()
        self._warm_up()

    def state(self):
        return {k: getattr(self, k) for k in ("udid", "device", "ios", "size", "pid", "expected_gone", "app", "crashes", "hangs",
                                                  "video", "hung", "away", "photos_ready", "restored")} | {
            "preloaded": sorted(self.preloaded), "seen_reports": sorted(self.seen_reports)}

    def pause(self):
        self._drop()

    def resume(self, state):
        self.__dict__.update(state)
        self.size, self.preloaded, self.seen_reports = tuple(self.size), set(self.preloaded), set(self.seen_reports)
        try:
            self._open_session()
        except (Hang, StepError, OSError, http.client.HTTPException, KeyError):
            self._drop()
            try:
                self._start_wda()
            except StepError as error:
                print("the touch driver is not back yet: %s" % error, flush=True)
                self.session, self.wda_stuck = self.session or "none", True

    def _trust(self):
        """The practice server's certificate (made on this runner a minute ago)."""
        cert = self.opt.get("ca")
        if cert and os.path.exists(cert):
            simctl("keychain", self.udid, "add-root-cert", cert, check=False)

    def _create(self):
        want = self.opt.get("ios", "")
        data = json.loads(simctl("list", "runtimes", "-j"))["runtimes"]
        runtimes = [r for r in data if r.get("platform") == "iOS" and r.get("isAvailable")
                    and re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-\d+-\d+", r["identifier"])]
        runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True)
        if want:
            runtimes = [r for r in runtimes if r["version"] == want or r["version"].startswith(want + ".")]
            if not runtimes:
                raise StepError("this runner has no iOS %s simulator" % want)
        names = DEVICES.get(self.opt.get("device", "small"), [self.opt.get("device")])
        problem = ""
        if not self.opt.get("prepare") and runtimes and self._restore(runtimes[0]["version"]):
            return
        for runtime in runtimes:
            for name in names:
                out = subprocess.run(["xcrun", "simctl", "create", "rig-" + self.sid, name, runtime["identifier"]],
                                     capture_output=True, text=True)
                if out.returncode == 0:
                    self.udid = out.stdout.strip()
                    self.device, self.ios = name, runtime["version"]
                    return
                problem = out.stderr.strip()[-200:]
        raise StepError("no simulator could be made for %s (%s)" % (names, problem))

    # ---- prepared phones: one that was started, settled and filled with samples once, and put away

    def _image_name(self, version):
        chip = "" if os.uname().machine == "arm64" else "-intel"
        return "ui-device-%s-%s%s-v1" % (self.opt.get("device", "small"), version, chip)

    def _restore(self, version):
        """Brings back the prepared phone of this kind, if one is stored. Much faster than a new one."""
        here = os.path.dirname(os.path.abspath(__file__))
        place = os.path.join(self.work, "device")
        self.status("looking for a prepared phone")
        begun = time.time()
        try:
            got = subprocess.run(["bash", os.path.join(here, "find_artifact.sh"), self._image_name(version), place],
                                 capture_output=True, text=True, timeout=600)
            if got.returncode != 0:
                return False
            with open(os.path.join(place, "phone.json")) as f:
                info = json.load(f)
            if os.path.exists(os.path.join(DEVICE_DIR, info["udid"])):
                return False  # another phone on this runner is already that one
            os.makedirs(DEVICE_DIR, exist_ok=True)
            run("tar", "-xzf", os.path.join(place, "device.tgz"), "-C", DEVICE_DIR, timeout=600)
            os.remove(os.path.join(place, "device.tgz"))
            run("pkill", "-9", "-f", "CoreSimulatorService", check=False)
            end = time.time() + 40
            while time.time() < end:
                time.sleep(2)
                listed = json.loads(simctl("list", "devices", "-j", check=False, timeout=120) or "{}").get("devices", {})
                if any(d["udid"] == info["udid"] and d.get("isAvailable") for ds in listed.values() for d in ds):
                    self.udid, self.device, self.ios = info["udid"], info["device"], info["ios"]
                    self.preloaded, self.photos_ready, self.restored = set(info["samples"]), True, True
                    print("prepared phone back after %.0f s" % (time.time() - begun), flush=True)
                    return True
            print("the prepared phone was not accepted", flush=True)
        except (OSError, ValueError, KeyError, StepError, subprocess.SubprocessError) as error:
            print("no prepared phone: %s" % error, flush=True)
        return False

    def prepare(self, wda, samples, out):
        """Makes a prepared phone: started, settled, the touch driver on it, the samples in Photos."""
        self._create()
        self._boot()
        self._put(wda)
        self._start_wda()
        added = []
        for path in samples:
            self.status("adding %s" % os.path.basename(path))
            try:
                self.add_photo(path, limit=600)
                added.append(os.path.splitext(os.path.basename(path))[0])
            except StepError as error:
                print("not added: %s: %s" % (path, error), flush=True)
        for bundle in ("com.apple.mobileslideshow", "com.apple.Preferences", "com.apple.mobilesafari"):
            simctl("launch", self.udid, bundle, check=False, timeout=120)
            time.sleep(8)
            try:  # Photos asks to send notifications; unanswered, the question would lie over every later screen
                self.press_alert("Allow")
            except (StepError, Hang, OSError):
                pass
            simctl("terminate", self.udid, bundle, check=False)
        end = time.time() + 420
        while time.time() < end and os.getloadavg()[0] > 2.0:  # let first-start work finish
            time.sleep(10)
        print("load %.1f; shutting the phone down" % os.getloadavg()[0], flush=True)
        simctl("shutdown", self.udid, timeout=240)
        os.makedirs(out, exist_ok=True)
        run("tar", "-czf", os.path.join(out, "device.tgz"), "--options", "gzip:compression-level=3",
            "--exclude", "*/Library/Logs/*", "--exclude", "*/var/db/diagnostics/*", "--exclude", "*/var/db/uuidtext/*",
            "-C", DEVICE_DIR, self.udid, timeout=1200)
        with open(os.path.join(out, "phone.json"), "w") as f:
            json.dump({"udid": self.udid, "device": self.device, "ios": self.ios, "samples": added}, f)
        print("%s: %.0f MB, samples %s" % (self._image_name(self.ios), os.path.getsize(os.path.join(out, "device.tgz")) / 1e6, added), flush=True)
        return self._image_name(self.ios)

    def _boot(self):
        light = ["--disabledJob=com.apple." + job for job in IDLE_JOBS]
        begun = time.time()
        for attempt in range(4):
            self.status("starting %s, iOS %s%s" % (self.device, self.ios, ", try %d" % (attempt + 1) if attempt else ""))
            subprocess.run(["xcrun", "simctl", "boot", self.udid] + light, capture_output=True)
            try:
                done = subprocess.run(["xcrun", "simctl", "bootstatus", self.udid], capture_output=True, text=True, timeout=600)
                print("boot try %d: %d after %.0f s: %s" % (attempt + 1, done.returncode, time.time() - begun,
                                                            done.stdout.strip()[-300:]), flush=True)
                if done.returncode == 0:
                    self._prepare()
                    return
            except subprocess.TimeoutExpired as error:
                print("boot try %d: not up after 10 minutes: %s" % (attempt + 1, str(error.stdout)[-300:]), flush=True)
            subprocess.run(["xcrun", "simctl", "shutdown", self.udid], capture_output=True)
            if attempt == 1:  # shutting down keeps the first-start work already done; wiping loses it
                subprocess.run(["xcrun", "simctl", "erase", self.udid], capture_output=True)
        raise StepError("the simulator did not start")

    def _prepare(self):
        for key in ("DidShowContinuousPathIntroduction", "DidShowGestureKeyboardIntroduction"):
            simctl("spawn", self.udid, "defaults", "write", "com.apple.keyboard.preferences", key, "-bool", "true", check=False)
        # The software keyboard shows, as on a phone, and autocorrect does not rewrite typed text.
        simctl("spawn", self.udid, "defaults", "write", "com.apple.Preferences", "KeyboardAutocorrection", "-bool", "false", check=False)
        simctl("ui", self.udid, "appearance", self.opt.get("theme", "light"), check=False)
        simctl("status_bar", self.udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
               "--cellularMode", "active", "--cellularBars", "4", "--wifiBars", "3", check=False)

    def _install(self):
        self._put(self.app)

    def _put(self, app):
        """Installs an app; a phone that has just started sometimes drops the first tries."""
        for attempt in range(4):
            try:
                simctl("install", self.udid, app, timeout=240)
                return
            except (StepError, subprocess.TimeoutExpired) as error:
                print("install try %d: %s" % (attempt + 1, error), flush=True)
                if attempt == 3:
                    raise StepError("the app could not be installed: %s" % error)
                time.sleep(5)
                subprocess.run(["xcrun", "simctl", "boot", self.udid], capture_output=True)
                subprocess.run(["xcrun", "simctl", "bootstatus", self.udid], capture_output=True)

    def _start_wda(self):
        env = dict(os.environ, SIMCTL_CHILD_USE_PORT=str(self.port), SIMCTL_CHILD_MJPEG_SERVER_PORT=str(self.port + 1000))
        problem = ""
        again = self.session is not None  # it ran before: do not spend minutes on it now
        if again:
            # One that waits for a hung app does not even let itself be closed.
            run("pkill", "-9", "-f", "Devices/%s/.*WebDriverAgentRunner" % self.udid, check=False)
        for attempt in range(2 if again else 4):
            try:
                out = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process",
                                      "--stdout=" + os.path.join(self.work, "wda.log"), "--stderr=" + os.path.join(self.work, "wda.log"),
                                      self.udid, WDA_BUNDLE], env=env, capture_output=True, text=True,
                                     timeout=60 if again else 180)
                if out.returncode:
                    problem = "launch: " + out.stderr.strip()[-160:]
            except subprocess.TimeoutExpired:
                problem = "launching it took too long"
            end = time.time() + (40 if again else 90 if attempt == 0 else 60)
            while time.time() < end:
                try:
                    self._http("GET", "/status", timeout=5)
                    self._open_session()
                    print("touch driver up (try %d)" % (attempt + 1), flush=True)
                    if again and self.alive() and not self.away:
                        self.activate()  # starting it put itself in front
                    return
                except (OSError, http.client.HTTPException, StepError, Hang, KeyError) as error:
                    problem = "%s: %s" % (type(error).__name__, error)
                    self._drop()
                    time.sleep(1)
            print("touch driver, try %d: %s" % (attempt + 1, problem), flush=True)
            if not again:
                self.status("starting the touch driver, try %d (%s)" % (attempt + 2, problem[:160]))
        raise StepError("the touch driver did not start (%s)" % problem)

    def _open_session(self):
        reply = self._http("POST", "/session", {"capabilities": {"alwaysMatch": {}}}, timeout=30)
        self.session = reply.get("sessionId") or reply["value"]["sessionId"]
        self._wda("POST", "/appium/settings", {"settings": {
            "waitForIdleTimeout": 0, "animationCoolOffTimeout": 0, "screenshotQuality": 1, "snapshotMaxDepth": 90,
            "customSnapshotTimeout": self.hang_after, "respectSystemAlerts": True, "shouldUseCompactResponses": True}})
        size = self._wda("GET", "/window/size")
        self.size = (int(size["width"]), int(size["height"]))

    def _warm_up(self):
        for _ in range(3):
            try:
                self.screenshot()
                self.read_tree(timeout=60)
                return
            except (Hang, StepError, OSError):
                time.sleep(1)

    # ---- talking to the touch driver -------------------------------------------------------

    def _drop(self):
        if self.conn is not None:
            self.conn.close()
        self.conn = None

    def _http(self, method, path, body=None, timeout=30):
        if self.conn is None:
            self.conn = http.client.HTTPConnection("127.0.0.1", self.port)
        self.conn.timeout = timeout
        if self.conn.sock is not None:
            self.conn.sock.settimeout(timeout)
        data = None if body is None else json.dumps(body).encode()
        try:
            self.conn.request(method, path, data, {"Content-Type": "application/json"})
            reply = json.loads(self.conn.getresponse().read() or b"{}")
        except socket.timeout:
            self._drop()
            raise Hang("no answer within %.0f s" % timeout)
        except (OSError, http.client.HTTPException):
            self._drop()
            raise
        value = reply.get("value")
        if isinstance(value, dict) and value.get("error"):
            raise StepError("%s: %s" % (value["error"], str(value.get("message", ""))[:300]))
        return reply

    HUNG = ("it is hung, and the rig cannot touch or list anything until it is closed; pictures, `home` and `reopen` work, "
            "`launch` closes and opens it")

    def _still_hung(self):
        """A quick look (about 2 s) at a hung app: has it come back by itself?"""
        if not self.hung:
            return False
        if self.away:
            # Behind another app iOS puts it to sleep, but the touch driver still waits for its answer.
            self.hung = self.alive()
        else:
            self.hung = self.alive() and (self.main_busy() or 0) > 0.6
        return self.hung

    def _wda(self, method, path, body=None, timeout=30):
        if self.hung and self._still_hung():
            raise Hang(self.HUNG)
        if self.wda_stuck:
            self._start_wda()
            self.wda_stuck = False
        for attempt in range(2):
            try:
                return self._http(method, "/session/%s%s" % (self.session, path), body, timeout).get("value")
            except StepError as error:
                if attempt == 0 and "invalid session" in str(error):
                    self._open_session()
                    continue
                raise
            except (ConnectionError, http.client.HTTPException, OSError):
                if attempt:
                    raise StepError("the touch driver is not answering")
                self._start_wda()

    # ---- looking ---------------------------------------------------------------------------

    def _raw_shot(self, path):
        if self.hung or self.wda_stuck:
            run("xcrun", "simctl", "io", self.udid, "screenshot", "--type=jpeg", path, timeout=40)
            return
        try:
            data = base64.b64decode(self._wda("GET", "/screenshot", timeout=10))
            with open(path, "wb") as f:
                f.write(data)
        except (Hang, StepError, OSError):
            self._drop()
            run("xcrun", "simctl", "io", self.udid, "screenshot", "--type=jpeg", path, timeout=30)

    def screenshot(self, name="shot.jpg", full=False):
        raw = os.path.join(self.work, "raw-" + name)
        out = os.path.join(self.work, name)
        self._raw_shot(raw)
        if full:
            run("sips", "-s", "format", "jpeg", "-s", "formatOptions", "85", raw, "--out", out, timeout=30)
        else:
            run("sips", "-s", "format", "jpeg", "-s", "formatOptions", "82", "-z", self.size[1], self.size[0], raw, "--out", out,
                timeout=30)
        with open(out, "rb") as f:
            return f.read()

    def zoom(self, x, y, w, h):
        raw = os.path.join(self.work, "raw-zoom.jpg")
        out = os.path.join(self.work, "zoom.jpg")
        self._raw_shot(raw)
        info = run("sips", "-g", "pixelWidth", raw)
        scale = int(re.search(r"pixelWidth: (\d+)", info).group(1)) / float(self.size[0])
        run("sips", "-s", "format", "jpeg", "-s", "formatOptions", "90", "--cropOffset", int(y * scale), int(x * scale),
            "-c", max(1, int(h * scale)), max(1, int(w * scale)), raw, "--out", out)
        with open(out, "rb") as f:
            return f.read()

    def settle(self, limit=2.5):
        """Waits until the picture stops changing (or `limit`); returns the last picture."""
        end, last = time.time() + limit, None
        while True:
            shot = self.screenshot()
            if last == shot or time.time() > end:
                return shot
            last = shot

    # No visibility or accessibility attributes: working those out runs inside the app and can stall it for a minute.
    SOURCE = "?format=json&excluded_attributes=visible,accessible"

    def read_tree(self, timeout=None):
        """Fills self.elements with what is on screen, in reading order, numbered from 1."""
        started = time.time()
        if self.hung and self._still_hung():
            raise Hang(self.HUNG)
        if self.wda_stuck:
            self._start_wda()
            self.wda_stuck = False
        try:
            node = self._http("GET", "/session/%s/source%s" % (self.session, self.SOURCE),
                              timeout=timeout or self.hang_after)["value"]
        except Hang:
            self.wda_stuck = True
            if (self.main_busy() or 0) > 0.5:
                raise  # the app really is busy
            # Its main thread has nothing to do, so it is the Mac that is slow: wait for it.
            self.slow_mac += 1
            try:
                node = self._http("GET", "/session/%s/source%s" % (self.session, self.SOURCE), timeout=60)["value"]
                self.wda_stuck = False
            except Hang:
                raise StepError("the Mac is too busy to read the screen at the moment (the app itself is idle); try again")
        except (ConnectionError, http.client.HTTPException, OSError):
            self._start_wda()
            node = self._wda("GET", "/source" + self.SOURCE, timeout=30)
        self.answer_time = time.time() - started
        if isinstance(node, str):
            node = json.loads(node)
        self.far = []
        self.offscreen, self.app_label = 0, node.get("label") or node.get("name") or ""
        self.keyboard = False
        found, layers = self._flatten(node)
        if layers:
            hidden = self._hidden_layers(found, layers)
            found = [e for e in found if not hidden.intersection(e["layers"])]
            self._shift_picker(found)
        unique, seen = [], set()
        named = {(e["label"], round(e["x"] + e["w"] / 2), round(e["y"] + e["h"] / 2)) for e in found if e["kind"] in INTERACTIVE}
        for e in found:
            middle = (e["label"], round(e["x"] + e["w"] / 2), round(e["y"] + e["h"] / 2))
            key = (e["kind"], e["label"], e["value"], round(e["x"]), round(e["y"]), round(e["w"]), round(e["h"]))
            if key in seen or (e["kind"] not in INTERACTIVE and e["label"] and middle in named):
                continue
            seen.add(key)
            unique.append(e)
        self.elements = unique
        self.ocr_used = bool(layers)
        for number, e in enumerate(unique, 1):
            e["n"] = number
        return unique

    def _flatten(self, node):
        """The tree as a list of what could matter to a person, each with the overlapping layers it is in.

        A layer is one of several big siblings lying over each other: the app's tabs, or the screen under a sheet.
        """
        found, layers = [], set()
        width, height = self.size

        def box(n):
            rect = n.get("rect") or n.get("frame") or {}
            if isinstance(rect, str):
                rect = dict(zip(("x", "y", "width", "height"), [float(v) for v in re.findall(r"-?[\d.]+", rect)]))
            return [float(rect.get(k, 0) or 0) for k in ("x", "y", "width", "height")]

        def labelled(n, want=2):
            count = 1 if (n.get("label") or "").strip() else 0
            for child in n.get("children") or []:
                if count >= want:
                    break
                count += labelled(child, want - count)
            return count

        def walk(n, depth, parent_text, path):
            kind = (n.get("type") or "").replace("XCUIElementType", "")
            x, y, w, h = box(n)
            name, value = n.get("rawIdentifier") or "", n.get("value")
            if kind == "Application" and depth == 0 and w:
                self.size = (int(w), int(h))
            if kind == "Keyboard":
                self.keyboard = True
            text = str(n.get("label") or "").strip()
            shown = str(value).strip() if value not in (None, "") else ""
            if kind == "Switch":
                shown = {"1": "on", "0": "off"}.get(shown, shown)
            elif kind in ("Button", "Tab", "Cell") and shown == "1":
                shown = "selected"
            if kind in ("Image", "Other", "StaticText") and parent_text and (kind == "Image" or text in parent_text):
                text = shown = ""  # the picture or words on a button, already named by it
            if text.startswith(("Vertical scroll bar", "Horizontal scroll bar")):
                return
            wanted = kind in INTERACTIVE or text or (shown and kind != "Other")
            if wanted and kind not in ("Application", "Window", "Keyboard", "Key"):
                item = {"kind": kind, "label": text, "value": shown, "id": name, "x": x, "y": y, "w": w, "h": h, "layers": path,
                        "enabled": str(n.get("isEnabled", n.get("enabled", "1"))) not in ("0", "false", "False"),
                        "selected": str(n.get("isSelected", n.get("selected", "0"))) in ("1", "true", "True")}
                cx, cy = x + w / 2, y + h / 2
                if w > 0 and h > 0 and x < width and y < height and x + w > 0 and y + h > 0:
                    item["onscreen"] = 0 <= cx <= width and 0 <= cy <= height
                    found.append(item)
                else:
                    self.offscreen += 1
                    if text:
                        self.far.append((text, x, y))
            children = n.get("children") or []
            big = []
            if len(children) > 1 and kind not in ("Cell", "Button"):
                for c in children:
                    cx, cy, cw, ch = box(c)
                    if cw >= width * 0.7 and ch >= height * 0.45 and labelled(c) >= 2:
                        big.append(id(c))
            for child in children:
                inner = path
                if len(big) > 1 and id(child) in big:
                    layers.add(len(layers) + 1)
                    inner = path + (len(layers),)
                walk(child, depth + 1, text if kind in INTERACTIVE else parent_text, inner)

        walk(node, 0, "", ())
        return found, layers

    def _shift_picker(self, found):
        """iOS 16 gives the Photos picker's things positions inside its sheet, not on the screen: move them down."""
        for index, e in enumerate(found):
            if e["kind"] == "Button" and e["label"] == "Cancel" and e["y"] < 30:
                real = [y + h / 2 for text, x, y, w, h in self.words if text.strip() == "cancel" and x < self.size[0] / 2]
                down = real[0] - (e["y"] + e["h"] / 2) if real else 0
                if down > 15:
                    for other in found[index:]:
                        other["y"] += down
                        other["onscreen"] = 0 <= other["y"] + other["h"] / 2 <= self.size[1]
                return

    def _hidden_layers(self, found, layers):
        """Which of the overlapping layers a person cannot see: their words are not in the picture."""
        words = self._read_words()
        self.words = words or []
        if words is None or len(words) < 2:
            return set()  # no words read: nothing can be told from that
        hidden, best = set(), (0, None)
        for layer in sorted(layers, reverse=True):  # inner ones first
            seen = missing = 0
            for e in found:
                if layer not in e["layers"] or hidden.intersection(e["layers"]) or not e["onscreen"]:
                    continue
                wanted = [w for w in re.findall(r"[a-z0-9]{3,}", plain(e["label"]))][:8]
                if not wanted or e["kind"] not in ("StaticText", "Button", "Link", "Cell") or e["h"] > self.size[1] * 0.5:
                    continue
                near = " ".join(text for text, x, y, w, h in words if x < e["x"] + e["w"] + 12 and x + w > e["x"] - 12
                                and y < e["y"] + e["h"] + 8 and y + h > e["y"] - 8)
                if sum(w in near for w in wanted) >= max(1, (len(wanted) + 1) // 2):
                    seen += 1
                elif e["kind"] != "Button" or " " in e["label"]:
                    missing += 1  # (an icon button's name is never in the picture)
            if missing >= 2 and seen <= missing * 0.4:
                hidden.add(layer)
            if seen > best[0]:
                best = (seen, layer)
        if all(hidden.intersection(e["layers"]) for e in found if e["layers"]):
            # Something must be on screen: keep the layer whose words fit best, with the ones around it.
            keep = {best[1]} if best[1] else set(hidden)
            for e in found:
                if best[1] in e["layers"]:
                    keep.update(e["layers"])
            hidden -= keep
        return hidden

    def _read_words(self):
        """The words in the current picture, as (lower-case text, x, y, width, height) in points; None without them."""
        try:
            if self.ocr is None:
                tool = self.opt.get("ocr") or os.path.join(os.environ.get("W", "/nonexistent"), "ocr")
                if not os.path.exists(tool):
                    if self.no_ocr:
                        return None
                    self.no_ocr = True  # one try
                    source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ocr.swift")
                    run("swiftc", "-O", source, "-o", tool, timeout=240)
                self.ocr = subprocess.Popen([tool], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
            path = os.path.join(self.work, "raw-words.jpg")
            self._raw_shot(path)
            self.ocr.stdin.write(path + "\n")
            self.ocr.stdin.flush()
            if not select.select([self.ocr.stdout], [], [], 8)[0]:
                raise OSError("no answer")
            width, height = self.size
            return [(t.lower(), x * width, y * height, w * width, h * height) for t, x, y, w, h in json.loads(self.ocr.stdout.readline())]
        except (OSError, ValueError, StepError, Hang) as error:
            print("words could not be read: %s" % error, flush=True)
            if self.ocr is not None:
                self.ocr.kill()
            self.ocr = None
            return None

    def tree_lines(self, everything=False):
        lines = []
        for e in self.elements:
            extra = ""
            if e["value"] and e["value"] != e["label"]:
                extra += ' value="%s"' % e["value"][:60]
            if not e["enabled"]:
                extra += " DISABLED"
            if e["selected"]:
                extra += " selected"
            if not e["onscreen"]:
                extra += " (partly off screen)"
            label = e["label"].replace("\n", " / ")
            if len(label) > 110 and not everything:
                label = label[:107] + "..."
            lines.append('@%d %s "%s" at %d,%d size %dx%d%s' % (
                e["n"], e["kind"], label or e["id"], e["x"] + e["w"] / 2, e["y"] + e["h"] / 2, e["w"], e["h"], extra))
        cap = 400 if everything else 110
        if len(lines) > cap:
            lines = lines[:cap] + ["... %d more (use `tree all`)" % (len(lines) - cap)]
        if self.offscreen:
            lines.append("(%d more further down or off screen)" % self.offscreen)
        return lines

    # ---- finding things --------------------------------------------------------------------

    def point(self, target, wait=4.0):
        """(x, y, description) for "Label", @12, 120,300, Button:Label, or Label#2."""
        target = target.strip()
        match = re.fullmatch(r"(-?[\d.]+)\s*,\s*(-?[\d.]+)", target)
        if match:
            return float(match.group(1)), float(match.group(2)), "point " + target
        if re.fullmatch(r"@\d+", target):
            number = int(target[1:])
            for e in self.elements:
                if e["n"] == number:
                    return self._aim(e)
            raise StepError("there is no element %s in the last list" % target)
        end = time.time() + wait
        while True:
            self.read_tree()
            found = self.matches(target)
            if found or time.time() > end:
                break
            time.sleep(0.3)
        if not found:
            away = [(e["label"], e["x"], e["y"]) for e in self.elements if not e["onscreen"]] + getattr(self, "far", [])
            for label, x, y in away:
                if plain(target.split(":")[-1]) in plain(label):
                    side = "below" if y >= self.size[1] - 30 else "above" if y < 0 else "to the left" if x < 30 else "to the right"
                    raise StepError('"%s" is there but off the screen (%s): swipe to it first' % (label[:60], side))
            near = [e["label"] for e in self.elements if e["label"] and e["onscreen"]][:25]
            raise StepError('nothing on screen is called "%s". On screen: %s' % (target, "; ".join(near)))
        return self._aim(found[0], len(found))

    def matches(self, target):
        kind, nth, text = None, None, target
        match = re.fullmatch(r"(.*)#(\d+)", text)
        if match:
            text, nth = match.group(1).strip(), int(match.group(2))
        match = re.fullmatch(r"([A-Z][A-Za-z]+):(.+)", text)
        if match and match.group(1) in INTERACTIVE | {"StaticText", "Image", "Other"}:
            kind, text = match.group(1), match.group(2)
        low = plain(text)
        whole = re.compile(r"(?<![a-z0-9])" + re.escape(low) + r"(?![a-z0-9])")
        pool = [e for e in self.elements if e["onscreen"] and (kind is None or e["kind"] == kind)]
        for test in (lambda e: e["label"] == text, lambda e: plain(e["label"]) == low,
                     lambda e: e["id"] == text, lambda e: plain(e["value"]) == low,
                     lambda e: plain(e["label"]).startswith(low) and whole.search(plain(e["label"])),
                     lambda e: whole.search(plain(e["label"])),
                     lambda e: plain(e["label"]).startswith(low), lambda e: low in plain(e["label"]),
                     lambda e: low in plain(e["value"])):
            found = [e for e in pool if test(e)]
            if found:
                if kind is None:
                    # A control wins over the plain text inside or beside it.
                    found.sort(key=lambda e: (e["kind"] not in INTERACTIVE, e["w"] * e["h"]))
                if nth:
                    found = sorted(found, key=lambda e: (e["y"], e["x"]))
                    return found[nth - 1:nth]
                return found
        return []

    def _aim(self, e, count=1):
        x, y = e["x"] + e["w"] / 2, e["y"] + e["h"] / 2
        if e["kind"] in ("Switch", "Toggle") and e["w"] > 110:
            x = e["x"] + e["w"] - 30  # a whole row is the switch; a person touches the knob
        width, height = self.size
        x, y = min(max(x, 2), width - 2), min(max(y, 2), height - 2)
        note = '%s "%s" at %d,%d' % (e["kind"], e["label"] or e["id"], x, y)
        if not e["enabled"]:
            note += " (it is DISABLED)"
        if count > 1:
            note += " (first of %d with that name; add #2 for the next)" % count
        return x, y, note

    # ---- touching --------------------------------------------------------------------------

    def _fingers(self, *paths, seconds=60):
        actions = []
        for index, path in enumerate(paths):
            actions.append({"type": "pointer", "id": "finger%d" % index, "parameters": {"pointerType": "touch"},
                            "actions": path})
        try:
            self._wda("POST", "/actions", {"actions": actions}, timeout=seconds)
        except Hang:
            self.wda_stuck = True
            raise

    @staticmethod
    def _move(x, y, ms=0):
        return {"type": "pointerMove", "duration": int(ms), "x": round(x, 1), "y": round(y, 1), "origin": "viewport"}

    DOWN, UP = {"type": "pointerDown", "button": 0}, {"type": "pointerUp", "button": 0}

    @staticmethod
    def _pause(ms):
        return {"type": "pause", "duration": int(ms)}

    def tap(self, x, y, times=1, hold=0.06):
        path = [self._move(x, y)]
        for _ in range(times):
            path += [self.DOWN, self._pause(hold * 1000), self.UP, self._pause(70)]
        self._fingers(path)

    def drag(self, x1, y1, x2, y2, seconds=0.6, hold=0.15):
        steps = max(4, min(30, int(seconds / 0.03)))
        path = [self._move(x1, y1), self.DOWN, self._pause(hold * 1000)]
        for i in range(1, steps + 1):
            path.append(self._move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, seconds * 1000 / steps))
        path += [self._pause(80), self.UP]
        self._fingers(path)

    def swipe(self, direction, x=None, y=None, amount=0.5):
        width, height = self.size
        x = width / 2 if x is None else x
        y = height / 2 if y is None else y
        dx, dy = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}[direction]
        rx, ry = dx * width * amount, dy * height * amount
        x1, y1 = x - rx / 2, y - ry / 2
        x2, y2 = x + rx / 2, y + ry / 2
        clamp = lambda v, top: min(max(v, 6), top - 6)
        path = [self._move(clamp(x1, width), clamp(y1, height)), self.DOWN]
        for i in range(1, 9):
            path.append(self._move(clamp(x1 + (x2 - x1) * i / 8, width), clamp(y1 + (y2 - y1) * i / 8, height), 22))
        path.append(self.UP)
        self._fingers(path)

    def pinch(self, x, y, scale, turn=0.0, seconds=0.7):
        """Two fingers around (x, y): spread or close by `scale`, turned by `turn` degrees."""
        width, height = self.size
        room = min(x, y, width - x, height - y)
        near = max(16.0, min(45.0, room / 3))
        far = min(near * scale, max(room - 4, near + 10)) if scale >= 1 else near
        start = near if scale >= 1 else min(near / scale, max(room - 4, near + 10))
        end = far if scale >= 1 else start * scale
        paths, steps = [], 14
        for side in (0, math.pi):
            path = []
            for i in range(steps + 1):
                t = i / steps
                radius = start + (end - start) * t
                angle = side + math.radians(turn) * t - math.pi / 4
                move = self._move(x + radius * math.cos(angle), y + radius * math.sin(angle),
                                  0 if i == 0 else seconds * 1000 / steps)
                path.append(move)
                if i == 0:
                    path += [self.DOWN, self._pause(60)]
            path += [self._pause(60), self.UP]
            paths.append(path)
        self._fingers(*paths)

    def type_text(self, text):
        for start in range(0, len(text), 40):
            self._wda("POST", "/wda/keys", {"value": list(text[start:start + 40])}, timeout=40)

    def key(self, name):
        keys = {"return": "\n", "enter": "\n", "delete": "\b", "backspace": "\b", "space": " ", "tab": "\t"}
        if name not in keys:
            raise StepError("keys: " + ", ".join(sorted(keys)))
        self._wda("POST", "/wda/keys", {"value": [keys[name]]}, timeout=30)

    def alert_buttons(self):
        try:
            return self._wda("GET", "/wda/alert/buttons", timeout=10) or []
        except (StepError, Hang):
            return []

    def press_alert(self, name):
        buttons = self.alert_buttons()
        for button in buttons:
            if plain(name) in plain(button):
                self._wda("POST", "/alert/accept", {"name": button}, timeout=15)
                return button
        return None

    def home(self):
        if self.hung:
            # The touch driver waits for the hung app, so another app is brought to the front instead.
            simctl("launch", self.udid, SYSTEM_APPS["settings"], check=False)
            time.sleep(2)
            self.away = True
            return
        self._wda("GET", "/window/size", timeout=20)  # (restarts the touch driver if it is stuck)
        self._http("POST", "/wda/homescreen", {}, timeout=20)

    def back(self):
        width, height = self.size
        path = [self._move(1, height / 2), self.DOWN]
        for i in range(1, 11):
            path.append(self._move(1 + (width * 0.75) * i / 10, height / 2, 22))
        path.append(self.UP)
        self._fingers(path)

    def app_switcher(self):
        width, height = self.size
        self.drag(width / 2, height - 3, width / 2, height * 0.45, 0.5, 0)

    def orient(self, way):
        ways = {"portrait": "PORTRAIT", "landscape": "LANDSCAPE", "landscape-left": "LANDSCAPE",
                "landscape-right": "UIA_DEVICE_ORIENTATION_LANDSCAPERIGHT"}
        if way not in ways:
            raise StepError("orient: portrait, landscape, landscape-right")
        try:
            self._wda("POST", "/orientation", {"orientation": ways[way]}, timeout=20)
        except StepError as error:
            if "Rotate" in str(error):
                raise StepError("this screen stays as it is when the phone is turned to " + way)
            raise
        time.sleep(0.8)
        size = self._wda("GET", "/window/size")
        self.size = (int(size["width"]), int(size["height"]))

    # ---- the app ---------------------------------------------------------------------------

    def launch(self, mode="", argument=""):
        args, env = [], dict(os.environ)
        if mode in ("sample", "screen"):
            args = ["-screen", argument if mode == "screen" else (argument or "shell.home")]
        elif mode == "fresh":
            simctl("terminate", self.udid, BUNDLE, check=False)
            simctl("uninstall", self.udid, BUNDLE, check=False)
            simctl("privacy", self.udid, "reset", "all", BUNDLE, check=False)
            simctl("keychain", self.udid, "reset", check=False)
            self._trust()
            self._install()
        elif mode not in ("", "again"):
            raise StepError("launch, launch fresh, launch sample, launch screen <id>")
        out = simctl("launch", "--terminate-running-process",
                     "--stdout=" + os.path.join(self.work, "stdout.log"), "--stderr=" + os.path.join(self.work, "stderr.log"),
                     self.udid, BUNDLE, *args, env=env, timeout=90)
        match = re.search(r": (\d+)", out)
        self.pid = int(match.group(1)) if match else None
        self.expected_gone = False
        self.hung = self.away = False
        self.cpu_mark = None
        # Until it shows something: the first picture is otherwise the empty launch screen.
        end = time.time() + 15
        while time.time() < end:
            time.sleep(0.7)
            try:
                if sum(1 for e in self.read_tree() if e["label"]) > 1:
                    break
            except (Hang, StepError, OSError):
                break
        self.settle(4)  # the entrance animation

    def activate(self):
        self.away = False
        if self.hung:
            simctl("launch", self.udid, BUNDLE, check=False, timeout=60)
            time.sleep(2)
            return
        out = simctl("launch", self.udid, BUNDLE, timeout=60)
        match = re.search(r": (\d+)", out)
        self.pid = int(match.group(1)) if match else self.pid
        self.expected_gone = False

    def open_app(self, name):
        bundle = SYSTEM_APPS.get(name.lower(), name)
        if bundle == BUNDLE:
            return self.activate()
        simctl("launch", self.udid, bundle, timeout=60)
        time.sleep(1.5)

    def kill(self):
        self.expected_gone = True
        self.hung = False
        simctl("terminate", self.udid, BUNDLE, check=False)

    def open_url(self, url):
        if not re.match(r"^[a-z][a-z0-9+.-]*:", url):
            raise StepError("give a full address, for example https://... or snapreel://...")
        simctl("openurl", self.udid, url, timeout=60)
        time.sleep(1.5)
        self._refresh_pid()

    def alive(self):
        if not self.pid:
            return False
        try:
            os.kill(self.pid, 0)
            return True
        except OSError:
            return False

    def _refresh_pid(self):
        out = simctl("spawn", self.udid, "launchctl", "list", check=False)
        match = re.search(r"^(\d+)\s+\S+\s+UIKitApplication:%s\[" % re.escape(BUNDLE), out, re.M)
        if match:
            self.pid = int(match.group(1))
            self.expected_gone = False
        return self.pid

    # ---- settings of the phone -------------------------------------------------------------

    def permission(self, verb, what):
        name = PERMISSIONS.get(what)
        if not name:
            raise StepError("permissions: " + ", ".join(sorted(PERMISSIONS)))
        simctl("privacy", self.udid, {"allow": "grant", "deny": "revoke", "ask": "reset"}[verb], name, BUNDLE)
        # iOS closes an app whose permission changes; that is not a crash.
        self.expected_gone = True

    def theme(self, value):
        if value not in ("light", "dark"):
            raise StepError("theme light or theme dark")
        simctl("ui", self.udid, "appearance", value)

    def text_size(self, value):
        if value not in TEXT_SIZES:
            raise StepError("text sizes, small to huge: xs s m l xl xxl xxxl ax1 ax2 ax3 ax4 ax5 (default = l)")
        simctl("ui", self.udid, "content_size", TEXT_SIZES[value])

    def contrast(self, value):
        simctl("ui", self.udid, "increase_contrast", "enabled" if value == "on" else "disabled")

    def practice_store(self):
        """Xcode's StoreKit testing without Xcode: the simulator's store daemon reads a configuration Xcode
        would have put there. Undocumented, so it may stop working with any iOS; the prices tell."""
        base = os.path.expanduser("~/Library/Developer/CoreSimulator/Devices/%s/data" % self.udid)
        source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "practice.storekit")
        places = [os.path.join(base, "Library/Caches/com.apple.storekitagent/Octane", BUNDLE)]
        for daemon in glob.glob(os.path.join(base, "Containers/Data/InternalDaemon/*")):
            plist = os.path.join(daemon, ".com.apple.mobile_container_manager.metadata.plist")
            try:
                with open(plist, "rb") as f:
                    if b"storekit" in f.read().lower():
                        places.append(os.path.join(daemon, "Library/Caches/Octane", BUNDLE))
                        places.append(os.path.join(daemon, "Library/Caches/com.apple.storekitagent/Octane", BUNDLE))
            except OSError:
                pass
        for place in places:
            os.makedirs(place, exist_ok=True)
            shutil.copy(source, os.path.join(place, "Configuration.storekit"))
        simctl("spawn", self.udid, "launchctl", "kickstart", "-k", "user/501/com.apple.storekitd", check=False)
        simctl("spawn", self.udid, "launchctl", "kickstart", "-k", "system/com.apple.storekitd", check=False)
        run("pkill", "-f", "%s.*storekit" % self.udid, check=False)
        return places

    def add_photo(self, path, limit=None):
        if not self.photos_ready:
            # A new simulator has no photo library until Photos has run; adding to it then can hang.
            simctl("launch", self.udid, SYSTEM_APPS["photos"], check=False, timeout=120)
            time.sleep(6)
            simctl("terminate", self.udid, SYSTEM_APPS["photos"], check=False)
            self.photos_ready = True
            if self.alive():
                self.activate()
        limit = limit or 150 + os.path.getsize(path) / 4e6
        for attempt in range(3):
            try:
                simctl("addmedia", self.udid, path, timeout=limit)
                return
            except subprocess.TimeoutExpired:
                print("addmedia %s: no answer in %.0f s" % (path, limit), flush=True)
                for daemon in ("com.apple.assetsd", "com.apple.photoanalysisd"):
                    simctl("spawn", self.udid, "launchctl", "kickstart", "-k", "user/foreground/" + daemon, check=False)
                time.sleep(3)
        raise StepError("the phone's Photos did not take it; try again in a minute")

    # ---- health ----------------------------------------------------------------------------

    def _reports(self):
        return glob.glob(os.path.join(REPORTS, "Snapreel*")) + glob.glob(os.path.join(REPORTS, "Retired", "Snapreel*"))

    def new_crashes(self):
        """Crash reports of this phone's app since the last call: [{summary, file, text}]."""
        fresh = []
        for path in self._reports():
            if path in self.seen_reports:
                continue
            try:
                with open(path, errors="replace") as f:
                    text = f.read()
            except OSError:
                continue
            if self.udid and "/Devices/" in text and self.udid not in text:
                continue
            self.seen_reports.add(path)
            fresh.append({"summary": self._crash_summary(text), "file": os.path.basename(path), "text": text})
        self.crashes += fresh
        return fresh

    @staticmethod
    def _crash_summary(text):
        try:
            body = json.loads(text.split("\n", 1)[1])
            exc = body.get("exception", {})
            lines = ["%s %s %s" % (exc.get("type", ""), exc.get("signal", ""), exc.get("subtype", ""))]
            for note in (body.get("asi") or {}).values():
                lines += [str(v) for v in note][:3]
            images = body.get("usedImages", [])
            thread = body.get("threads", [])[body.get("faultingThread", 0)]
            for frame in thread.get("frames", [])[:14]:
                image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex", -1) < len(images) else "?"
                lines.append("  %s  %s" % (image, frame.get("symbol", "+%s" % frame.get("imageOffset"))))
            return "\n".join(lines)
        except (ValueError, KeyError, IndexError, TypeError):
            return text[:1500]

    def wait_for_crash(self, seconds=12):
        end = time.time() + seconds
        while time.time() < end:
            fresh = self.new_crashes()
            if fresh:
                return fresh
            time.sleep(1)
        return []

    def usage(self):
        """(cpu % since the last call, memory in MB) of the app; None when it is not running."""
        if not self.alive():
            return None
        out = run("ps", "-o", "time=,rss=", "-p", self.pid, check=False).split()
        if len(out) < 2:
            return None
        parts = [float(p) for p in out[0].replace("-", ":").split(":")]
        cpu = 0.0
        for part in parts:
            cpu = cpu * 60 + part
        now, mark = time.time(), self.cpu_mark
        self.cpu_mark = (self.pid, now, cpu)
        if not mark or mark[0] != self.pid or now - mark[1] < 0.2:
            return (None, int(out[1]) // 1024)
        return (round(100 * (cpu - mark[2]) / (now - mark[1])), int(out[1]) // 1024)

    def perf(self, seconds):
        self.usage()
        time.sleep(seconds)
        use = self.usage()
        if use is None:
            return "Snapreel is not running"
        text = "over %.0f s: CPU %s%% (100%% is one core), memory %d MB" % (seconds, use[0], use[1])
        out = run("sudo", "footprint", "-p", self.pid, check=False, timeout=60)
        match = re.search(r"phys_footprint: *([^\n]+)", out)
        peak = re.search(r"phys_footprint_peak: *([^\n]+)", out)
        if match:
            text += ", footprint " + match.group(1).strip() + (" (peak %s)" % peak.group(1).strip() if peak else "")
        return text

    def main_busy(self, seconds=1.5):
        """How much of `seconds` the app's main thread spent working, 0 to 1; None when it cannot be told. Cheap."""
        def used():
            out = run("ps", "-M", "-p", self.pid, check=False, timeout=30).split("\n")
            if len(out) < 2:
                return None
            times = re.findall(r"(\d+):([\d.]+)", out[1])[-2:]  # system and user time of the first thread
            return sum(int(m) * 60 + float(sec) for m, sec in times) if len(times) == 2 else None
        if not self.alive():
            return None
        before, begun = used(), time.time()
        time.sleep(seconds)
        after = used()
        if before is None or after is None:
            return None
        return min(1.0, (after - before) / (time.time() - begun))

    def main_thread(self, seconds=2):
        """What the app's main thread did for `seconds`: (busy share 0-1, readable stack, whole sample)."""
        if not self.alive():
            return None
        path = os.path.join(self.work, "sample.txt")
        try:
            run("sudo", "rm", "-f", path, check=False)
            run("sudo", "sample", self.pid, seconds, 5, "-mayDie", "-file", path, check=False, timeout=seconds + 90)
            run("sudo", "chmod", "644", path, check=False)
        except subprocess.TimeoutExpired:
            run("sudo", "pkill", "-9", "-x", "sample", check=False)
            return None
        try:
            with open(path, errors="replace") as f:
                text = f.read()
        except OSError:
            return None
        lines, graph = text.split("\n"), []
        start = next((i for i, l in enumerate(lines) if "com.apple.main-thread" in l), None)
        if start is None:
            return (0.0, "", text)
        total = int(re.search(r"(\d+)", lines[start]).group(1))
        for line in lines[start + 1:]:
            if re.match(r"^    \d+ Thread_", line) or not line.strip():
                break
            graph.append(line)
        idle = 0
        for line in graph:
            match = re.match(r"^[\s+!:|]*(\d+) (mach_msg2_trap|mach_msg_trap)\b", line)
            if match:
                idle += int(match.group(1))
        # The heaviest path, deepest frames last.
        best, depth_best = [], {}
        stack = []
        for line in graph:
            match = re.match(r"^([\s+!:|]*)(\d+) (.+)$", line)
            if not match:
                continue
            depth, count, name = len(match.group(1)), int(match.group(2)), match.group(3)
            while stack and stack[-1][0] >= depth:
                stack.pop()
            stack.append((depth, count, name))
            if count >= total * 0.3:
                best = [s for s in stack]
        names = [re.sub(r"\s+\[0x.*$", "", "%d %s" % (c, n)) for _, c, n in best]
        return (1 - idle / float(total or 1), "\n".join(names[-40:]), text)

    def check_hang(self, reason):
        """Called when the app did not answer in time. Records and returns a hang if its main thread is busy."""
        if not self.alive():
            return None
        share = self.main_busy(2)
        found = self.main_thread(2) if share is None or share > 0.3 else None
        busy, stack, text = found if found else (share or 0.0, "(no stack)", "main thread busy %s" % share)
        if share is not None:
            busy = share
        ours = sum(stack.count(w) for w in ("AXRuntime", "AccessibilityUtilities", "UIAccessibility", "_AXXMIG"))
        self.hung = busy > 0.6 and ours < 3
        if ours >= 3:
            return None  # it is busy describing its screen to the rig
        hang = {"at": time.strftime("%H:%M:%S"), "reason": reason, "busy": round(busy * 100), "stack": stack, "text": text}
        if busy < 0.5:
            hang["note"] = "its main thread is mostly idle, so this may be the rig being slow; look again"
        self.hangs.append(hang)
        return hang

    def log_tail(self, count=60, pattern="", minutes=10):
        """The app's log, read back on demand: a running log stream takes a third of a core."""
        out = simctl("spawn", self.udid, "log", "show", "--style", "compact", "--info", "--last", "%dm" % minutes, "--predicate",
                     'process == "Snapreel" OR process BEGINSWITH "SnapreelB" OR process BEGINSWITH "SnapreelL"',
                     check=False, timeout=150)
        lines = out.split("\n")
        for name in ("stdout.log", "stderr.log"):
            try:
                with open(os.path.join(self.work, name), errors="replace") as f:
                    lines += ["(%s) %s" % (name[:6], l) for l in f.read().split("\n")[-200:] if l.strip()]
            except OSError:
                pass
        if pattern:
            lines = [l for l in lines if re.search(pattern, l, re.I)]
        return lines[-count:]

    # ---- video -----------------------------------------------------------------------------

    def video_start(self):
        if self.video:
            raise StepError("a recording is already running")
        path = os.path.join(self.work, "video-%d.mp4" % int(time.time()))
        log = open(path + ".log", "w")
        proc = subprocess.Popen(["xcrun", "simctl", "io", self.udid, "recordVideo", "--codec=h264", "--force", path],
                                stdout=log, stderr=log)
        end = time.time() + 10
        while time.time() < end and "Recording started" not in open(path + ".log").read():
            time.sleep(0.1)
        self.video = (proc.pid, path)

    def video_stop(self):
        if not self.video:
            raise StepError("no recording is running")
        pid, path = self.video
        self.video = None
        end = time.time() + 60
        try:
            os.kill(pid, signal.SIGINT)
            while time.time() < end:
                try:
                    os.waitpid(pid, os.WNOHANG)
                except ChildProcessError:
                    pass
                os.kill(pid, 0)
                time.sleep(0.3)
        except OSError:
            pass  # it has ended and the file is whole
        small = path.replace(".mp4", "-s.mp4")
        # A third of the pixels: easy to send, still readable.
        run("avconvert", "--preset", "Preset960x540", "--source", path, "--output", small, "--replace", check=False, timeout=600)
        best = small if os.path.exists(small) and os.path.getsize(small) > 1000 else path
        with open(best, "rb") as f:
            return f.read()

    def stop(self):
        if self.video:
            try:
                os.kill(self.video[0], signal.SIGINT)
            except OSError:
                pass
        if self.udid:
            subprocess.run(["xcrun", "simctl", "shutdown", self.udid], capture_output=True)
            subprocess.run(["xcrun", "simctl", "delete", self.udid], capture_output=True)
