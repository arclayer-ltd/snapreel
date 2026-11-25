"use client";

// The Snapreel web player. Custom controls modelled on the app's player: a centre transport (back 5 s,
// play, forward 5 s), a red scrubber with viewers' reactions pinned above it, speed, captions, picture in
// picture and full screen. Poster first; portrait, landscape and audio-only all fit the stage.
import Image from "next/image";
import {
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from "react";
import type { Reaction, Transcript, VideoKind } from "@/lib/contract";
import { formatTime, spokenTime } from "@/lib/client/format";
import { SITE_URL } from "@/lib/client/links";
import { emojiName } from "./emoji";
import {
  Back5Icon,
  CaptionsIcon,
  ExitFullscreenIcon,
  Forward5Icon,
  FullscreenIcon,
  MicIcon,
  MuteIcon,
  PauseIcon,
  PipIcon,
  PlayIcon,
  ReplayIcon,
  SpeedIcon,
  VolumeIcon,
} from "./icons";
import { usePlaybackStore } from "./playback";
import "./player.css";
import { Waveform } from "./Waveform";

export const SPEEDS = [1, 1.25, 1.5, 2] as const;
const SKIP = 5;
const HIDE_AFTER_MS = 2600;
/** Room for one 13px emoji on the scrubber, with a gap. */
const MARK_WIDTH = 20;
/** Waiting this long with nothing arriving means the connection or the signed link died: pick it up again. */
const STALLED_AFTER_MS = 15_000;
/** Automatic recoveries closer together than this show the message instead. */
const RECOVER_EVERY_MS = 20_000;

interface Cue {
  start: number;
  end: number;
  text: string;
}

export interface PlayerProps {
  src: string | null;
  poster: string | null;
  captionsUrl: string | null;
  transcript: Transcript | null;
  kind: VideoKind;
  title: string;
  artist?: string | null;
  width: number;
  height: number;
  durationS: number;
  reactions?: Reaction[];
  /** Start as soon as it can (after an upload finishes). Falls back to muted if the browser insists. */
  autoStart?: boolean;
  /** page: the watch page; embed: fills an iframe; preview: the dashboard. */
  variant?: "page" | "embed" | "preview";
  /** Shown under Replay when the video ends (the call-to-action). */
  endScreen?: ReactNode;
  /** Show viewers' reactions beside the reaction buttons as playback passes them. */
  floatReactions?: boolean;
  /** Fetch a fresh signed address for the video (they last 2 hours). Resolves true if `src` will change. */
  onRefresh?: () => Promise<boolean>;
  /** Overlay at the top of the picture (the embed's title). */
  topOverlay?: ReactNode;
}

function parseVtt(text: string): Cue[] {
  const toSeconds = (t: string) => {
    const parts = t.trim().replace(",", ".").split(":").map(Number);
    return parts.reduce((acc, n) => acc * 60 + n, 0);
  };
  const cues: Cue[] = [];
  for (const block of text.replace(/\r/g, "").split(/\n\n+/)) {
    const lines = block.split("\n");
    const i = lines.findIndex((l) => l.includes("-->"));
    if (i < 0) continue;
    const [a, b] = lines[i].split("-->");
    const cueText = lines
      .slice(i + 1)
      .join("\n")
      .replace(/<[^>]+>/g, "")
      .trim();
    if (cueText) cues.push({ start: toSeconds(a), end: toSeconds(b.trim().split(/\s+/)[0]), text: cueText });
  }
  return cues;
}

function transcriptCues(transcript: Transcript | null): Cue[] {
  return (transcript?.segments ?? []).map((s) => ({ start: s.start, end: s.start + s.duration, text: s.text }));
}

function readStoredCaptions(): boolean {
  try {
    return localStorage.getItem("sr_captions") === "on";
  } catch {
    return false;
  }
}

type WebkitVideo = HTMLVideoElement & {
  webkitEnterFullscreen?: () => void;
  webkitSupportsPresentationMode?: (mode: string) => boolean;
  webkitSetPresentationMode?: (mode: string) => void;
  webkitPresentationMode?: string;
  webkitDisplayingFullscreen?: boolean;
};

export function Player({
  src,
  poster,
  captionsUrl,
  transcript,
  kind,
  title,
  artist,
  width,
  height,
  durationS,
  reactions = [],
  autoStart = false,
  variant = "page",
  endScreen,
  floatReactions = false,
  onRefresh,
  topOverlay,
}: PlayerProps) {
  const store = usePlaybackStore();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const trackWidthRef = useRef(600);
  const lastTimeRef = useRef(0);
  const hideTimer = useRef<number | undefined>(undefined);
  const lastTap = useRef<{ at: number; x: number } | null>(null);
  const menuId = useId();
  // What the viewer asked for, whatever the network is doing: it decides whether a recovery starts playing again.
  const wantsPlay = useRef(false);
  const resume = useRef<{ at: number; play: boolean } | null>(null);
  const recoveredAt = useRef(-Infinity);
  const autoStarted = useRef(false);

  const isAudio = kind === "audio" || width === 0 || height === 0;
  const ratio = isAudio ? 16 / 9 : width / height;

  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(durationS);
  const [buffered, setBuffered] = useState(0);
  const [waiting, setWaiting] = useState(false);
  const [ended, setEnded] = useState(false);
  const [rate, setRate] = useState(1);
  const [muted, setMuted] = useState(false);
  const [volume, setVolume] = useState(1);
  const [captionsOn, setCaptionsOn] = useState(false);
  const [vttCues, setVttCues] = useState<Cue[] | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [pip, setPip] = useState(false);
  const [canPip, setCanPip] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);
  const [finePointer, setFinePointer] = useState(false);
  const [controlsShown, setControlsShown] = useState(true);
  const [menuOpen, setMenuOpen] = useState(false);
  const [scrub, setScrub] = useState<number | null>(null);
  const [hud, setHud] = useState<{ key: number; text: string } | null>(null);
  const [ripple, setRipple] = useState<{ key: number; side: "left" | "right" } | null>(null);
  const [autoMuted, setAutoMuted] = useState(false);
  const [failed, setFailed] = useState(false);
  const [recovering, setRecovering] = useState(false);

  const cues = useMemo(() => vttCues ?? transcriptCues(transcript), [vttCues, transcript]);
  const hasCaptions = cues.length > 0;
  const shownTime = scrub ?? time;
  const activeCue = captionsOn ? cues.find((c) => shownTime >= c.start && shownTime < c.end) : undefined;
  const visible = controlsShown || !playing || menuOpen || scrub !== null || !started;

  const checkPip = useCallback(() => {
    const v = videoRef.current as WebkitVideo | null;
    setCanPip(
      !isAudio &&
        !!v &&
        ((document.pictureInPictureEnabled && !v.disablePictureInPicture) ||
          !!v.webkitSupportsPresentationMode?.("picture-in-picture")),
    );
  }, [isAudio]);

  // Feature detection runs on the client only, so the server and first client render agree.
  useEffect(() => {
    const v = videoRef.current as WebkitVideo | null;
    checkPip();
    setCanFullscreen(document.fullscreenEnabled || (!isAudio && typeof v?.webkitEnterFullscreen === "function"));
    setFinePointer(window.matchMedia("(pointer: fine)").matches);
    setCaptionsOn(readStoredCaptions());
  }, [isAudio, checkPip]);

  // Captions come from the WebVTT file when there is one, otherwise from the transcript. The API gives the address on
  // snapreel.video; asked for from this page's own address it works on www and preview addresses too.
  const captionsSrc = captionsUrl?.startsWith(`${SITE_URL}/`) ? captionsUrl.slice(SITE_URL.length) : captionsUrl;
  useEffect(() => {
    if (!captionsSrc) return;
    let cancelled = false;
    fetch(captionsSrc, { credentials: "same-origin" })
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error(String(r.status)))))
      .then((text) => {
        if (!cancelled) setVttCues(parseVtt(text));
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [captionsSrc]);

  const onTrackWidth = useCallback((w: number) => {
    trackWidthRef.current = w;
  }, []);

  const flash = useCallback((text: string) => setHud({ key: Date.now(), text }), []);

  const poke = useCallback(() => {
    setControlsShown(true);
    window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => setControlsShown(false), HIDE_AFTER_MS);
  }, []);

  useEffect(() => () => window.clearTimeout(hideTimer.current), []);

  const play = useCallback(async () => {
    const v = videoRef.current;
    if (!v || !src) return;
    wantsPlay.current = true;
    if (v.ended) v.currentTime = 0;
    // Nothing to show yet: say so straight away instead of sitting there until "waiting" fires.
    if (v.readyState < HTMLMediaElement.HAVE_FUTURE_DATA) setWaiting(true);
    try {
      await v.play();
    } catch (err) {
      if (!(err instanceof DOMException) || err.name !== "NotAllowedError") return;
      v.muted = true;
      try {
        await v.play();
        setAutoMuted(true);
      } catch {
        // Not even muted (Low Power Mode): wait for a tap, with the sound on.
        v.muted = false;
        wantsPlay.current = false;
        setWaiting(false);
      }
    }
  }, [src]);

  const pause = useCallback(() => {
    wantsPlay.current = false;
    videoRef.current?.pause();
  }, []);

  const toggle = useCallback(() => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused || v.ended) void play();
    else pause();
  }, [play, pause]);

  // Carries on from where it was after an expired link or a dropped connection.
  const recover = useCallback(async () => {
    const v = videoRef.current;
    if (!v) return;
    recoveredAt.current = performance.now();
    resume.current = { at: lastTimeRef.current, play: wantsPlay.current };
    setFailed(false);
    setRecovering(true);
    try {
      const changes = (await onRefresh?.()) ?? false;
      // A new address reloads by itself when React sets it; the same one needs telling.
      if (!changes) v.load();
    } catch {
      resume.current = null;
      setRecovering(false);
      setFailed(true);
    }
  }, [onRefresh]);

  const broke = useCallback(() => {
    setWaiting(false);
    if (navigator.onLine && performance.now() - recoveredAt.current > RECOVER_EVERY_MS) {
      void recover();
      return;
    }
    resume.current = null;
    setRecovering(false);
    setFailed(true);
  }, [recover]);

  // Back online after the message: carry on without being asked.
  useEffect(() => {
    if (!failed) return;
    const onOnline = () => void recover();
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  }, [failed, recover]);

  // Stuck: waiting while playing (or reconnecting), and not one more byte for a while.
  const stuckable = (waiting && playing) || recovering;
  useEffect(() => {
    const v = videoRef.current;
    if (!stuckable || !v) return;
    let id = 0;
    const arm = () => {
      window.clearTimeout(id);
      id = window.setTimeout(broke, STALLED_AFTER_MS);
    };
    arm();
    v.addEventListener("progress", arm);
    return () => {
      window.clearTimeout(id);
      v.removeEventListener("progress", arm);
    };
  }, [stuckable, broke]);

  // Coming back to the tab or the app: iOS pauses in the background without always saying so.
  useEffect(() => {
    const onVisible = () => {
      const v = videoRef.current;
      if (!v || document.visibilityState !== "visible") return;
      setPlaying(!v.paused && !v.ended);
      setTime(v.currentTime);
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("pageshow", onVisible);
    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("pageshow", onVisible);
    };
  }, []);

  const seekTo = useCallback(
    (t: number, andPlay = false) => {
      const v = videoRef.current;
      if (!v) return;
      const d = Number.isFinite(v.duration) && v.duration > 0 ? v.duration : duration;
      const clamped = Math.max(0, Math.min(d, t));
      v.currentTime = clamped;
      lastTimeRef.current = clamped;
      setTime(clamped);
      setEnded(false);
      store.update({ time: clamped });
      if (andPlay) void play();
    },
    [duration, play, store],
  );

  const skip = useCallback(
    (delta: number) => {
      const v = videoRef.current;
      if (!v) return;
      seekTo(v.currentTime + delta);
      flash(delta > 0 ? `Forward ${Math.abs(delta)} seconds` : `Back ${Math.abs(delta)} seconds`);
    },
    [flash, seekTo],
  );

  // Let the transcript, comments and reaction bar drive the player.
  useEffect(() => {
    store.attach({ seek: (t, p) => seekTo(t, p), play: () => void play(), pause });
    return () => store.attach(null);
  }, [store, seekTo, play, pause]);

  // Smooth time while playing: move the scrubber about once per pixel.
  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    const tick = () => {
      const v = videoRef.current;
      if (v) {
        const t = v.currentTime;
        const step = Math.max(1 / 30, duration / Math.max(200, trackWidthRef.current));
        setTime((prev) => (Math.abs(prev - t) >= step ? t : prev));
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [playing, duration]);

  // Keyboard: space/k, j/l and arrows, f, c, m. Global on the watch page; focus-only elsewhere.
  const handleKey = useCallback(
    (e: KeyboardEvent | ReactKeyboardEvent, scoped: boolean) => {
      if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
      const target = e.target instanceof Element ? e.target : null;
      if (target?.closest("input, textarea, select, [contenteditable='true'], [role='slider'], [role='menu']")) return;
      if (document.querySelector("dialog[open]")) return;
      const onControl = !!target?.closest("button, a, summary, [role='button']");
      const inPlayer = scoped || (!!target && !!containerRef.current?.contains(target));
      const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      switch (key) {
        case " ":
          if (onControl) return;
          toggle();
          break;
        case "k":
          toggle();
          break;
        case "j":
        case "ArrowLeft":
          skip(-SKIP);
          break;
        case "l":
        case "ArrowRight":
          skip(SKIP);
          break;
        case "ArrowUp":
        case "ArrowDown": {
          if (!inPlayer) return;
          const v = videoRef.current;
          if (!v) return;
          const next = Math.max(0, Math.min(1, Math.round((v.volume + (key === "ArrowUp" ? 0.1 : -0.1)) * 10) / 10));
          v.volume = next;
          v.muted = next === 0;
          flash(`Volume ${Math.round(next * 100)}%`);
          break;
        }
        case "f":
          if (!canFullscreen) return;
          void toggleFullscreen();
          break;
        case "c":
          if (!hasCaptions) return;
          toggleCaptions();
          break;
        case "m":
          toggleMute();
          break;
        default:
          return;
      }
      e.preventDefault();
      poke();
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps -- the toggles below read refs and state setters only
    [toggle, skip, flash, poke, canFullscreen, hasCaptions],
  );

  useEffect(() => {
    if (variant === "preview") return;
    const onKey = (e: KeyboardEvent) => handleKey(e, variant === "embed");
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [handleKey, variant]);

  // Full screen and picture in picture state. iPhone Safari has its own events for both, and its full screen player
  // pauses on the way out and draws captions itself.
  const captionsOnRef = useRef(false);
  useEffect(() => {
    captionsOnRef.current = captionsOn;
  }, [captionsOn]);
  useEffect(() => {
    const v = videoRef.current as WebkitVideo | null;
    const onFs = () => setFullscreen(document.fullscreenElement === containerRef.current);
    const onPipIn = () => setPip(true);
    const onPipOut = () => setPip(false);
    const onMode = () => setPip(v?.webkitPresentationMode === "picture-in-picture");
    const setTracks = (mode: TextTrackMode) => {
      for (const track of Array.from(v?.textTracks ?? [])) track.mode = mode;
    };
    let playedAt = -Infinity; // the last moment it was seen playing in the native player
    let timer = 0;
    const onNativeIn = () => setTracks(captionsOnRef.current ? "showing" : "hidden");
    const onNativeTime = () => {
      if (v?.webkitDisplayingFullscreen && !v.paused) playedAt = performance.now();
    };
    const onNativeOut = () => {
      setTracks("hidden");
      // Playing up to the moment Done was tapped: iOS pauses it, so start it again.
      if (!v?.ended && performance.now() - playedAt < 900) {
        timer = window.setTimeout(() => void v?.play().catch(() => {}), 250);
      }
    };
    document.addEventListener("fullscreenchange", onFs);
    v?.addEventListener("enterpictureinpicture", onPipIn);
    v?.addEventListener("leavepictureinpicture", onPipOut);
    v?.addEventListener("webkitpresentationmodechanged", onMode);
    v?.addEventListener("webkitbeginfullscreen", onNativeIn);
    v?.addEventListener("webkitendfullscreen", onNativeOut);
    v?.addEventListener("timeupdate", onNativeTime);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("fullscreenchange", onFs);
      v?.removeEventListener("enterpictureinpicture", onPipIn);
      v?.removeEventListener("leavepictureinpicture", onPipOut);
      v?.removeEventListener("webkitpresentationmodechanged", onMode);
      v?.removeEventListener("webkitbeginfullscreen", onNativeIn);
      v?.removeEventListener("webkitendfullscreen", onNativeOut);
      v?.removeEventListener("timeupdate", onNativeTime);
    };
  }, []);

  // Autoplay once an upload has finished (and only then: a refreshed address must not start a paused video).
  useEffect(() => {
    if (!autoStart || !src || autoStarted.current) return;
    autoStarted.current = true;
    void play();
  }, [autoStart, src, play]);

  // Lock Screen and headset controls.
  useEffect(() => {
    if (!started || !("mediaSession" in navigator)) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title,
        artist: artist ?? "Snapreel",
        artwork: poster ? [{ src: new URL(poster, location.href).href, sizes: "1280x720", type: "image/jpeg" }] : [],
      });
      navigator.mediaSession.setActionHandler("seekbackward", () => skip(-SKIP));
      navigator.mediaSession.setActionHandler("seekforward", () => skip(SKIP));
    } catch {
      // Older browsers: nothing to do.
    }
  }, [started, title, artist, poster, skip]);

  async function toggleFullscreen() {
    const el = containerRef.current;
    const v = videoRef.current as WebkitVideo | null;
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else if (document.fullscreenEnabled && el) {
        await el.requestFullscreen({ navigationUI: "hide" });
      } else {
        enterNative(v);
      }
    } catch {
      enterNative(v);
    }
  }

  // iPhone: the native player only opens once the video's details have loaded.
  function enterNative(v: WebkitVideo | null) {
    if (!v?.webkitEnterFullscreen) return;
    try {
      if (v.readyState >= HTMLMediaElement.HAVE_METADATA) {
        v.webkitEnterFullscreen();
        return;
      }
    } catch {
      // Falls through to the message.
    }
    void play();
    flash("Still loading. Try full screen again in a moment");
  }

  async function togglePip() {
    const v = videoRef.current as WebkitVideo | null;
    if (!v) return;
    try {
      if (document.pictureInPictureElement) {
        await document.exitPictureInPicture();
      } else if (document.pictureInPictureEnabled && v.requestPictureInPicture) {
        await v.requestPictureInPicture();
      } else if (v.webkitSetPresentationMode) {
        v.webkitSetPresentationMode(v.webkitPresentationMode === "picture-in-picture" ? "inline" : "picture-in-picture");
      }
    } catch {
      flash("Picture in picture isn't available here");
    }
  }

  function toggleCaptions() {
    setCaptionsOn((on) => {
      const next = !on;
      try {
        localStorage.setItem("sr_captions", next ? "on" : "off");
      } catch {}
      flash(next ? "Captions on" : "Captions off");
      return next;
    });
  }

  function toggleMute() {
    const v = videoRef.current;
    if (!v) return;
    v.muted = !v.muted;
    if (!v.muted && v.volume === 0) v.volume = 0.6;
    setAutoMuted(false);
    flash(v.muted ? "Muted" : "Sound on");
  }

  function setSpeed(r: number) {
    const v = videoRef.current;
    if (v) v.playbackRate = r;
    setRate(r);
    setMenuOpen(false);
    flash(r === 1 ? "Normal speed" : `${r}× speed`);
  }

  // Touch: tap shows or hides the controls; a quick second tap on either side skips 5 s.
  // Mouse: click plays or pauses; double-click goes full screen.
  function onSurfacePointerUp(e: ReactPointerEvent<HTMLDivElement>) {
    if (menuOpen) {
      setMenuOpen(false);
      return;
    }
    if (!started) {
      void play();
      return;
    }
    if (e.pointerType === "mouse") {
      toggle();
      poke();
      return;
    }
    const rect = e.currentTarget.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const now = Date.now();
    const prev = lastTap.current;
    lastTap.current = { at: now, x };
    if (prev && now - prev.at < 320 && (x < 0.35 || x > 0.65)) {
      const side = x < 0.35 ? "left" : "right";
      skip(side === "left" ? -SKIP : SKIP);
      setRipple({ key: now, side });
      poke();
      lastTap.current = null;
      return;
    }
    if (visible && playing) {
      window.clearTimeout(hideTimer.current);
      setControlsShown(false);
    } else {
      poke();
    }
  }

  const progress = duration > 0 ? shownTime / duration : 0;
  const busy = recovering || (waiting && (playing || !started));

  // Audio has no picture to fit, so it gets a taller stage on phones for the waveform and controls.
  const audioShape = isAudio && variant !== "embed" && !fullscreen ? "aspect-[4/3] sm:aspect-video" : "";
  const stageClass =
    variant === "embed"
      ? "h-full w-full"
      : variant === "preview"
        ? "w-full max-h-[56svh] rounded-2xl"
        : "w-full max-h-[max(24rem,calc(100svh-9.5rem))] max-lg:landscape:max-h-[calc(100svh-4rem)] sm:rounded-2xl lg:max-h-[calc(100svh-11rem)]";

  return (
    <div
      ref={containerRef}
      className={`group/player relative isolate select-none overflow-hidden bg-[#07080c] text-white ${stageClass} ${audioShape} ${
        visible ? "" : "cursor-none"
      }`}
      style={variant === "embed" || fullscreen || isAudio ? undefined : { aspectRatio: String(ratio) }}
      onPointerMove={(e) => {
        if (e.pointerType === "mouse") poke();
      }}
      onFocusCapture={poke}
      onKeyDown={variant === "preview" ? (e) => handleKey(e, true) : undefined}
      role="region"
      aria-label={`Video player: ${title}`}
    >
      {poster && !isAudio && (
        <Image
          src={poster}
          alt=""
          fill
          unoptimized
          loading="eager"
          fetchPriority="high"
          sizes="100vw"
          className="pointer-events-none scale-125 object-cover opacity-45 blur-2xl"
          aria-hidden="true"
        />
      )}

      <video
        ref={videoRef}
        className={`absolute inset-0 h-full w-full object-contain ${isAudio ? "opacity-0" : ""}`}
        src={src ?? undefined}
        poster={poster ?? undefined}
        preload="metadata"
        playsInline
        aria-label={title}
        onLoadedMetadata={(e) => {
          const d = e.currentTarget.duration;
          if (Number.isFinite(d) && d > 0) {
            setDuration(d);
            store.update({ duration: d });
          }
          for (const track of Array.from(e.currentTarget.textTracks)) track.mode = "hidden";
          checkPip();
          e.currentTarget.playbackRate = rate;
          const back = resume.current;
          if (back) {
            resume.current = null;
            setRecovering(false);
            if (back.at > 0) e.currentTarget.currentTime = back.at;
            if (back.play) void play();
          }
        }}
        onPlay={() => {
          setPlaying(true);
          setStarted(true);
          setEnded(false);
          store.update({ playing: true, started: true });
          poke();
        }}
        onPause={(e) => {
          // Paused from the Lock Screen, a headset or the native player too, but not by a reload or an error.
          if (!resume.current && !e.currentTarget.error) wantsPlay.current = false;
          setPlaying(false);
          store.update({ playing: false });
        }}
        onWaiting={() => setWaiting(true)}
        onSeeking={(e) => {
          if (e.currentTarget.readyState < HTMLMediaElement.HAVE_FUTURE_DATA) setWaiting(true);
        }}
        onSeeked={(e) => {
          if (e.currentTarget.readyState >= HTMLMediaElement.HAVE_FUTURE_DATA) setWaiting(false);
        }}
        onPlaying={() => setWaiting(false)}
        onCanPlay={() => setWaiting(false)}
        onEnded={() => {
          wantsPlay.current = false;
          setWaiting(false);
          setEnded(true);
          setPlaying(false);
          store.update({ playing: false });
        }}
        onTimeUpdate={(e) => {
          const v = e.currentTarget;
          // A reload resets the time to 0 before anything is there: keep the place for the recovery.
          if (v.readyState === HTMLMediaElement.HAVE_NOTHING) return;
          const t = v.currentTime;
          const prev = lastTimeRef.current;
          lastTimeRef.current = t;
          setTime(t);
          store.update({ time: t });
          if (floatReactions && !v.paused && t > prev && t - prev < 1.5) {
            const passed = reactions.filter((r) => r.atS > prev && r.atS <= t).slice(0, 3);
            for (const r of passed) store.burst(r.emoji);
          }
        }}
        onProgress={(e) => {
          const v = e.currentTarget;
          // The stretch around the playhead: after a seek there can be several.
          let end = 0;
          for (let i = 0; i < v.buffered.length; i++) {
            if (v.buffered.start(i) <= v.currentTime + 0.5) end = Math.max(end, v.buffered.end(i));
          }
          setBuffered(end);
        }}
        onRateChange={(e) => setRate(e.currentTarget.playbackRate)}
        onVolumeChange={(e) => {
          setMuted(e.currentTarget.muted);
          setVolume(e.currentTarget.volume);
        }}
        onError={() => {
          if (src) broke();
        }}
      >
        {captionsSrc && <track kind="captions" src={captionsSrc} srcLang={transcript?.locale?.slice(0, 2) ?? "en"} label="Captions" />}
      </video>

      {isAudio && (
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center bg-[radial-gradient(ellipse_at_center,rgb(255_255_255/0.07),transparent_70%)] px-[7%] pb-10">
          <div className="absolute left-1/2 top-4 flex -translate-x-1/2 items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-[13px] font-medium text-white/85">
            <MicIcon size={15} />
            Voice recording
          </div>
          <div className="h-[30%] w-full max-w-[720px]">
            <Waveform seed={title} progress={progress} playing={playing} bars={finePointer ? 64 : 40} />
          </div>
        </div>
      )}

      {topOverlay && (
        <div
          className={`absolute inset-x-0 top-0 z-20 bg-gradient-to-b from-black/65 to-transparent px-4 pb-8 pt-3 transition-opacity duration-200 motion-reduce:transition-none ${
            visible ? "opacity-100" : "pointer-events-none opacity-0"
          }`}
        >
          {topOverlay}
        </div>
      )}

      {/* Tap and click surface */}
      <div
        className="absolute inset-0 z-10"
        onPointerUp={onSurfacePointerUp}
        onDoubleClick={() => {
          if (canFullscreen && finePointer) void toggleFullscreen();
        }}
        aria-hidden="true"
      />

      {/* Captions */}
      {activeCue && (
        <div
          className={`pointer-events-none absolute inset-x-0 z-20 flex justify-center px-4 transition-[bottom] duration-200 motion-reduce:transition-none ${
            visible ? "bottom-[5.75rem]" : "bottom-5"
          }`}
        >
          <p className="max-w-[min(90%,46rem)] whitespace-pre-line rounded-lg bg-black/78 px-3 py-1.5 text-center text-[15px] font-medium leading-snug text-white sm:text-lg">
            {activeCue.text}
          </p>
        </div>
      )}

      {/* Double-tap skip ripple */}
      {ripple && (
        <div
          key={ripple.key}
          className={`sr-ripple pointer-events-none absolute top-1/2 z-20 flex h-28 w-28 items-center justify-center rounded-full bg-white/20 ${
            ripple.side === "left" ? "left-[8%]" : "right-[8%]"
          }`}
          onAnimationEnd={() => setRipple(null)}
          aria-hidden="true"
        >
          {ripple.side === "left" ? <Back5Icon size={34} /> : <Forward5Icon size={34} />}
        </div>
      )}

      {/* Centre transport, as in the app */}
      {!ended && !failed && !menuOpen && (
        <div
          className={`pointer-events-none absolute inset-0 z-20 flex items-center justify-center gap-6 pb-14 transition-opacity duration-200 motion-reduce:transition-none sm:gap-9 ${
            visible ? "opacity-100" : "opacity-0"
          }`}
        >
          {started && (
            <TransportButton label="Back 5 seconds" onClick={() => skip(-SKIP)} hidden={!visible}>
              <Back5Icon size={26} />
            </TransportButton>
          )}
          <button
            type="button"
            onClick={() => (started ? toggle() : void play())}
            tabIndex={visible ? 0 : -1}
            className={`pointer-events-auto flex h-[68px] w-[68px] items-center justify-center rounded-full text-white shadow-[0_8px_30px_rgb(0_0_0/0.35)] backdrop-blur-md transition-transform duration-150 hover:scale-105 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white motion-reduce:transition-none ${
              started ? "bg-black/40" : "bg-[var(--accent-strong,#d32434)]"
            }`}
            aria-label={playing ? (busy ? "Pause (loading)" : "Pause") : started ? "Play" : `Play ${title}`}
          >
            {busy ? (
              <span className={`sr-spinner block h-8 w-8 rounded-full border-[3px] border-white/30 border-t-white`} />
            ) : playing ? (
              <PauseIcon size={30} />
            ) : (
              <PlayIcon size={32} className="translate-x-[2px]" />
            )}
          </button>
          {started && (
            <TransportButton label="Forward 5 seconds" onClick={() => skip(SKIP)} hidden={!visible}>
              <Forward5Icon size={26} />
            </TransportButton>
          )}
        </div>
      )}

      {/* Buffering, when the controls are hidden */}
      {busy && !visible && (
        <span
          className={`sr-spinner pointer-events-none absolute left-1/2 top-1/2 z-20 -ml-5 -mt-5 block h-10 w-10 rounded-full border-[3px] border-white/25 border-t-white`}
          aria-hidden="true"
        />
      )}

      {/* Keyboard feedback */}
      {hud && (
        <div
          key={hud.key}
          className={`sr-hud pointer-events-none absolute left-1/2 top-5 z-30 -translate-x-1/2 rounded-full bg-black/70 px-3.5 py-1.5 text-[13px] font-semibold`}
          onAnimationEnd={() => setHud(null)}
        >
          {hud.text}
        </div>
      )}
      <p className="sr-only" aria-live="polite">
        {hud?.text ?? (recovering ? "Reconnecting" : busy && playing ? "Loading" : "")}
      </p>

      {/* Muted autoplay */}
      {autoMuted && (
        <button
          type="button"
          onClick={toggleMute}
          className="absolute left-3 top-3 z-30 flex items-center gap-2 rounded-full bg-black/70 px-3 py-2 text-[13px] font-semibold text-white focus-visible:outline-2 focus-visible:outline-white"
        >
          <MuteIcon size={16} />
          Tap for sound
        </button>
      )}

      {/* Bottom bar. Only the controls take taps: on a phone the shade above them reaches over the play button. */}
      <div
        className={`pointer-events-none absolute inset-x-0 bottom-0 z-30 bg-gradient-to-t from-black/75 via-black/40 to-transparent px-2 pb-1 pt-10 transition-opacity duration-200 motion-reduce:transition-none sm:px-3 sm:pb-2 ${
          visible ? "opacity-100 *:pointer-events-auto" : "opacity-0"
        }`}
      >
        <Scrubber
          time={shownTime}
          duration={duration}
          buffered={buffered}
          reactions={reactions}
          onWidth={onTrackWidth}
          onScrub={(t) => {
            setScrub(t);
            poke();
          }}
          onCommit={(t) => {
            setScrub(null);
            seekTo(t);
          }}
          onKeySeek={(t) => seekTo(t)}
          tabbable={visible}
        />
        <div className="flex items-center gap-1">
          <span className="whitespace-nowrap px-1.5 text-[13px] font-medium tabular-nums text-white/90">
            {formatTime(shownTime)} <span className="text-white/55">/ {formatTime(duration)}</span>
          </span>
          <div className="ml-auto flex items-center gap-0.5">
            <div>
              <button
                type="button"
                className="flex h-11 items-center gap-1 rounded-full px-2 text-[13px] font-semibold tabular-nums text-white hover:bg-white/15 focus-visible:outline-2 focus-visible:outline-white"
                aria-haspopup="menu"
                aria-expanded={menuOpen}
                aria-controls={menuId}
                aria-label={`Playback speed, ${rate === 1 ? "normal" : `${rate} times`}`}
                onClick={() => setMenuOpen((o) => !o)}
                tabIndex={visible ? 0 : -1}
              >
                <SpeedIcon size={16} className="max-[359px]:hidden" />
                {rate}×
              </button>
              {menuOpen && <SpeedMenu id={menuId} rate={rate} onPick={setSpeed} onClose={() => setMenuOpen(false)} />}
            </div>
            {hasCaptions && (
              <ControlButton
                label={captionsOn ? "Turn captions off" : "Turn captions on"}
                pressed={captionsOn}
                onClick={toggleCaptions}
                tabbable={visible}
              >
                <CaptionsIcon on={captionsOn} size={21} />
              </ControlButton>
            )}
            {finePointer && (
              <ControlButton label={muted ? "Unmute" : "Mute"} onClick={toggleMute} tabbable={visible}>
                {muted || volume === 0 ? <MuteIcon size={20} /> : <VolumeIcon size={20} />}
              </ControlButton>
            )}
            {canPip && (
              <ControlButton
                label={pip ? "Leave picture in picture" : "Picture in picture"}
                pressed={pip}
                onClick={() => void togglePip()}
                tabbable={visible}
              >
                <PipIcon size={20} />
              </ControlButton>
            )}
            {canFullscreen && (
              <ControlButton
                label={fullscreen ? "Leave full screen" : "Full screen"}
                onClick={() => void toggleFullscreen()}
                tabbable={visible}
              >
                {fullscreen ? <ExitFullscreenIcon size={20} /> : <FullscreenIcon size={20} />}
              </ControlButton>
            )}
          </div>
        </div>
      </div>

      {/* End screen: the last frame stays, dimmed, and the scrubber stays in reach (it sits above this). */}
      {ended && !failed && (
        <div className="absolute inset-0 z-[25] flex flex-wrap content-center items-center justify-center gap-3 bg-black/55 px-6 pb-20 pt-4 text-center">
          <button
            type="button"
            onClick={() => seekTo(0, true)}
            className="inline-flex h-12 items-center gap-2 rounded-full bg-white px-5 text-[15px] font-semibold text-[#13141b] shadow-[0_8px_30px_rgb(0_0_0/0.35)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
          >
            <ReplayIcon size={20} />
            Watch again
          </button>
          {endScreen}
        </div>
      )}

      {/* Playback failed, and picking it up again by itself didn't work */}
      {failed && (
        <div
          role="alert"
          className="absolute inset-0 z-40 flex flex-col items-center justify-center gap-3 bg-black/75 p-6 text-center"
        >
          <p className="max-w-xs text-pretty text-[15px] font-medium">
            The video stopped loading. Check your connection, then {time > 0 ? `carry on from ${formatTime(time)}` : "try again"}.
          </p>
          <button
            type="button"
            onClick={() => {
              wantsPlay.current = true;
              void recover();
            }}
            className="h-11 rounded-full bg-white px-5 text-[15px] font-semibold text-[#13141b] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
          >
            Try again
          </button>
        </div>
      )}
    </div>
  );
}

