"use client";

// "This upload didn't finish", for as long as that's true: the app can send the video again under the same link, so
// the page looks now and then (and on the button) and moves on by itself.
import { useEffect, useRef, useState } from "react";
import type { PublicVideo } from "@/lib/contract";
import { ApiError, publicApi } from "@/lib/client/api";
import { btn } from "../ui-classes";
import { StateScreen } from "./StateScreen";

const CHECK_MS = 20_000;

export function FailedUpload({
  slug,
  ownerName,
  onRevived,
  onGone,
}: {
  slug: string;
  ownerName: string | null;
  onRevived: (v: PublicVideo) => void;
  onGone: (error: string) => void;
}) {
  const [checking, setChecking] = useState(false);
  const [checked, setChecked] = useState(false);
  const check = useRef<() => void>(() => {});

  useEffect(() => {
    let timer = 0;
    let stopped = false;
    let running = false;
    const run = async (asked: boolean) => {
      window.clearTimeout(timer);
      if (stopped || running) return;
      if (asked || document.visibilityState === "visible") {
        running = true;
        if (asked) setChecking(true);
        try {
          const next = await publicApi.video(slug);
          if (stopped) return;
          if (next.status !== "failed") {
            stopped = true;
            onRevived(next);
            return;
          }
        } catch (err) {
          if (!stopped && err instanceof ApiError && [401, 404, 410].includes(err.status)) {
            stopped = true;
            onGone(err.code);
            return;
          }
        } finally {
          running = false;
        }
        if (asked) {
          setChecking(false);
          setChecked(true);
        }
      }
      timer = window.setTimeout(() => void run(false), CHECK_MS);
    };
    const onVisible = () => {
      if (document.visibilityState === "visible") void run(false);
    };
    check.current = () => void run(true);
    timer = window.setTimeout(() => void run(false), CHECK_MS);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [slug, onRevived, onGone]);

  return (
    <StateScreen
      state="failed"
      ownerName={ownerName}
      extra={
        <>
          <button type="button" onClick={() => check.current()} disabled={checking} className={btn("primary", "md", "mt-6 min-w-36")}>
            {checking ? "Checking\u2026" : "Check again"}
          </button>
          <p role="status" className="mt-2 min-h-5 text-sm text-text-2">
            {checked && !checking ? "Not there yet." : ""}
          </p>
        </>
      }
    />
  );
}
