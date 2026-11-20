import type { Metadata } from "next";

// Interim home page: the content of the old static snapreel.video page (server/push/public/index.html), ported so
// the live site doesn't regress when the Next.js app replaces it. The website session replaces this file with the
// real marketing home page; its version wins at merge.
export const metadata: Metadata = {
  title: { absolute: "Snapreel" },
  description: "Snapreel records your screen, camera or voice on iPhone. Your recordings stay on your iPhone.",
};

export default function Home() {
  return (
    <div className="flex min-h-screen flex-1 flex-col bg-surface text-text">
      <main className="mx-auto flex w-full max-w-[560px] flex-1 flex-col justify-center px-5 py-12 text-[17px] leading-normal">
        <div className="mb-7 grid h-14 w-14 place-items-center rounded-2xl bg-sr-red" aria-hidden="true">
          <span className="h-[22px] w-[22px] rounded-full bg-white shadow-[0_0_0_6px_rgba(255,255,255,0.28)]" />
        </div>
        <h1 className="mb-3 text-[40px] font-bold leading-[1.1] tracking-[-0.02em]">Snapreel</h1>
        <p className="mb-3.5 text-text-2">
          Record your screen, your camera or your voice on iPhone, then watch, title and share the recording.
        </p>
        <p className="mb-3.5 text-text-2">No account and no cloud: your recordings stay on your iPhone.</p>
        <p className="mb-3.5 text-text-2">
          Questions?{" "}
          <a className="text-sr-red hover:underline" href="mailto:support@snapreel.video">
            support@snapreel.video
          </a>
        </p>
      </main>
      <footer className="mx-auto w-full max-w-[560px] border-t border-line p-5 text-sm text-text-2">© 2026 Arclayer Ltd</footer>
    </div>
  );
}
