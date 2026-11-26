"""The same eyes and fingers for the website: headless Chrome (Playwright) on the runner, at a phone's or a
desktop's size. Offers the methods agent.py's steps use, so a tester works the same way as on the phone.
"""
import os
import re
import subprocess
import time

from ios_driver import Hang, INTERACTIVE, IOSDriver, StepError

SIZES = {"phone": (375, 812), "desktop": (1440, 900), "tablet": (820, 1180)}
HOME = "http://localhost:3000"

# Everything a person can see or press, with its box, in document order.
LIST = r"""
() => {
  const out = [], vw = innerWidth, vh = innerHeight;
  const kinds = {A: 'Link', BUTTON: 'Button', INPUT: 'TextField', TEXTAREA: 'TextView', SELECT: 'Button', VIDEO: 'Video',
                 IMG: 'Image', SUMMARY: 'Button', IFRAME: 'Frame'};
  const roles = {button: 'Button', link: 'Link', switch: 'Switch', checkbox: 'Switch', slider: 'Slider', tab: 'Tab',
                 textbox: 'TextField', menuitem: 'MenuItem', radio: 'Button', option: 'Button', dialog: 'Dialog'};
  const seen = (el, r) => {
    const s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || +s.opacity === 0) return false;
    return r.width > 0 && r.height > 0;
  };
  const inside = (el) => el.closest('a,button,[role=button],[role=link],[role=tab],[role=menuitem],label,summary');
  const walk = (root) => {
    for (const el of root.querySelectorAll('*')) {
      if (el.shadowRoot) walk(el.shadowRoot);
      const role = el.getAttribute('role');
      let kind = roles[role] || kinds[el.tagName];
      if (el.tagName === 'INPUT') {
        if (['checkbox', 'radio'].includes(el.type)) kind = 'Switch';
        else if (['submit', 'button', 'reset'].includes(el.type)) kind = 'Button';
        else if (el.type === 'range') kind = 'Slider';
        else if (el.type === 'hidden') continue;
      }
      let label = '';
      if (kind) {
        label = el.getAttribute('aria-label') || el.alt || (el.labels && el.labels[0] && el.labels[0].innerText) ||
                el.innerText || el.placeholder || el.title || '';
      } else if (/^(H[1-6]|P|LI|SPAN|DIV|LABEL|TD|TH|FIGCAPTION|TIME|STRONG|EM|SMALL|DT|DD|CODE|PRE)$/.test(el.tagName)) {
        const own = [...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' ').trim();
        if (!own || inside(el)) continue;
        kind = /^H[1-6]$/.test(el.tagName) ? 'Heading' : 'StaticText';
        label = /^(H[1-6]|P|LI)$/.test(el.tagName) ? el.innerText : own;
      }
      if (!kind || kind === 'Image' && !label) continue;
      const r = el.getBoundingClientRect();
      if (!seen(el, r)) continue;
      out.push({kind, label: (label || '').trim().replace(/\s+/g, ' ').slice(0, 300), id: el.id || '',
                value: kind === 'Switch' ? (el.checked || el.getAttribute('aria-checked') === 'true' ? 'on' : 'off')
                       : el.type === 'password' ? '' : String(el.value === undefined || typeof el.value === 'object' ? '' : el.value).slice(0, 100),
                enabled: !el.disabled && el.getAttribute('aria-disabled') !== 'true',
                selected: el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-current') === 'page',
                x: r.x, y: r.y, w: r.width, h: r.height,
                onscreen: r.x + r.width / 2 >= 0 && r.x + r.width / 2 <= vw && r.y + r.height / 2 >= 0 && r.y + r.height / 2 <= vh});
    }
  };
  walk(document);
  return {items: out, title: document.title, url: location.href,
          wide: document.documentElement.scrollWidth - vw};
}
"""


