#!/usr/bin/env node
// Full-page review screenshots of the marketing site at phone and desktop width, Light and Dark.
//
//   node scripts/web-review.mjs http://localhost:3000            # every page
//   node scripts/web-review.mjs http://localhost:3000 / /pricing  # some pages
//   node scripts/web-review.mjs --shot <url> <out.png> <width> <height>   # one viewport, e.g. the OG image
//
// Drives headless Chrome over the DevTools protocol, so the width is exact
// (a plain --window-size is clamped to 500 px in headless mode) and prefers-color-scheme is
// emulated. Writes art/web/review/{page}-{width}-{scheme}.jpg (REVIEW_OUT=<dir> writes there instead), plus
// {page}-{width}-{scheme}-fold.jpg, the first screen only, and prints any horizontal overflow.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = process.env.REVIEW_OUT ? resolve(process.env.REVIEW_OUT) : join(root, "art/web/review");
const PAGES = ["/", "/pricing", "/help", "/help/camera-recording", "/privacy", "/terms", "/support", "/help/no-such-article", "/no-such-page"];
const SIZES = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
];
// Chrome only, always headless (the owner asked for Chrome and no browser windows on screen).
const BROWSERS = [
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function launch() {
  const exe = BROWSERS.find((b) => existsSync(b));
  if (!exe) throw new Error("no Chrome found");
  const profile = mkdtempSync(join(tmpdir(), "sr-review-"));
  const port = 9300 + Math.floor(Math.random() * 500);
  const proc = spawn(exe, [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    "about:blank",
  ]);
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find((t) => t.type === "page");
      if (page) return { proc, profile, ws: page.webSocketDebuggerUrl };
    } catch {}
    await sleep(500);
  }
  throw new Error("browser did not start");
}

function connect(url) {
  const ws = new WebSocket(url);
  let id = 0;
  const pending = new Map();
  const listeners = [];
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve: ok, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : ok(msg.result);
    } else if (msg.method) {
      listeners.forEach((l) => l(msg));
    }
  };
  const send = (method, params = {}) =>
    new Promise((ok, reject) => {
      const n = ++id;
      pending.set(n, { resolve: ok, reject });
      ws.send(JSON.stringify({ id: n, method, params }));
    });
  const waitFor = (method, ms = 30000) =>
    new Promise((ok) => {
      const t = setTimeout(ok, ms);
      listeners.push((m) => {
        if (m.method === method) {
          clearTimeout(t);
          ok(m);
        }
      });
    });
  return new Promise((ok) => (ws.onopen = () => ok({ send, waitFor, close: () => ws.close() })));
}

