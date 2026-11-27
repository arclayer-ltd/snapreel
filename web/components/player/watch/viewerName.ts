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

// Comments written in this browser, so their writer can delete them (the server checks too). Newest 300 kept.
const MINE = "sr_my_comments";

function readMine(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(MINE) ?? "[]");
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  } catch {
    return [];
  }
}

export function isMine(id: string): boolean {
  return readMine().includes(id);
}

export function rememberMine(id: string) {
  try {
    localStorage.setItem(MINE, JSON.stringify([...readMine().filter((x) => x !== id), id].slice(-300)));
  } catch {}
}

export function forgetMine(id: string) {
  try {
    localStorage.setItem(MINE, JSON.stringify(readMine().filter((x) => x !== id)));
  } catch {}
}