class WebDriver:
    kind = "web"

    def __init__(self, sid, options, work, status):
        self.sid, self.opt, self.work, self.status = sid, options, work, status
        self.device = "Chrome (%s)" % options.get("device", "phone")
        self.ios = "-"
        self.size = SIZES.get(options.get("device", "phone"), SIZES["phone"])
        self.touch = options.get("device", "phone") != "desktop"
        self.elements, self.offscreen, self.app_label = [], 0, ""
        self.crashes, self.hangs, self.lines = [], [], []
        self.keyboard, self.answer_time = False, 0.0
        self.pid, self.expected_gone = None, True
        self.hang_after = 8
        self.theme_name, self.video_dir = options.get("theme", "light"), os.path.join(work, "videos")
        self.video_from = None
        os.makedirs(work, exist_ok=True)

    def start(self):
        from playwright.sync_api import sync_playwright
        self.status("starting Chrome")
        self.pw = sync_playwright().start()
        self.browser = self.pw.chromium.launch(channel="chrome", headless=True, args=["--autoplay-policy=no-user-gesture-required"])
        self.context = None
        self._context()
        self.open_url(HOME)

    def _context(self, state=None):
        if self.context:
            self.context.close()
        options = dict(viewport={"width": self.size[0], "height": self.size[1]}, color_scheme=self.theme_name,
                       device_scale_factor=2, has_touch=self.touch, is_mobile=self.touch,
                       record_video_dir=self.video_dir, record_video_size={"width": self.size[0], "height": self.size[1]})
        if state:
            options["storage_state"] = state
        # Headless Chrome names itself "HeadlessChrome", which the site rightly treats as a bot (no views counted).
        # A person's browser says what it is, so these do too.
        options["user_agent"] = self.user_agent()
        self.context = self.browser.new_context(**options)
        self.context.on("page", self._watch)
        self.page = self.context.new_page()

    def user_agent(self):
        kind = self.opt.get("device", "phone")
        if kind == "phone":
            return ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
                    "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1")
        if kind == "tablet":
            return ("Mozilla/5.0 (iPad; CPU OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
                    "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1")
        major = (self.browser.version or "140").split(".")[0]
        return ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/%s.0.0.0 Safari/537.36" % major)

    def _watch(self, page):
        self.page = page
        page.set_default_timeout(15000)
        page.on("console", lambda m: self.lines.append("%s console %s: %s" % (time.strftime("%H:%M:%S"), m.type, m.text[:400])))
        page.on("pageerror", lambda e: self._error("page error: %s" % e))
        page.on("response", lambda r: r.status >= 400 and self.lines.append("%s HTTP %d %s" % (time.strftime("%H:%M:%S"), r.status, r.url[:200])))
        page.on("requestfailed", lambda r: self.lines.append("%s failed %s (%s)" % (time.strftime("%H:%M:%S"), r.url[:200], r.failure)))
        page.on("dialog", self._dialog)
        page.on("close", lambda p: self._closed(p))

    def _closed(self, page):
        pages = [p for p in self.context.pages if not p.is_closed()] if self.context else []
        if pages:
            self.page = pages[-1]

    def _dialog(self, dialog):
        self.lines.append("%s the page asked: %s (%s); answered OK" % (time.strftime("%H:%M:%S"), dialog.message, dialog.type))
        dialog.accept()

    def _error(self, text):
        self.lines.append(time.strftime("%H:%M:%S ") + text)

    # ---- looking

    def screenshot(self, name="shot.jpg", full=False):
        try:
            return self.page.screenshot(type="jpeg", quality=82, scale="device" if full else "css", timeout=10000,
                                        full_page=bool(full), caret="initial")
        except Exception as error:
            raise StepError("no picture: %s" % str(error).split("\n")[0])

    def zoom(self, x, y, w, h):
        return self.page.screenshot(type="jpeg", quality=90, clip={"x": x, "y": y, "width": w, "height": h})

    def settle(self, limit=2.5):
        end, last = time.time() + limit, None
        while True:
            shot = self.screenshot()
            if last == shot or time.time() > end:
                return shot
            last = shot
            self.page.wait_for_timeout(150)

    def read_tree(self, timeout=None):
        started = time.time()
        for attempt in range(3):
            try:
                data = self.page.evaluate(LIST)
                break
            except Exception as error:  # navigating at that moment
                if attempt == 2:
                    raise StepError("the page could not be read: %s" % str(error).split("\n")[0])
                self.page.wait_for_timeout(500)
        self.answer_time = time.time() - started
        width, height = self.size
        shown = [e for e in data["items"] if e["x"] < width and e["y"] < height and e["x"] + e["w"] > 0 and e["y"] + e["h"] > 0]
        self.offscreen = len(data["items"]) - len(shown)
        for number, e in enumerate(shown, 1):
            e["n"] = number
        self.elements = shown
        self.app_label = "%s, %s" % (data["title"][:60], data["url"])
        if data["wide"] > 1:
            self.app_label += ", PAGE IS %d px WIDER THAN THE SCREEN" % data["wide"]
        return shown

    tree_lines = IOSDriver.tree_lines
    matches = IOSDriver.matches
    point = IOSDriver.point

    def _aim(self, e, count=1):
        x, y = e["x"] + e["w"] / 2, e["y"] + e["h"] / 2
        note = '%s "%s" at %d,%d' % (e["kind"], e["label"] or e["id"], x, y)
        if not e["enabled"]:
            note += " (it is DISABLED)"
        if count > 1:
            note += " (first of %d with that name; add #2 for the next)" % count
        return x, y, note

    # ---- touching

    def tap(self, x, y, times=1, hold=0.06):
        if self.touch and hold < 0.3:
            for _ in range(times):
                self.page.touchscreen.tap(x, y)
        else:
            self.page.mouse.move(x, y)
            for _ in range(times):
                self.page.mouse.down()
                self.page.wait_for_timeout(hold * 1000)
                self.page.mouse.up()
        self.page.wait_for_timeout(250)

    def drag(self, x1, y1, x2, y2, seconds=0.6, hold=0.15):
        self.page.mouse.move(x1, y1)
        self.page.mouse.down()
        self.page.wait_for_timeout(hold * 1000)
        self.page.mouse.move(x2, y2, steps=max(5, int(seconds / 0.03)))
        self.page.mouse.up()

    def swipe(self, direction, x=None, y=None, amount=0.5):
        width, height = self.size
        dx, dy = {"up": (0, 1), "down": (0, -1), "left": (1, 0), "right": (-1, 0)}[direction]
        self.page.mouse.move(width / 2 if x is None else x, height / 2 if y is None else y)
        self.page.mouse.wheel(dx * width * amount * 1.4, dy * height * amount * 1.4)
        self.page.wait_for_timeout(400)

    def pinch(self, x, y, scale, turn=0.0, seconds=0.7):
        raise StepError("pinch works only on the phone")

    def type_text(self, text):
        for part in re.split("(\b)", text):
            if part == "\b":
                self.page.keyboard.press("Backspace")
            elif part:
                self.page.keyboard.type(part, delay=15)

    KEYS = {"return": "Enter", "enter": "Enter", "delete": "Backspace", "backspace": "Backspace", "space": "Space",
            "tab": "Tab", "escape": "Escape", "esc": "Escape", "left": "ArrowLeft", "right": "ArrowRight", "up": "ArrowUp",
            "down": "ArrowDown", "home": "Home", "end": "End", "pageup": "PageUp", "pagedown": "PageDown",
            "shift": "Shift", "ctrl": "Control", "control": "Control", "alt": "Alt", "option": "Alt", "cmd": "Meta", "meta": "Meta"}

    def key(self, name):
        """One key or a combination: tab, shift+tab, escape, ctrl+a, arrows."""
        parts = [p for p in name.split("+") if p]
        named = []
        for part in parts:
            if part in self.KEYS:
                named.append(self.KEYS[part])
            elif len(part) == 1 or re.fullmatch(r"f\d{1,2}", part):
                named.append(part.upper() if part.startswith("f") and len(part) > 1 else part)
            else:
                raise StepError("no key called %s; keys: %s, letters, f1..f12, joined with + (shift+tab)" % (
                    part, ", ".join(sorted(self.KEYS))))
        self.page.keyboard.press("+".join(named))

    def clipboard(self, text=None):
        """The browser's clipboard: what a page copied (Copy link), or put something there to paste."""
        self.context.grant_permissions(["clipboard-read", "clipboard-write"], origin=HOME)
        try:
            if text is not None:
                self.page.evaluate("t => navigator.clipboard.writeText(t)", text)
                return "put that on the clipboard"
            got = self.page.evaluate("() => navigator.clipboard.readText()")
        except Exception as error:
            raise StepError("the clipboard could not be read on this page (%s)" % str(error).split("\n")[0][:120])
        return "clipboard: " + (got.strip() or "(empty)")

    def press_alert(self, name):
        return None

    def home(self):
        self.open_url(HOME)

    def back(self):
        self.page.go_back(timeout=15000)

    def app_switcher(self):
        raise StepError("that works only on the phone")

    def orient(self, way):
        width, height = self.size
        if (way == "portrait") != (height >= width):
            self.size = (height, width)
            self.page.set_viewport_size({"width": height, "height": width})

    def launch(self, mode="", argument=""):
        if mode == "fresh":
            self._context()
        self.open_url(HOME)

    def activate(self):
        self.page.reload()

    def open_app(self, name):
        self.open_url(HOME + "/" + name.lstrip("/"))

    def kill(self):
        self._context()

    def open_url(self, url):
        try:
            self.page.goto(url, wait_until="load", timeout=45000)
        except Exception as error:
            raise StepError("%s did not open: %s" % (url, str(error).split("\n")[0]))
        self.page.wait_for_timeout(600)

    def alive(self):
        return True

    def permission(self, verb, what):
        raise StepError("that works only on the phone")

    def theme(self, value):
        self.theme_name = value
        self.page.emulate_media(color_scheme=value)

    def text_size(self, value):
        raise StepError("that works only on the phone")

    contrast = add_photo = text_size

    # ---- health

    def new_crashes(self):
        return []

    def wait_for_crash(self, seconds=0):
        return []

    def usage(self):
        return None

    def perf(self, seconds):
        data = self.page.evaluate("""() => { const n = performance.getEntriesByType('navigation')[0] || {};
            return {load: Math.round(n.loadEventEnd || 0), first: Math.round((performance.getEntriesByName('first-contentful-paint')[0] || {}).startTime || 0),
                    files: performance.getEntriesByType('resource').length,
                    bytes: performance.getEntriesByType('resource').reduce((a, r) => a + (r.transferSize || 0), 0)}; }""")
        return "first picture after %(first)d ms, loaded after %(load)d ms, %(files)d files, %(bytes)d bytes" % data

    def main_thread(self, seconds=2):
        started = time.time()
        self.page.evaluate("() => 1")
        return (0.0, "the page answered in %.2f s" % (time.time() - started), "")

    def check_hang(self, reason):
        return None

    def log_tail(self, count=60, pattern=""):
        lines = [l for l in self.lines if not pattern or re.search(pattern, l, re.I)]
        return lines[-count:]

    def video_start(self):
        self.video_from = time.time()

    def video_stop(self):
        if self.video_from is None:
            raise StepError("no recording is running")
        self.video_from = None
        page = self.page
        url, state = page.url, self.context.storage_state()
        video = page.video
        self._context(state)
        path = video.path()
        self.open_url(url)
        with open(path, "rb") as f:
            return f.read()

    def stop(self):
        try:
            self.context.close()
            self.browser.close()
            self.pw.stop()
        except Exception:
            pass
