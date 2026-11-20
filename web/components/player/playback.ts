"use client";

// A tiny shared store between the player and what sits around it (transcript, comments, reactions):
// they read the current time and ask the player to seek, without re-rendering the player.
import { createContext, useContext, useSyncExternalStore } from "react";

export interface PlaybackState {
  time: number;
  duration: number;
  playing: boolean;
  started: boolean;
}

interface Controller {
  seek(t: number, play: boolean): void;
  play(): void;
  pause(): void;
}

export class PlaybackStore {
  private state: PlaybackState;
  private listeners = new Set<() => void>();
  private burstListeners = new Set<(emoji: string) => void>();
  private controller: Controller | null = null;

  constructor(duration: number) {
    this.state = { time: 0, duration, playing: false, started: false };
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = () => this.state;

  update(patch: Partial<PlaybackState>) {
    const next = { ...this.state, ...patch };
    if (
      next.time === this.state.time &&
      next.duration === this.state.duration &&
      next.playing === this.state.playing &&
      next.started === this.state.started
    ) {
      return;
    }
    this.state = next;
    for (const l of this.listeners) l();
  }

  attach(controller: Controller | null) {
    this.controller = controller;
  }

  seek(t: number, play = true) {
    this.controller?.seek(t, play);
  }

  play() {
    this.controller?.play();
  }

  pause() {
    this.controller?.pause();
  }

  /** Floats an emoji up over the picture. */
  burst(emoji: string) {
    for (const l of this.burstListeners) l(emoji);
  }

  onBurst(listener: (emoji: string) => void) {
    this.burstListeners.add(listener);
    return () => {
      this.burstListeners.delete(listener);
    };
  }
}

export const PlaybackContext = createContext<PlaybackStore | null>(null);

export function usePlaybackStore(): PlaybackStore {
  const store = useContext(PlaybackContext);
  if (!store) throw new Error("usePlaybackStore needs a PlaybackContext provider");
  return store;
}

export function usePlayback(): PlaybackState {
  const store = usePlaybackStore();
  return useSyncExternalStore(store.subscribe, store.getSnapshot, store.getSnapshot);
}

/** The current time rounded down to whole seconds, so readers re-render once a second at most. */
export function usePlaybackSecond(): number {
  const store = usePlaybackStore();
  return useSyncExternalStore(
    store.subscribe,
    () => Math.floor(store.getSnapshot().time),
    () => 0,
  );
}