function TransportButton({
  label,
  onClick,
  hidden,
  children,
}: {
  label: string;
  onClick: () => void;
  hidden: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      tabIndex={hidden ? -1 : 0}
      aria-label={label}
      className="pointer-events-auto flex h-[52px] w-[52px] items-center justify-center rounded-full bg-black/30 text-white backdrop-blur-md hover:bg-black/45 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
    >
      {children}
    </button>
  );
}

function ControlButton({
  label,
  onClick,
  pressed,
  tabbable,
  children,
}: {
  label: string;
  onClick: () => void;
  pressed?: boolean;
  tabbable: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      aria-pressed={pressed}
      tabIndex={tabbable ? 0 : -1}
      title={label}
      className="flex h-11 w-10 shrink-0 items-center justify-center rounded-full text-white hover:bg-white/15 focus-visible:outline-2 focus-visible:outline-white"
      style={{ ["--cc-cut" as string]: "#07080c" }}
    >
      {children}
    </button>
  );
}

function SpeedMenu({
  id,
  rate,
  onPick,
  onClose,
}: {
  id: string;
  rate: number;
  onPick: (r: number) => void;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const current = ref.current?.querySelector<HTMLButtonElement>("[aria-checked='true']");
    current?.focus();
    const onDown = (e: PointerEvent) => {
      if (!ref.current?.parentElement?.contains(e.target as Node)) onClose();
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [onClose]);
  return (
    <div
      ref={ref}
      id={id}
      role="menu"
      aria-label="Playback speed"
      className="absolute bottom-[4.75rem] right-2 z-50 flex gap-0.5 rounded-full border border-white/10 bg-[#1c1e27] p-1 shadow-[0_12px_40px_rgb(0_0_0/0.5)]"
      onKeyDown={(e) => {
        const items = Array.from(ref.current?.querySelectorAll<HTMLButtonElement>("[role='menuitemradio']") ?? []);
        const i = items.indexOf(document.activeElement as HTMLButtonElement);
        if (e.key === "Escape") {
          e.preventDefault();
          e.stopPropagation();
          onClose();
        } else if (e.key === "ArrowDown" || e.key === "ArrowRight") {
          e.preventDefault();
          items[(i + 1) % items.length]?.focus();
        } else if (e.key === "ArrowUp" || e.key === "ArrowLeft") {
          e.preventDefault();
          items[(i - 1 + items.length) % items.length]?.focus();
        }
      }}
    >
      {SPEEDS.map((r) => (
        <button
          key={r}
          type="button"
          role="menuitemradio"
          aria-checked={r === rate}
          aria-label={r === 1 ? "Normal speed" : `${r} times`}
          onClick={() => onPick(r)}
          className={`flex h-11 min-w-12 items-center justify-center rounded-full px-2 text-[15px] tabular-nums focus-visible:outline-2 focus-visible:outline-white ${
            r === rate ? "bg-white font-semibold text-[#13141b]" : "text-white hover:bg-white/10"
          }`}
        >
          {r}×
        </button>
      ))}
    </div>
  );
}

function Scrubber({
  time,
  duration,
  buffered,
  reactions,
  onWidth,
  onScrub,
  onCommit,
  onKeySeek,
  tabbable,
}: {
  time: number;
  duration: number;
  buffered: number;
  reactions: Reaction[];
  onWidth: (w: number) => void;
  onScrub: (t: number | null) => void;
  onCommit: (t: number) => void;
  onKeySeek: (t: number) => void;
  tabbable: boolean;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);
  const [hover, setHover] = useState<number | null>(null);
  const [active, setActive] = useState(false);
  const [slots, setSlots] = useState(16);

  useEffect(() => {
    const el = trackRef.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      onWidth(entry.contentRect.width);
      setSlots(Math.max(6, Math.min(50, Math.floor(entry.contentRect.width / MARK_WIDTH))));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [onWidth]);

  const timeAt = (clientX: number) => {
    const rect = trackRef.current!.getBoundingClientRect();
    const f = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    return f * duration;
  };

  // Reactions grouped into slots wide enough for one emoji each, so they never overlap; the most common shows.
  const marks = useMemo(() => {
    if (!duration) return [];
    const groups = new Map<number, Map<string, number>>();
    for (const r of reactions) {
      const slot = Math.min(slots - 1, Math.max(0, Math.floor((r.atS / duration) * slots)));
      const m = groups.get(slot) ?? new Map<string, number>();
      m.set(r.emoji, (m.get(r.emoji) ?? 0) + 1);
      groups.set(slot, m);
    }
    return [...groups.entries()].map(([slot, m]) => {
      const sorted = [...m.entries()].sort((a, b) => b[1] - a[1]);
      const count = sorted.reduce((n, [, c]) => n + c, 0);
      return { slot, emoji: sorted[0][0], count, label: sorted.map(([e, c]) => `${c} ${emojiName(e)}`).join(", ") };
    });
  }, [reactions, duration, slots]);

  const played = duration > 0 ? Math.min(1, time / duration) : 0;
  const loaded = duration > 0 ? Math.min(1, buffered / duration) : 0;

  return (
    <div className="relative px-1.5">
      {/* On the line itself, as in the app, so they never stand over the picture. */}
      {marks.length > 0 && (
        <div className="pointer-events-none absolute inset-x-1.5 inset-y-0 z-10" aria-hidden="true">
          {marks.map((m) => (
            <span
              key={m.slot}
              className="absolute top-1/2 -translate-x-1/2 -translate-y-1/2 text-[13px] leading-none drop-shadow-[0_1px_2px_rgb(0_0_0/0.8)]"
              style={{ left: `${((m.slot + 0.5) / slots) * 100}%` }}
              title={m.label}
            >
              {m.emoji}
            </span>
          ))}
        </div>
      )}
      <div
        ref={trackRef}
        role="slider"
        tabIndex={tabbable ? 0 : -1}
        aria-label="Seek"
        aria-valuemin={0}
        aria-valuemax={Math.round(duration)}
        aria-valuenow={Math.round(time)}
        aria-valuetext={`${spokenTime(time)} of ${spokenTime(duration)}`}
        className="group/scrub relative flex h-8 cursor-pointer touch-none items-center focus-visible:outline-none"
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId);
          dragging.current = true;
          setActive(true);
          onScrub(timeAt(e.clientX));
        }}
        onPointerMove={(e) => {
          if (dragging.current) onScrub(timeAt(e.clientX));
          else if (e.pointerType === "mouse") setHover(timeAt(e.clientX));
        }}
        onPointerUp={(e) => {
          if (!dragging.current) return;
          dragging.current = false;
          setActive(false);
          onCommit(timeAt(e.clientX));
        }}
        onPointerCancel={() => {
          dragging.current = false;
          setActive(false);
          onScrub(null);
        }}
        onPointerLeave={() => setHover(null)}
        onKeyDown={(e) => {
          const big = duration * 0.1;
          let t: number | null = null;
          if (e.key === "ArrowLeft" || e.key === "ArrowDown") t = time - SKIP;
          else if (e.key === "ArrowRight" || e.key === "ArrowUp") t = time + SKIP;
          else if (e.key === "PageDown") t = time - big;
          else if (e.key === "PageUp") t = time + big;
          else if (e.key === "Home") t = 0;
          else if (e.key === "End") t = duration;
          if (t === null) return;
          e.preventDefault();
          e.stopPropagation();
          onKeySeek(Math.max(0, Math.min(duration, t)));
        }}
      >
        <div className="relative h-1 w-full overflow-hidden rounded-full bg-white/25 transition-[height] duration-150 group-hover/scrub:h-1.5 group-focus-visible/scrub:h-1.5 motion-reduce:transition-none">
          <div className="absolute inset-y-0 left-0 bg-white/35" style={{ width: `${loaded * 100}%` }} />
          <div className="absolute inset-y-0 left-0 bg-[var(--accent,#f04850)]" style={{ width: `${played * 100}%` }} />
        </div>
        <span
          className={`pointer-events-none absolute top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[var(--accent,#f04850)] shadow-[0_1px_4px_rgb(0_0_0/0.45)] ring-2 ring-white/0 transition-transform duration-100 group-focus-visible/scrub:ring-white motion-reduce:transition-none ${
            active ? "scale-125" : ""
          }`}
          style={{ left: `${played * 100}%` }}
        />
        {hover !== null && (
          <span
            className="pointer-events-none absolute -top-8 -translate-x-1/2 rounded-md bg-black/80 px-1.5 py-0.5 text-xs font-semibold tabular-nums"
            style={{ left: `${(hover / Math.max(duration, 0.001)) * 100}%` }}
          >
            {formatTime(hover)}
          </span>
        )}
      </div>
    </div>
  );
}
