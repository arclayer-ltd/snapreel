// Full-page states for a watch link that can't play: expired, removed, not found, upload failed.
import Image from "next/image";
import type { ReactNode } from "react";
import { SITE_URL } from "@/lib/client/links";
import watching from "../art/watching.webp";
import { btn } from "../ui-classes";
import { WatchFooter, WatchHeader } from "./WatchChrome";

export type WatchState = "expired" | "removed" | "not_found" | "failed";

const COPY: Record<WatchState, { title: string; body: (owner: string | null) => string }> = {
  expired: {
    title: "This link has expired",
    body: (owner) => `${owner ?? "The person who shared it"} set it to stop working after a while. Ask them for a new link.`,
  },
  removed: {
    title: "This video isn’t shared any more",
    body: () => "Its owner stopped sharing it, or it was taken down. If you were expecting it, ask them to send it again.",
  },
  not_found: {
    title: "We can’t find that video",
    body: () => "Check the link is complete. Snapreel links look like snapreel.video/v/ followed by ten letters and numbers.",
  },
  failed: {
    title: "This upload didn’t finish",
    body: (owner) => `${owner ?? "Whoever sent it"} can send it again from the Snapreel app, and this link will start working.`,
  },
};

export function StateScreen({ state, ownerName = null, extra }: { state: WatchState; ownerName?: string | null; extra?: ReactNode }) {
  const copy = COPY[state];
  return (
    <div className="flex min-h-svh flex-col">
      <WatchHeader logoUrl={null} ownerName={null} showBadge />
      <main className="mx-auto flex w-full max-w-md flex-1 flex-col items-center justify-center px-6 py-10 text-center">
        <div className="mb-7 w-56 overflow-hidden rounded-[2rem] bg-[#f3eee6] shadow-[0_10px_40px_rgb(19_20_27/0.12)] sm:w-64">
          <Image src={watching} alt="" priority sizes="256px" className="h-auto w-full" />
        </div>
        <h1 className="text-2xl font-semibold tracking-tight">{copy.title}</h1>
        <p className="mt-3 text-[15px] leading-relaxed text-text-2">{copy.body(ownerName)}</p>
        {extra}
        <a href={SITE_URL} className={btn("secondary", "md", "mt-7")}>
          What&rsquo;s Snapreel?
        </a>
      </main>
      <WatchFooter showBadge={false} />
    </div>
  );
}