async function shoot(cdp, url, { width, height }, scheme, file) {
  await cdp.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: width < 768 });
  // Reduced motion keeps transitions out of the captures, so every capture is the same frame.
  await cdp.send("Emulation.setEmulatedMedia", {
    features: [
      { name: "prefers-color-scheme", value: scheme },
      { name: "prefers-reduced-motion", value: "reduce" },
    ],
  });
  const loaded = cdp.waitFor("Page.loadEventFired");
  await cdp.send("Page.navigate", { url });
  await loaded;
  await sleep(1200); // let React hydrate before measuring
  const { result } = await cdp.send("Runtime.evaluate", {
    returnByValue: true,
    expression: `(() => {
      const de = document.documentElement;
      const wide = [...document.querySelectorAll("body *")]
        .filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.right > de.clientWidth + 1 && !e.closest(".mk-scene"); })
        .slice(0, 5).map((e) => e.tagName.toLowerCase() + "." + String(e.className.baseVal ?? e.className).split(" ").slice(0, 3).join("."));
      const empty = [];
      return { scrollWidth: de.scrollWidth, clientWidth: de.clientWidth, height: de.scrollHeight, wide, empty };
    })()`,
  });
  const m = result.value;
  // The first screen, as a visitor sees it on arrival.
  await cdp.send("Runtime.evaluate", {
    awaitPromise: true,
    expression: `(async () => {
      const inView = [...document.images].filter((i) => { const r = i.getBoundingClientRect(); return r.width && r.top < innerHeight && r.bottom > 0; });
      await Promise.race([
        Promise.all(inView.map((i) => i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; }))),
        new Promise((r) => setTimeout(r, 15000)),
      ]);
      await Promise.all(inView.map((i) => (i.decode ? i.decode().catch(() => {}) : 0)));
      await document.fonts.ready;
      await new Promise((r) => setTimeout(r, 400));
    })()`,
  });
  const fold = await cdp.send("Page.captureScreenshot", { format: "jpeg", quality: 85, clip: { x: 0, y: 0, width, height, scale: 1 } });
  writeFileSync(file.replace(/\.jpg$/, "-fold.jpg"), Buffer.from(fold.data, "base64"));
  // Paint the whole page in one viewport (captureBeyondViewport skips some composited layers).
  // Every lazy image is then in view, so it loads on its own.
  await cdp.send("Emulation.setDeviceMetricsOverride", { width, height: m.height, deviceScaleFactor: 1, mobile: width < 768 });
  await cdp.send("Runtime.evaluate", {
    awaitPromise: true,
    expression: `(async () => {
      await new Promise((r) => setTimeout(r, 300));
      // Wait for visible images only (a lazy image inside display:none never loads), 15 s at most.
      const visible = [...document.images].filter((i) => i.getClientRects().length);
      await Promise.race([
        Promise.all(visible.map((i) => i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; }))),
        new Promise((r) => setTimeout(r, 15000)),
      ]);
      // Lazy, async-decoded images can be "complete" but not yet painted; decode them first.
      await Promise.all(visible.map((i) => (i.decode ? i.decode().catch(() => {}) : 0)));
      await document.fonts.ready;
      await new Promise((r) => setTimeout(r, 800));
    })()`,
  });
  const after = await cdp.send("Runtime.evaluate", { returnByValue: true, expression: `[...document.images].filter((i) => i.getClientRects().length && !i.naturalWidth).map((i) => i.alt.slice(0, 30))` });
  m.empty = after.result.value;
  const shot = await cdp.send("Page.captureScreenshot", {
    format: "jpeg",
    quality: 85,
    clip: { x: 0, y: 0, width, height: m.height, scale: 1 },
  });
  writeFileSync(file, Buffer.from(shot.data, "base64"));
  const overflow = m.scrollWidth > m.clientWidth ? `  OVERFLOW ${m.scrollWidth}px: ${m.wide.join(", ")}` : "";
  const empty = m.empty.length ? `  EMPTY IMAGES: ${m.empty.join(" | ")}` : "";
  console.log(`${file.startsWith(root) ? file.slice(root.length + 1) : file}  ${width}x${m.height}${overflow}${empty}`);
}

async function single(url, file, width, height) {
  const { proc, profile, ws } = await launch();
  const cdp = await connect(ws);
  await cdp.send("Page.enable");
  try {
    await cdp.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    const loaded = cdp.waitFor("Page.loadEventFired");
    await cdp.send("Page.navigate", { url });
    await loaded;
    await cdp.send("Runtime.evaluate", {
      awaitPromise: true,
      expression: `(async () => {
        const inView = [...document.images].filter((i) => { const r = i.getBoundingClientRect(); return r.width && r.top < innerHeight && r.bottom > 0; });
        await Promise.race([
          Promise.all(inView.map((i) => i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; }))),
          new Promise((r) => setTimeout(r, 15000)),
        ]);
        await Promise.all(inView.map((i) => (i.decode ? i.decode().catch(() => {}) : 0)));
        await document.fonts.ready;
        await new Promise((r) => setTimeout(r, 600));
      })()`,
    });
    const shot = await cdp.send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width, height, scale: 1 } });
    writeFileSync(resolve(root, file), Buffer.from(shot.data, "base64"));
    console.log(`${file}  ${width}x${height}`);
  } finally {
    cdp.close();
    proc.kill();
    await sleep(1500);
    try {
      rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
    } catch {}
  }
}

if (process.argv[2] === "--shot") {
  const [, , , url, file, w, h] = process.argv;
  await single(url, file, Number(w), Number(h));
  process.exit(0);
}

const base = (process.argv[2] ?? "http://localhost:3000").replace(/\/$/, "");
const pages = process.argv.slice(3).length ? process.argv.slice(3) : PAGES;
mkdirSync(outDir, { recursive: true });
const { proc, profile, ws } = await launch();
const cdp = await connect(ws);
await cdp.send("Page.enable");
try {
  for (const page of pages) {
    const name = page.replace(/^\/|\/$/g, "").replace(/\//g, "-") || "home";
    for (const size of SIZES) {
      for (const scheme of ["light", "dark"]) {
        await shoot(cdp, base + page, size, scheme, join(outDir, `${name}-${size.width}-${scheme}.jpg`));
      }
    }
  }
} finally {
  cdp.close();
  proc.kill();
  await sleep(1500);
  try {
    rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
  } catch {
    // Windows can keep the profile locked for a moment; it's a temp folder, so leave it.
  }
}
