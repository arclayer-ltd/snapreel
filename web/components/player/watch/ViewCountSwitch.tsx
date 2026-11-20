"use client";

// "Don't count my views" in the watch page footer (the simple way to object to view statistics that the UK
// statistical-purposes cookie exception and CNIL's audience-measurement exemption ask for). It sets the sr_nocount
// cookie through the API, for a year, on every Snapreel link in this browser; the view beacons then stop, and the
// server ignores any that still arrive. Watching, comments and reactions are unchanged.
import { useEffect, useId, useState } from "react";
import { publicApi, viewsOptedOut } from "@/lib/client/api";

export function ViewCountSwitch() {
  const [optedOut, setOptedOut] = useState(false);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const hintId = useId();

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the cookie is only readable after mount
    setOptedOut(viewsOptedOut());
  }, []);

  async function toggle() {
    const next = !optedOut;
    setBusy(true);
    setFailed(false);
    setOptedOut(next);
    try {
      const saved = await publicApi.setViewOptOut(next);
      setOptedOut(saved.optOut);
    } catch {
      setOptedOut(!next);
      setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <span className="inline-flex items-center gap-2">
      <button
        type="button"
        role="switch"
        aria-checked={optedOut}
        aria-describedby={hintId}
        disabled={busy}
        onClick={toggle}
        className="inline-flex items-center gap-2 rounded hover:text-text focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sr-red disabled:opacity-60"
      >
        <span
          aria-hidden="true"
          className={`relative inline-flex h-[18px] w-[30px] shrink-0 items-center rounded-full transition-colors duration-150 motion-reduce:transition-none ${
            optedOut ? "bg-sr-red-deep" : "bg-line"
          }`}
        >
          <span
            className={`inline-block h-[14px] w-[14px] rounded-full bg-white shadow-[0_1px_3px_rgb(0_0_0/0.25)] transition-transform duration-150 motion-reduce:transition-none ${
              optedOut ? "translate-x-[14px]" : "translate-x-[2px]"
            }`}
          />
        </span>
        Don&rsquo;t count my views
      </button>
      <span id={hintId} className="sr-only">
        Stops your views being recorded on Snapreel links in this browser. You can still watch, comment and react.
      </span>
      {failed && (
        <span role="alert" className="text-red-text">
          Didn&rsquo;t save. Try again.
        </span>
      )}
    </span>
  );
}
