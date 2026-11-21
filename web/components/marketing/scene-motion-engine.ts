/* The moving layer of an illustrated scene: a 2.5D Three.js stage laid exactly over the scene's picture.
   Loaded on demand by scene-motion.tsx (never in the first paint), so three.js stays out of the page's
   own bundle.

   The picture itself is the base texture. Where something that moves was painted into it (clouds, the two
   birds, the kite, butterflies), a clean plate shows instead and the element is drawn again as a sprite
   cut from the same art, so the first frame equals the still picture. Everything starts at rest and eases
   in. Data comes from scripts/web-motion.py (motion-manifest.ts and /marketing/motion/*).

   World units are pixels of the scene's source picture, x right and y down. */
import {
  AdditiveBlending,
  BufferAttribute,
  BufferGeometry,
  CanvasTexture,
  DoubleSide,
  DynamicDrawUsage,
  Group,
  LinearFilter,
  LinearMipmapLinearFilter,
  LinearSRGBColorSpace,
  Mesh,
  NoColorSpace,
  OrthographicCamera,
  Scene,
  ShaderMaterial,
  Texture,
  Vector2,
  Vector3,
  Vector4,
  WebGLRenderer,
  type IUniform,
} from "three";
import { motion } from "./motion-manifest";

type Box = readonly [number, number, number, number];
type Pt = readonly [number, number];
type Sprite = { readonly r: Box; readonly a: Box };
type Lane = readonly [Pt, Pt, Pt];
type ThemeData = {
  readonly mask: string;
  readonly plate: string;
  readonly atlas: string;
  readonly atlasSize: Pt;
  readonly clouds: readonly (Sprite & { readonly pin: number })[];
  readonly birds: readonly (Sprite & { readonly ink: readonly number[] })[];
  readonly butterflies: readonly (Sprite & { readonly axis: readonly number[]; readonly perches: readonly Pt[] })[];
  readonly kite?: {
    readonly attach: Pt;
    readonly fill: readonly number[];
    readonly edge: readonly number[];
    readonly ribbons: readonly { readonly p: readonly Pt[]; readonly w: readonly number[] }[];
    readonly body: Sprite;
    readonly tail: Sprite;
  };
  readonly lamps?: readonly { readonly at: Pt; readonly r: number; readonly pool?: Box }[];
  readonly stars?: readonly (readonly number[])[];
  readonly fireflies?: readonly Box[];
};
type SceneData = {
  readonly size: Pt;
  readonly mobile: Box | null;
  readonly maxShift: number;
  readonly lanes: readonly Lane[];
  readonly lanesMobile: readonly Lane[];
  readonly birdExit: Pt;
  readonly water: boolean;
  readonly light: ThemeData;
  readonly dark: ThemeData;
};

export type MotionSlot = keyof typeof motion;
export type MotionTheme = "light" | "dark";
export type MotionOptions = {
  theme: MotionTheme;
  /** The picture on screen is the scene's phone crop. */
  narrow: boolean;
  /** Phones and touch screens: fewer things, 30 frames a second. */
  lite: boolean;
};

const TAU = Math.PI * 2;
const rand = (a: number, b: number) => a + Math.random() * (b - a);
const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
const smooth = (v: number) => {
  const x = clamp01(v);
  return x * x * (3 - 2 * x);
};

/* ------------------------------------------------------------------------------------------ shaders */

const VERTEX = /* glsl */ `
  uniform vec2 uSize;
  varying vec2 vUv;
  varying vec2 vSrc;
  void main() {
    vUv = uv;
    vec4 world = modelMatrix * vec4(position, 1.0);
    vSrc = world.xy / uSize;
    gl_Position = projectionMatrix * viewMatrix * world;
  }
`;

/* Wind: how far the picture is pulled at a point (in fractions of the picture), given the point's sway
   weight. Gusts travel left to right (wide slow swells with shorter ones riding on them), so neighbouring
   trees move one after the other; a crown leans with the gust, rocks on its own rhythm and its leaves
   flutter in small patches. The periods don't divide into each other, so it never visibly repeats. */
const WIND = /* glsl */ `
  uniform sampler2D uMask;
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uIntro;
  uniform float uShift;
  uniform vec3 uSeed;
  vec2 windAt(vec2 p, float weight) {
    if (weight <= 0.0) return vec2(0.0);
    float t = uTime;
    float gust = 0.5
      + 0.30 * sin(6.2832 * (p.x * 0.85 - t * 0.067) + uSeed.x)
      + 0.17 * sin(6.2832 * (p.x * 2.10 - t * 0.109) + uSeed.y)
      + 0.11 * sin(6.2832 * (p.x * 0.31 - t * 0.0271) + uSeed.z);
    gust = clamp(gust, 0.0, 1.0);
    vec2 px = p * uSize;
    float rock = 0.6 * sin(6.2832 * (t * 0.21 - p.x * 1.9) + px.y * 0.004 + uSeed.y)
               + 0.4 * sin(6.2832 * (t * 0.34 - p.x * 3.1) - px.y * 0.007 + uSeed.z);
    float flutter = sin(px.x * 0.021 + px.y * 0.013 + t * 4.3 + uSeed.x) * sin(px.y * 0.019 - px.x * 0.011 - t * 3.1 + uSeed.y);
    float dx = (gust - 0.4) * 0.55 + rock * (0.12 + 0.28 * gust) + flutter * (0.05 + 0.13 * gust);
    float dy = (gust - 0.4) * 0.08 + rock * 0.10 + flutter * (0.04 + 0.10 * gust);
    return vec2(dx, dy) * (weight * uShift * uIntro) / uSize;
  }
`;

