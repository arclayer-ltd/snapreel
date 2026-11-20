"use client";

// The name a viewer comments under, remembered on this device only.
const KEY = "sr_viewer_name";

export function readViewerName(): string {
  try {
    return localStorage.getItem(KEY) ?? "";
  } catch {
    return "";
  }
}

export function saveViewerName(name: string) {
  try {
    localStorage.setItem(KEY, name.trim().slice(0, 60));
  } catch {
    // Private mode: the name is asked for again next time.
  }
}