const BASE_FRAGMENT = /* glsl */ `
  precision highp float;
  ${WIND}
  uniform sampler2D uBase;
  uniform sampler2D uPlate;
  uniform vec4 uCrop;
  uniform float uWater;
  uniform vec3 uGlint;
  varying vec2 vSrc;
  void main() {
    vec4 here = texture2D(uMask, vSrc);
    vec2 at = vSrc + windAt(vSrc, here.r);
    float glint = 0.0;
    if (uWater > 0.0 && here.g > 0.0) {
      // The pond: the reflection wobbles in thin horizontal ripples, with glints running along them.
      vec2 px = vSrc * uSize;
      float t = uTime;
      float a = sin(px.y * 0.55 + t * 1.6 + 2.0 * sin(px.x * 0.02 + t * 0.5));
      float b = sin(px.y * 0.23 - t * 1.1 + px.x * 0.011);
      at += vec2(a * 1.6 + b * 2.4, b * 0.5) * (here.g * uIntro) / uSize;
      float line = pow(max(0.0, sin(px.y * 0.8 + t * 1.3 + 3.0 * sin(px.x * 0.035 - t * 0.4))), 14.0);
      glint = line * (0.5 + 0.5 * sin(px.x * 0.05 + t * 0.7 + uSeed.x)) * here.g * uIntro;
    }
    vec4 there = texture2D(uMask, at);
    vec3 base = texture2D(uBase, (at - uCrop.xy) / uCrop.zw).rgb;
    vec3 plate = texture2D(uPlate, at).rgb;
    vec3 colour = mix(base, plate, smoothstep(0.6, 0.9, there.b));
    gl_FragColor = vec4(colour + uGlint * glint, 1.0);
  }
`;

/* A cut-out from the atlas. uBehind = 1 puts it in the sky layer: trees (moving with the wind) hide it. */
const SPRITE_FRAGMENT = /* glsl */ `
  precision highp float;
  ${WIND}
  uniform sampler2D uMap;
  uniform vec4 uRect;
  uniform vec3 uTint;
  uniform float uOpacity;
  uniform float uBehind;
  varying vec2 vUv;
  varying vec2 vSrc;
  void main() {
    vec4 c = texture2D(uMap, mix(uRect.xy, uRect.zw, vUv));
    float open = 1.0;
    if (uBehind > 0.0) {
      vec2 at = vSrc + windAt(vSrc, texture2D(uMask, vSrc).r);
      open = smoothstep(0.1, 0.4, texture2D(uMask, at).b);
    }
    gl_FragColor = vec4(c.rgb * uTint, c.a * uOpacity * open);
  }
`;

/* A butterfly: both wings fold towards the body's axis (uFlap 1 = as painted, towards 0 = closed). */
const BUTTERFLY_FRAGMENT = /* glsl */ `
  precision highp float;
  uniform sampler2D uMap;
  uniform vec4 uRect;
  uniform vec2 uDim;
  uniform vec2 uAxisAt;
  uniform vec2 uAxisDir;
  uniform float uFlap;
  varying vec2 vUv;
  void main() {
    vec2 rel = vUv * uDim - uAxisAt;
    float along = dot(rel, uAxisDir);
    vec2 across = rel - along * uAxisDir;
    vec2 uv = (uAxisAt + along * uAxisDir + across / uFlap) / uDim;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) discard;
    gl_FragColor = texture2D(uMap, mix(uRect.xy, uRect.zw, uv));
  }
`;

/* A ribbon of the kite's tail, drawn in code: the kite's red with its ink line along both edges by day,
   and with the lit rim along one edge at dusk (uLit), as painted. */
const RIBBON_VERTEX = /* glsl */ `
  attribute float aSide;
  attribute float aHalf;
  varying float vSide;
  varying float vHalf;
  void main() {
    vSide = aSide;
    vHalf = aHalf;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;
const RIBBON_FRAGMENT = /* glsl */ `
  precision highp float;
  uniform vec3 uFill;
  uniform vec3 uEdge;
  uniform float uOpacity;
  uniform float uScale;
  uniform float uLit;
  varying float vSide;
  varying float vHalf;
  void main() {
    float fromEdge = (1.0 - abs(vSide)) * vHalf * uScale; // screen pixels in from the ribbon's edge
    float line = max(0.5, 0.9 * uScale);
    vec3 inked = mix(uEdge, uFill, smoothstep(line - 0.5, line + 0.5, fromEdge));
    vec3 lit = mix(uFill * 0.85, uEdge, smoothstep(-0.1, 0.6, vSide));
    vec3 colour = mix(inked, lit, uLit);
    gl_FragColor = vec4(colour, clamp(fromEdge + 0.5, 0.0, 1.0) * uOpacity);
  }
`;

/* A soft light, added on top: a lamp's halo, a firefly, a star's sparkle (uCross). */
const GLOW_FRAGMENT = /* glsl */ `
  precision highp float;
  uniform vec3 uColor;
  uniform float uPower;
  uniform float uCross;
  varying vec2 vUv;
  void main() {
    vec2 p = (vUv - 0.5) * 2.0;
    float d = length(p);
    float g = pow(max(0.0, 1.0 - d), 2.4);
    g += uCross * max(0.0, 1.0 - d) * (exp(-abs(p.x) * 22.0) + exp(-abs(p.y) * 22.0)) * 0.7;
    gl_FragColor = vec4(uColor * (g * uPower), 1.0);
  }
`;

/* ------------------------------------------------------------------------------------------ helpers */

async function loadBitmap(url: string, signal: AbortSignal): Promise<ImageBitmap> {
  const blob = await (await fetch(url, { signal })).blob();
  try {
    // The mask's channels are data: no colour management, no premultiplying.
    return await createImageBitmap(blob, { premultiplyAlpha: "none", colorSpaceConversion: "none" });
  } catch {
    return createImageBitmap(blob);
  }
}

function dataTexture(image: ImageBitmap | HTMLCanvasElement, mipmaps: boolean): Texture {
  const texture = image instanceof HTMLCanvasElement ? new CanvasTexture(image) : new Texture(image);
  texture.flipY = false;
  texture.premultiplyAlpha = false;
  texture.colorSpace = NoColorSpace; // the shaders work in the picture's own values, so nothing shifts
  texture.generateMipmaps = mipmaps;
  texture.minFilter = mipmaps ? LinearMipmapLinearFilter : LinearFilter;
  texture.magFilter = LinearFilter;
  texture.needsUpdate = true;
  return texture;
}

/** The scene's picture once the browser has it for this theme and crop (the <picture> picks the file). */
function pictureReady(img: HTMLImageElement, theme: MotionTheme, narrow: boolean, signal: AbortSignal): Promise<void> {
  const ok = () => {
    const src = img.currentSrc;
    // The fallback <img> has no dark or phone sources of its own; then any loaded picture will do.
    const right = (src.includes(`-${theme}-`) || !/-(light|dark)-/.test(src)) && src.includes("-mobile-") === narrow;
    return right && img.complete && img.naturalWidth > 0;
  };
  return new Promise((resolve, reject) => {
    if (ok()) return resolve();
    const stop = () => {
      img.removeEventListener("load", check);
      clearTimeout(timer);
    };
    const check = () => {
      if (!ok()) return;
      stop();
      resolve();
    };
    const timer = setTimeout(() => {
      stop();
      reject(new Error("scene picture not ready"));
    }, 12000);
    img.addEventListener("load", check);
    signal.addEventListener("abort", () => {
      stop();
      reject(new Error("aborted"));
    });
  });
}

const BIRD_FRAMES = 12;
const BIRD_DOWN = -0.45; // wing position of the first frame; the last is 1 (wings up)

/** Wing frames of a gull seen head on, like the birds in the art: white, tinted to the ink colour. */
function birdFrames(): HTMLCanvasElement {
  const cell = 96;
  const canvas = document.createElement("canvas");
  canvas.width = cell * BIRD_FRAMES;
  canvas.height = cell;
  const ctx = canvas.getContext("2d");
  if (!ctx) return canvas;
  ctx.fillStyle = "#fff";
  const span = cell * 0.46;
  for (let i = 0; i < BIRD_FRAMES; i++) {
    const lift = BIRD_DOWN + ((1 - BIRD_DOWN) * i) / (BIRD_FRAMES - 1);
    const cx = i * cell + cell / 2;
    const cy = cell * 0.62;
    for (const side of [-1, 1]) {
      // Root, shoulder and tip: the shoulder always arches up, the tip swings above and below it.
      const tip = [span * (0.98 - 0.22 * lift * lift), span * (0.02 - 0.62 * lift)];
      const mid = [tip[0] * 0.48, -span * (0.3 * lift + 0.17)];
      const ctrl = [2 * mid[0] - tip[0] / 2, 2 * mid[1] - tip[1] / 2];
      const upper: number[][] = [];
      const lower: number[][] = [];
      for (let k = 0; k <= 14; k++) {
        const u = k / 14;
        const x = 2 * (1 - u) * u * ctrl[0] + u * u * tip[0];
        const y = 2 * (1 - u) * u * ctrl[1] + u * u * tip[1];
        const tx = 2 * (1 - 2 * u) * ctrl[0] + 2 * u * tip[0];
        const ty = 2 * (1 - 2 * u) * ctrl[1] + 2 * u * tip[1];
        const len = Math.hypot(tx, ty) || 1;
        const half = span * (0.07 * Math.pow(1 - u, 0.8) + 0.014);
        upper.push([x - (ty / len) * half, y + (tx / len) * half]);
        lower.push([x + (ty / len) * half, y - (tx / len) * half]);
      }
      ctx.beginPath();
      [...upper, ...lower.reverse()].forEach(([x, y], k) => (k ? ctx.lineTo(cx + side * x, cy + y) : ctx.moveTo(cx + side * x, cy + y)));
      ctx.closePath();
      ctx.fill();
    }
    ctx.beginPath();
    ctx.ellipse(cx, cy + span * 0.04, span * 0.1, span * 0.085, 0, 0, TAU);
    ctx.fill();
  }
  return canvas;
}

function quadGeometry(): BufferGeometry {
  const g = new BufferGeometry();
  g.setAttribute("position", new BufferAttribute(new Float32Array([-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0]), 3));
  g.setAttribute("uv", new BufferAttribute(new Float32Array([0, 0, 1, 0, 1, 1, 0, 1]), 2));
  g.setIndex([0, 1, 2, 0, 2, 3]);
  return g;
}

/** A slow, irregular value in -1..1 that is 0 at t = 0 (two sines whose periods don't line up). */
const drift = (t: number, period: number, phase = 0) =>
  0.62 * (Math.sin((TAU * t) / period + phase) - Math.sin(phase)) + 0.38 * (Math.sin((TAU * t) / (period * 0.618) + phase * 1.7) - Math.sin(phase * 1.7));

const bezier = (lane: Lane, u: number, out: Vector2) => {
  const v = 1 - u;
  return out.set(v * v * lane[0][0] + 2 * v * u * lane[1][0] + u * u * lane[2][0], v * v * lane[0][1] + 2 * v * u * lane[1][1] + u * u * lane[2][1]);
};

/* ------------------------------------------------------------------------------------------ engine */

type Actor = (t: number, dt: number) => void;

export class SceneMotion {
  private renderer: WebGLRenderer;
  private camera = new OrthographicCamera(0, 1, 0, 1, -1, 1);
  private scene = new Scene();
  private quad = quadGeometry();
  private data: SceneData;
  private actors: Actor[] = [];
  private disposables: { dispose(): void }[] = [];
  private bitmaps: ImageBitmap[] = [];
  private abort = new AbortController();
  private shared: Record<"uMask" | "uSize" | "uTime" | "uIntro" | "uShift" | "uSeed", IUniform>;
  private pxScale = { value: 1 }; // screen pixels per source pixel
  private options: MotionOptions = { theme: "light", narrow: false, lite: false };
  private view: Box = [0, 0, 1, 1]; // the part of the source on screen
  private time = 0;
  private last = 0;
  private lastDraw = 0;
  private raf = 0;
  private running = false;
  private loaded = false;
  private firstFrame: (() => void) | null = null;

  constructor(
    private canvas: HTMLCanvasElement,
    private img: HTMLImageElement,
    slot: MotionSlot,
  ) {
    this.data = motion[slot] as unknown as SceneData;
    this.renderer = new WebGLRenderer({ canvas, antialias: false, alpha: false, depth: false, stencil: false, powerPreference: "low-power" });
    this.renderer.outputColorSpace = LinearSRGBColorSpace; // pass the picture's values straight through
    this.renderer.setPixelRatio(1);
    this.shared = {
      uMask: { value: null },
      uSize: { value: new Vector2(this.data.size[0], this.data.size[1]) },
      uTime: { value: 0 },
      uIntro: { value: 0 },
      uShift: { value: this.data.maxShift },
      uSeed: { value: new Vector3(rand(0, TAU), rand(0, TAU), rand(0, TAU)) },
    };
  }

  /** Build the scene for a theme and crop. Resolves once its first frame (the still picture) is drawn. */
  async load(options: MotionOptions): Promise<void> {
    this.clear();
    this.options = options;
    const signal = this.abort.signal;
    const theme = this.data[options.theme];
    await pictureReady(this.img, options.theme, options.narrow && !!this.data.mobile, signal);
    const [base, mask, plate, atlas] = await Promise.all([
      createImageBitmap(this.img),
      loadBitmap(theme.mask, signal),
      loadBitmap(theme.plate, signal),
      loadBitmap(theme.atlas, signal),
    ]);
    this.bitmaps.push(base, mask, plate, atlas);
    if (signal.aborted) throw new Error("aborted");

    const textures = { base: dataTexture(base, false), mask: dataTexture(mask, false), plate: dataTexture(plate, false), atlas: dataTexture(atlas, true) };
    this.disposables.push(...Object.values(textures));
    this.shared.uMask.value = textures.mask;
    this.shared.uSeed.value = new Vector3(rand(0, TAU), rand(0, TAU), rand(0, TAU));
    this.time = 0;

    this.resize(); // the actors below ask what is in view
    this.addBase(textures.base, textures.plate);
    const dark = options.theme === "dark";
    this.addClouds(theme, textures.atlas);
    this.addBirds(theme, textures.atlas);
    if (theme.kite) this.addKite(theme.kite, textures.atlas, theme.atlasSize);
    this.addButterflies(theme, textures.atlas);
    if (dark) this.addLights(theme);

    this.loaded = true;
    this.draw(0);
    if (this.running) this.loop();
  }

  /** Called with true while the scene is on screen and the tab is visible. Time stands still otherwise. */
  setRunning(on: boolean) {
    if (on === this.running) return;
    this.running = on;
    this.last = 0; // the clock picks up where it stopped
    cancelAnimationFrame(this.raf);
    if (on && this.loaded) this.loop();
  }

  onFirstFrame(fn: () => void) {
    this.firstFrame = fn;
  }

  resize() {
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    if (!w || !h) return;
    // Sharp enough for the inked lines, but never more pixels than a mid-range GPU fills comfortably.
    const cap = this.options.lite ? 2 : 1.5;
    const budget = this.options.lite ? 1.3e6 : 3.6e6;
    const ratio = Math.min(window.devicePixelRatio || 1, cap, Math.sqrt(budget / (w * h)));
    this.renderer.setSize(Math.round(w * ratio), Math.round(h * ratio), false);

    // The picture fills the box like object-fit: cover, centred; show the same part of the source.
    const [sw, sh] = this.data.size;
    const crop = this.crop();
    let x0 = crop[0] * sw;
    let y0 = crop[1] * sh;
    let cw = crop[2] * sw;
    let ch = crop[3] * sh;
    // (A box a fraction of a pixel off the picture's shape just stretches it, as the browser does.)
    const shape = w / h / (cw / ch);
    if (shape > 1.004) {
      const visible = cw / (w / h);
      y0 += (ch - visible) / 2;
      ch = visible;
    } else if (shape < 0.996) {
      const visible = ch * (w / h);
      x0 += (cw - visible) / 2;
      cw = visible;
    }
    this.view = [x0, y0, cw, ch];
    this.camera.left = x0;
    this.camera.right = x0 + cw;
    this.camera.top = y0; // top < bottom: y runs down, like the picture
    this.camera.bottom = y0 + ch;
    this.camera.updateProjectionMatrix();
    this.pxScale.value = (w * ratio) / cw;
    if (this.loaded && !this.running) this.draw(0);
  }

  dispose() {
    this.abort.abort();
    cancelAnimationFrame(this.raf);
    this.running = false;
    this.clear();
    this.quad.dispose();
    this.renderer.dispose();
  }

  /* ---------------------------------------------------------------------------------- frame loop */

  private loop = () => {
    this.raf = requestAnimationFrame((now) => {
      if (!this.running) return;
      this.loop();
      // Phones draw every other frame. A pause (tab hidden, scrolled away) never shows as a jump.
      if (this.options.lite && now - this.lastDraw < 30) return;
      const dt = this.last ? Math.min(0.1, (now - this.last) / 1000) : 0;
      this.last = now;
      this.lastDraw = now;
      this.draw(dt);
    });
  };

  private draw(dt: number) {
    this.time += dt;
    const t = this.time;
    this.shared.uTime.value = t;
    this.shared.uIntro.value = smooth(t / 3);
    for (const act of this.actors) act(t, dt);
    this.renderer.render(this.scene, this.camera);
    if (this.firstFrame) {
      const fn = this.firstFrame;
      this.firstFrame = null;
      fn();
    }
  }

  private clear() {
    this.loaded = false;
    this.last = 0;
    this.actors = [];
    this.scene.clear();
    for (const d of this.disposables) d.dispose();
    for (const b of this.bitmaps) b.close();
    this.disposables = [];
    this.bitmaps = [];
  }

  /** x, y, width, height of the picture on screen, in fractions of the source. */
  private crop(): Box {
    const m = this.options.narrow ? this.data.mobile : null;
    return m ? [m[0], m[1], m[2] - m[0], m[3] - m[1]] : [0, 0, 1, 1];
  }

  private material(fragmentShader: string, uniforms: Record<string, IUniform>, additive = false, vertexShader = VERTEX) {
    const m = new ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: { ...this.shared, ...uniforms },
      transparent: true,
      depthTest: false,
      depthWrite: false,
      side: DoubleSide, // y runs down, which flips the winding
    });
    if (additive) m.blending = AdditiveBlending;
    this.disposables.push(m);
    return m;
  }

  private mesh(material: ShaderMaterial, order: number, parent: Scene | Group = this.scene, geometry = this.quad) {
    const mesh = new Mesh(geometry, material);
    mesh.frustumCulled = false;
    mesh.renderOrder = order;
    parent.add(mesh);
    return mesh;
  }

  private sprite(s: Sprite, atlas: Texture, atlasSize: Pt, order: number, behind: boolean, parent: Scene | Group = this.scene) {
    const [ax, ay, aw, ah] = s.a;
    const uniforms = {
      uMap: { value: atlas },
      uRect: { value: new Vector4(ax / atlasSize[0], ay / atlasSize[1], (ax + aw) / atlasSize[0], (ay + ah) / atlasSize[1]) },
      uTint: { value: new Vector3(1, 1, 1) },
      uOpacity: { value: 1 },
      uBehind: { value: behind ? 1 : 0 },
    };
    const mesh = this.mesh(this.material(SPRITE_FRAGMENT, uniforms), order, parent);
    mesh.position.set(s.r[0] + s.r[2] / 2, s.r[1] + s.r[3] / 2, 0);
    mesh.scale.set(s.r[2], s.r[3], 1);
    return { mesh, uniforms };
  }

  /* ---------------------------------------------------------------------------------- the picture */

  private addBase(base: Texture, plate: Texture) {
    const [w, h] = this.data.size;
    const crop = this.crop();
    const material = this.material(BASE_FRAGMENT, {
      uBase: { value: base },
      uPlate: { value: plate },
      uCrop: { value: new Vector4(crop[0], crop[1], crop[2], crop[3]) },
      uWater: { value: this.data.water ? 1 : 0 },
      uGlint: { value: this.options.theme === "dark" ? new Vector3(0.2, 0.13, 0.1) : new Vector3(0.24, 0.26, 0.28) },
    });
    material.transparent = false;
    const mesh = this.mesh(material, 0);
    mesh.position.set(w / 2, h / 2, 0);
    mesh.scale.set(w, h, 1);
  }

  /* ---------------------------------------------------------------------------------- clouds */

  private addClouds(theme: ThemeData, atlas: Texture) {
    const w = this.data.size[0];
    for (const cloud of theme.clouds) {
      const { mesh } = this.sprite(cloud, atlas, theme.atlasSize, 1, true);
      const home = mesh.position.clone();
      const period = rand(150, 260); // each cloud at its own pace, for a little parallax
      const reach = w * rand(0.013, 0.022);
      const dir = cloud.pin || (Math.random() < 0.5 ? -1 : 1);
      const phase = rand(0, TAU);
      this.actors.push((t) => {
        // A cloud cut by the picture's edge only leans out towards it and comes back; the others wander
        // both ways around where they were painted. They stay where they frame the scene.
        const angle = (TAU * t) / period + 0.25 * Math.sin((TAU * t) / (period * 0.53));
        const along = cloud.pin ? (1 - Math.cos(angle)) / 2 : Math.sin(angle);
        const breathe = 1 + 0.012 * drift(t, period * 0.31, phase);
        mesh.scale.set(cloud.r[2] * breathe, cloud.r[3] * (2 - breathe), 1);
        mesh.position.x = home.x + dir * reach * along - (cloud.pin * (breathe - 1) * cloud.r[2]) / 2;
        mesh.position.y = home.y + w * 0.0025 * drift(t, period * 0.53, phase);
      });
    }
  }

  /* ---------------------------------------------------------------------------------- birds */

  private addBirds(theme: ThemeData, atlas: Texture) {
    const [w, h] = this.data.size;
    const ink = theme.birds[0]?.ink ?? (this.options.theme === "dark" ? [18, 17, 28] : [74, 76, 79]);
    const tint = new Vector3(ink[0] / 255, ink[1] / 255, ink[2] / 255);

    // The two painted birds hold still for a moment, then glide off the way they face.
    const exit = new Vector2(this.data.birdExit[0], this.data.birdExit[1]).normalize();
    theme.birds.forEach((bird, i) => {
      const { mesh } = this.sprite(bird, atlas, theme.atlasSize, 2, true);
      const home = mesh.position.clone();
      const leave = 1.6 + i * 0.9 + rand(0, 0.5);
      const speed = w * rand(0.03, 0.036);
      const phase = rand(0, TAU);
      this.actors.push((t) => {
        if (!mesh.visible || t < leave) return;
        const s = t - leave;
        const gone = speed * (s - 2.4 * (1 - Math.exp(-s / 2.4))); // eases up to speed
        const bob = Math.sin(s * 0.9 + phase) * bird.r[3] * 0.35 * smooth(s / 3);
        mesh.position.set(home.x + exit.x * gone, home.y + exit.y * gone + bob, 0);
        mesh.rotation.z = Math.sin(s * 0.7 + phase) * 0.07 * smooth(s / 3);
        if (!this.inView(mesh.position.x, mesh.position.y, bird.r[2])) mesh.visible = false;
      });
    });

    // After that, small flocks cross now and then, drawn in code.
    const lanes = this.options.narrow && this.data.mobile ? this.data.lanesMobile : this.data.lanes;
    if (!lanes.length) return;
    const frames = dataTexture(birdFrames(), true);
    this.disposables.push(frames);
    const size = theme.birds.length ? theme.birds[0].r[2] * 1.12 : w * 0.019;
    type Flyer = { mesh: Mesh; rect: Vector4; lane: Lane; from: number; span: number; off: Vector2; scale: number; rate: number; phase: number; wing: number; busy: boolean };
    const pool: Flyer[] = [];
    const flyer = () => {
      let f = pool.find((p) => !p.busy);
      if (!f) {
        const rect = new Vector4(0, 0, 1 / BIRD_FRAMES, 1);
        const mesh = this.mesh(this.material(SPRITE_FRAGMENT, { uMap: { value: frames }, uRect: { value: rect }, uTint: { value: tint }, uOpacity: { value: 1 }, uBehind: { value: 1 } }), 2);
        f = { mesh, rect, lane: lanes[0], from: 0, span: 1, off: new Vector2(), scale: 1, rate: 3, phase: 0, wing: 0, busy: false };
        pool.push(f);
      }
      return f;
    };
    const at = new Vector2();
    const ahead = new Vector2();
    // The first one follows the painted birds; where none of those are in view (the phone crops), sooner.
    const painted = theme.birds.some((b) => this.inView(b.r[0] + b.r[2] / 2, b.r[1] + b.r[3] / 2, 0));
    let next = painted ? rand(7, 11) : rand(2.5, 5);
    this.actors.push((t, dt) => {
      if (t >= next) {
        next = t + rand(20, 60);
        const lane = lanes[Math.floor(Math.random() * lanes.length)];
        const way: Lane = Math.random() < 0.5 ? lane : [lane[2], lane[1], lane[0]];
        const far = rand(0.55, 1); // a far flock is smaller and slower
        const length = Math.hypot((way[2][0] - way[0][0]) * w, (way[2][1] - way[0][1]) * h);
        const span = length / (w * 0.06 * far);
        const count = this.options.lite ? 2 + Math.floor(Math.random() * 2) : 2 + Math.floor(Math.random() * 4);
        for (let i = 0; i < count; i++) {
          const f = flyer();
          const row = Math.ceil(i / 2);
          Object.assign(f, { lane: way, span, scale: far * rand(0.9, 1.08), rate: rand(2.7, 3.4), phase: rand(0, TAU), wing: rand(0, TAU), busy: true });
          f.from = t + row * rand(0.55, 0.8) + rand(0, 0.15);
          f.off.set(0, (i % 2 ? 1 : -1) * row * size * far * rand(0.9, 1.5)); // a loose V behind the leader
        }
      }
      for (const f of pool) {
        if (!f.busy) continue;
        const u = (t - f.from) / f.span;
        f.mesh.visible = u >= 0 && u <= 1;
        if (u > 1) f.busy = false;
        if (!f.mesh.visible) continue;
        bezier(f.lane, u, at);
        bezier(f.lane, Math.min(1, u + 0.01), ahead);
        const dx = (ahead.x - at.x) * w;
        const dy = (ahead.y - at.y) * h;
        const len = Math.hypot(dx, dy) || 1;
        // Flap for a while, then hold the wings out and glide.
        const glide = smooth((Math.sin(t * 0.83 + f.phase) + Math.sin(t * 0.31 + f.phase * 2.3) - 0.5) * 1.6);
        f.wing += dt * TAU * f.rate * (1 - 0.92 * glide);
        const lift = Math.sin(f.wing) * (1 - glide) + 0.22 * glide;
        const frame = Math.round(clamp01((lift - BIRD_DOWN) / (1 - BIRD_DOWN)) * (BIRD_FRAMES - 1));
        f.rect.set(frame / BIRD_FRAMES, 0, (frame + 1) / BIRD_FRAMES, 1);
        const s = size * f.scale * 1.09; // the wings span 92% of a frame
        const sway = Math.sin(t * 0.6 + f.phase) * s * 0.35;
        // Offsets across the path, so the V and the meander follow the turn.
        f.mesh.position.set(at.x * w + (-dy / len) * (f.off.y + sway), at.y * h + (dx / len) * (f.off.y + sway) - lift * s * 0.07, 0);
        f.mesh.scale.set(s, s, 1);
        f.mesh.rotation.z = Math.max(-0.2, Math.min(0.2, (dy / len) * 0.35 * Math.sign(dx || 1)));
      }
    });
  }

  /* ---------------------------------------------------------------------------------- the kite */

  private addKite(kite: NonNullable<ThemeData["kite"]>, atlas: Texture, atlasSize: Pt) {
    const w = this.data.size[0];
    const [ax, ay] = kite.attach;
    const phase = rand(0, TAU);
    // Where the kite is and how it is turned at a moment: it sways on its line, pivoting where the tail joins.
    const pose = (t: number) => {
      const ease = smooth(t / 2.5);
      return {
        x: w * 0.004 * drift(t, 9.7, phase) * ease,
        y: w * 0.003 * drift(t, 7.3, phase + 2) * ease,
        turn: (0.05 * drift(t, 6.1, phase + 4) + 0.02 * Math.sin(t * 2.1 + phase)) * ease,
      };
    };

    const group = new Group();
    group.position.set(ax, ay, 0);
    this.scene.add(group);
    const place = (s: Sprite) => {
      const made = this.sprite(s, atlas, atlasSize, 4, false, group);
      made.mesh.position.set(s.r[0] + s.r[2] / 2 - ax, s.r[1] + s.r[3] / 2 - ay, 0);
      return made;
    };
    place(kite.body);
    const painted = place(kite.tail); // the tail as painted, until the one drawn in code has taken over

    const fill = new Vector3(kite.fill[0] / 255, kite.fill[1] / 255, kite.fill[2] / 255);
    const edge = new Vector3(kite.edge[0] / 255, kite.edge[1] / 255, kite.edge[2] / 255);
    const opacity = { value: 0 };
    const ribbons = kite.ribbons.map((traced, index) => {
      // The traced centre line has a point every few pixels; a smooth curve through it bends without corners.
      const ribbon = { p: [] as number[][], w: [] as number[] };
      const last = traced.p.length - 1;
      const pick = (i: number) => traced.p[Math.min(last, Math.max(0, i))];
      for (let i = 0; i <= last * 3; i++) {
        const k = Math.floor(i / 3);
        const u = (i % 3) / 3;
        const [a, b, c, d] = [pick(k - 1), pick(k), pick(k + 1), pick(k + 2)];
        const spline = (j: 0 | 1) => 0.5 * (2 * b[j] + (c[j] - a[j]) * u + (2 * a[j] - 5 * b[j] + 4 * c[j] - d[j]) * u * u + (3 * b[j] - a[j] - 3 * c[j] + d[j]) * u * u * u);
        ribbon.p.push([spline(0), spline(1)]);
        ribbon.w.push(traced.w[k] + (traced.w[Math.min(last, k + 1)] - traced.w[k]) * u);
      }
      const n = ribbon.p.length;
      const geometry = new BufferGeometry();
      const position = new BufferAttribute(new Float32Array(n * 2 * 3), 3);
      position.setUsage(DynamicDrawUsage);
      const side = new Float32Array(n * 2);
      const half = new Float32Array(n * 2);
      const indices: number[] = [];
      for (let i = 0; i < n; i++) {
        side[i * 2] = -1;
        side[i * 2 + 1] = 1;
        half[i * 2] = half[i * 2 + 1] = ribbon.w[i] / 2 + 0.3;
        if (i < n - 1) indices.push(i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 1, i * 2 + 3, i * 2 + 2);
      }
      geometry.setAttribute("position", position);
      geometry.setAttribute("aSide", new BufferAttribute(side, 1));
      geometry.setAttribute("aHalf", new BufferAttribute(half, 1));
      geometry.setIndex(indices);
      this.disposables.push(geometry);
      const material = this.material(RIBBON_FRAGMENT, { uFill: { value: fill }, uEdge: { value: edge }, uOpacity: opacity, uScale: this.pxScale, uLit: { value: this.options.theme === "dark" ? 1 : 0 } }, false, RIBBON_VERTEX);
      this.mesh(material, 3, this.scene, geometry);
      // Rest shape relative to the joint, and how far along the ribbon each point is.
      const rest = ribbon.p.map(([x, y]) => [x - ax, y - ay]);
      const along = [0];
      for (let i = 1; i < n; i++) along.push(along[i - 1] + Math.hypot(rest[i][0] - rest[i - 1][0], rest[i][1] - rest[i - 1][1]));
      return { position, rest, along, length: along[n - 1], half, points: new Float32Array(n * 2), seed: rand(0, TAU) + index * 2.1 };
    });

    this.actors.push((t) => {
      const now = pose(t);
      group.position.set(ax + now.x, ay + now.y, 0);
      group.rotation.z = now.turn;
      const swap = smooth((t - 0.4) / 1.2);
      painted.uniforms.uOpacity.value = 1 - swap;
      painted.mesh.visible = swap < 1;
      opacity.value = swap;
      const wave = smooth(t / 3);
      const wind = 0.75 + 0.25 * Math.sin(t * 0.37 + phase);
      for (const r of ribbons) {
        const n = r.rest.length;
        for (let i = 0; i < n; i++) {
          // The far end follows the kite late, like a soft rope, and a wave runs down the ribbon, growing
          // towards its free end.
          const s = r.along[i] / r.length;
          const then = pose(Math.max(0, t - s * 0.55));
          const cos = Math.cos(then.turn);
          const sin = Math.sin(then.turn);
          const [rx, ry] = r.rest[i];
          const j = Math.min(n - 1, i + 1);
          const k = Math.max(0, i - 1);
          const tx = r.rest[j][0] - r.rest[k][0];
          const ty = r.rest[j][1] - r.rest[k][1];
          const tl = Math.hypot(tx, ty) || 1;
          const ripple = wave * wind * r.length * 0.07 * Math.pow(s, 1.3) * (0.62 * Math.sin(TAU * (s * 1.5 - t * 0.85) + r.seed) + 0.38 * Math.sin(TAU * (s * 2.6 - t * 1.37) + r.seed * 1.9));
          const px = rx + (-ty / tl) * ripple;
          const py = ry + (tx / tl) * ripple;
          r.points[i * 2] = ax + then.x + px * cos - py * sin;
          r.points[i * 2 + 1] = ay + then.y + px * sin + py * cos;
        }
        const out = r.position.array as Float32Array;
        for (let i = 0; i < n; i++) {
          const j = Math.min(n - 1, i + 1);
          const k = Math.max(0, i - 1);
          const tx = r.points[j * 2] - r.points[k * 2];
          const ty = r.points[j * 2 + 1] - r.points[k * 2 + 1];
          const tl = Math.hypot(tx, ty) || 1;
          const hw = r.half[i * 2];
          out[i * 6] = r.points[i * 2] + (ty / tl) * hw;
          out[i * 6 + 1] = r.points[i * 2 + 1] - (tx / tl) * hw;
          out[i * 6 + 3] = r.points[i * 2] - (ty / tl) * hw;
          out[i * 6 + 4] = r.points[i * 2 + 1] + (tx / tl) * hw;
        }
        r.position.needsUpdate = true;
      }
    });
  }

  /* ---------------------------------------------------------------------------------- butterflies */

  private addButterflies(theme: ThemeData, atlas: Texture) {
    const w = this.data.size[0];
    const list = this.options.lite ? theme.butterflies.slice(0, 1) : theme.butterflies;
    for (const b of list) {
      const [ax, ay, aw, ah] = b.a;
      const [sx, sy] = theme.atlasSize;
      const turn = (b.axis[2] * Math.PI) / 180;
      const flap = { value: 1 };
      const mesh = this.mesh(
        this.material(BUTTERFLY_FRAGMENT, {
          uMap: { value: atlas },
          uRect: { value: new Vector4(ax / sx, ay / sy, (ax + aw) / sx, (ay + ah) / sy) },
          uDim: { value: new Vector2(b.r[2], b.r[3]) },
          uAxisAt: { value: new Vector2(b.axis[0] - b.r[0], b.axis[1] - b.r[1]) },
          uAxisDir: { value: new Vector2(Math.cos(turn), -Math.sin(turn)) },
          uFlap: flap,
        }),
        5,
      );
      const home = new Vector2(b.r[0] + b.r[2] / 2, b.r[1] + b.r[3] / 2);
      mesh.position.set(home.x, home.y, 0);
      mesh.scale.set(b.r[2], b.r[3], 1);
      const spots = [home, ...b.perches.map(([x, y]) => new Vector2(x, y))];
      let spot = 0;
      let facing = 1;
      // Sit on a flower with the wings slowly opening and closing, then flutter over to another one.
      let state: { fly: false; since: number; until: number } | { fly: true; since: number; span: number; from: Vector2; via: Vector2; to: Vector2; next: number } = {
        fly: false,
        since: 0,
        until: rand(3.5, 7),
      };
      const at = new Vector2();
      this.actors.push((t) => {
        if (!state.fly) {
          const s = t - state.since;
          flap.value = 1 - 0.45 * (1 - Math.cos(TAU * s * 0.32)) * 0.5 * smooth(s / 1.5);
          if (t < state.until || spots.length < 2) return;
          let next = Math.floor(Math.random() * (spots.length - 1));
          if (next >= spot) next++;
          const from = spots[spot];
          const to = spots[next];
          const reach = from.distanceTo(to);
          const via = from.clone().add(to).multiplyScalar(0.5).add(new Vector2(rand(-0.4, 0.4) * reach, -rand(0.2, 0.55) * reach - w * 0.01));
          state = { fly: true, since: t, span: Math.max(2.2, reach / (w * 0.035)), from, via, to, next };
          return;
        }
        const u = (t - state.since) / state.span;
        if (u >= 1) {
          spot = state.next;
          mesh.position.set(state.to.x, state.to.y, 0);
          mesh.rotation.z = 0;
          mesh.scale.set(b.r[2] * facing, b.r[3], 1);
          state = { fly: false, since: t, until: t + rand(5, 12) };
          return;
        }
        const e = smooth(u);
        const v = 1 - e;
        at.set(v * v * state.from.x + 2 * v * e * state.via.x + e * e * state.to.x, v * v * state.from.y + 2 * v * e * state.via.y + e * e * state.to.y);
        const air = Math.sin(Math.PI * u); // 0 on the flower, 1 in mid air
        const s = t - state.since;
        at.x += Math.sin(s * 5.3) * w * 0.0035 * air;
        at.y += (Math.sin(s * 7.9) + 0.5 * Math.sin(s * 13.1)) * w * 0.003 * air;
        // Back at the painted spot it faces the painted way again; elsewhere, the way it flew.
        const want = state.next === 0 ? 1 : state.to.x >= state.from.x ? 1 : -1;
        if (u > 0.5) facing = want;
        flap.value = 1 - 0.8 * Math.abs(Math.sin(s * Math.PI * 6)) * smooth(Math.min(u, 1 - u) * 8);
        const grow = 1 + 0.08 * air;
        mesh.position.set(at.x, at.y, 0);
        mesh.scale.set(b.r[2] * facing * grow, b.r[3] * grow, 1);
        mesh.rotation.z = Math.sin(s * 3.1) * 0.16 * air;
      });
    }
  }

  /* ---------------------------------------------------------------------------------- lights (Dusk) */

  private glow(x: number, y: number, rx: number, ry: number, colour: Vector3, order: number, cross = 0) {
    const power = { value: 0 };
    const mesh = this.mesh(this.material(GLOW_FRAGMENT, { uColor: { value: colour }, uPower: power, uCross: { value: cross } }, true), order);
    mesh.position.set(x, y, 0);
    mesh.scale.set(rx * 2, ry * 2, 1);
    return { mesh, power };
  }

  private addLights(theme: ThemeData) {
    const warm = new Vector3(1, 0.7, 0.34);
    for (const lamp of theme.lamps ?? []) {
      const halo = this.glow(lamp.at[0], lamp.at[1], lamp.r, lamp.r, warm, 6);
      const core = this.glow(lamp.at[0], lamp.at[1], lamp.r * 0.36, lamp.r * 0.36, warm, 6);
      const pool = lamp.pool ? this.glow(lamp.pool[0], lamp.pool[1], lamp.pool[2], lamp.pool[3], warm, 6) : null;
      const phase = rand(0, TAU);
      let dipAt = rand(4, 12);
      let dipFor = 0.12;
      let dipTo = 0.6;
      this.actors.push((t) => {
        // A faint, uneven shimmer, and now and then a short dip, as an old lamp does.
        if (t > dipAt + dipFor) {
          dipAt = t + rand(5, 19);
          dipFor = rand(0.08, 0.22);
          dipTo = rand(0.45, 0.8);
        }
        const dip = t >= dipAt ? dipTo : 1;
        const shimmer = 0.78 + 0.12 * Math.sin(t * 2.3 + phase) + 0.06 * Math.sin(t * 5.9 + phase * 2) + 0.04 * Math.sin(t * 13.7 + phase * 3);
        const level = shimmer * dip * this.shared.uIntro.value;
        halo.power.value = 0.15 * level;
        core.power.value = 0.13 * level;
        if (pool) pool.power.value = 0.07 * level * (0.85 + 0.15 * Math.sin(t * 0.6 + phase));
      });
    }

    const pale = new Vector3(0.85, 0.9, 1);
    for (const star of this.options.lite ? [] : (theme.stars ?? [])) {
      const spark = this.glow(star[0], star[1], star[2] * 2.2, star[2] * 2.2, pale, 6, 1);
      const phase = rand(0, TAU);
      const pace = rand(0.5, 1.1);
      this.actors.push((t) => {
        const twinkle = Math.max(0, Math.sin(t * pace + phase) * Math.sin(t * pace * 0.37 + phase * 2.1));
        spark.power.value = 0.55 * twinkle * twinkle * this.shared.uIntro.value;
      });
    }

    const green = new Vector3(0.8, 1, 0.3);
    const zones = this.options.lite ? [] : (theme.fireflies ?? []);
    const each = zones.length ? Math.ceil(8 / zones.length) : 0;
    for (const zone of zones) {
      for (let i = 0; i < each; i++) {
        const fly = this.glow(0, 0, 20, 20, green, 6);
        const hx = rand(zone[0], zone[2]);
        const hy = rand(zone[1], zone[3]);
        const phase = rand(0, TAU);
        const roam = rand(50, 130);
        const beat = rand(2.6, 4.8);
        this.actors.push((t) => {
          fly.mesh.position.set(
            hx + roam * (Math.sin(t * 0.19 + phase) + 0.5 * Math.sin(t * 0.43 + phase * 2)),
            hy + roam * 0.5 * (Math.sin(t * 0.23 + phase * 3) + 0.4 * Math.sin(t * 0.61 + phase)),
            0,
          );
          fly.power.value = 0.8 * Math.pow(Math.max(0, Math.sin((TAU * t) / beat + phase)), 3) * this.shared.uIntro.value;
        });
      }
    }
  }

  private inView(x: number, y: number, margin: number) {
    const [vx, vy, vw, vh] = this.view;
    return x > vx - margin && x < vx + vw + margin && y > vy - margin && y < vy + vh + margin;
  }
}
