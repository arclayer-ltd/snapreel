import Link from "next/link";
import type { ReactNode } from "react";
import { AppStoreBadge } from "./app-store-badge";
import { inline } from "./markdown";
import { ArrowRight, Check, MotionStrokes, Sparkle } from "./marks";

/* Plans: the numbers come from docs/plans/PREMIUM-PLAN.md section 3. Pro is sold only through
   in-app purchase (App Store guideline 3.1.1), so nothing here links to a web checkout. */

export const PRICE_MONTHLY = "$5.99";
export const PRICE_YEARLY = "$39.99";

export const freeFeatures = [
  "Record your screen, camera or voice, as much as you like",
  "Library, folders, tags, search, transcripts and notes on your iPhone",
  "Save to Photos and send the video file anywhere",
  "25 share links, up to 5 minutes each, at 720p",
  "Views and unique viewers on every link",
  "Comments and emoji reactions, with alerts",
];

export const proFeatures = [
  "Unlimited share links, up to 2 hours each",
  "1080p on the web",
  "Who watched, how far, where they dropped off, and from which countries",
  "Password, link expiry, and downloads on or off",
  "A call-to-action button on your videos",
  "Your logo and colour, and no “Made with Snapreel”",
];

export function Container({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`mx-auto w-full max-w-[1280px] px-[var(--mk-gutter)] ${className}`}>{children}</div>;
}

export function SectionHeading({
  eyebrow,
  title,
  intro,
  id,
  className = "",
}: {
  eyebrow?: string;
  title: ReactNode;
  intro?: ReactNode;
  id?: string;
  className?: string;
}) {
  return (
    <div className={`mk-on-canvas max-w-3xl ${className}`}>
      {eyebrow ? <p className="text-sm font-semibold uppercase tracking-[0.12em] text-red-text">{eyebrow}</p> : null}
      <h2 id={id} className="mk-headline mt-3 text-[2.25rem] text-text sm:text-[3.25rem]">
        {title}
      </h2>
      {intro ? <p className="mt-4 max-w-2xl text-lg leading-relaxed text-text-2">{intro}</p> : null}
    </div>
  );
}

export function PlanCards({ detailed = false }: { detailed?: boolean }) {
  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
      <div className="flex flex-col rounded-[24px] bg-surface p-6 shadow-[0_1px_0_rgb(0_0_0/0.04)] ring-1 ring-line sm:p-8">
        <h2 className="mk-display text-2xl font-semibold">Free</h2>
        <p className="mt-1 text-text-2">Everything on your iPhone, and links to get started.</p>
        <p className="mt-6 flex items-baseline gap-2">
          <span className="mk-display text-5xl font-semibold tracking-[-0.03em]">$0</span>
          <span className="text-text-2">forever</span>
        </p>
        <ul className="mt-6 space-y-3">
          {freeFeatures.map((f) => (
            <li key={f} className="flex gap-3 text-[0.9375rem] leading-snug">
              <Check className="mt-0.5 shrink-0 text-red-text" />
              <span>{f}</span>
            </li>
          ))}
        </ul>
        {detailed ? (
          <p className="mt-auto pt-8 text-sm text-text-2">No account needed to record. You sign in only when you make your first link.</p>
        ) : null}
      </div>

      <div className="mk-field mk-field--deep flex flex-col p-6 sm:p-8" style={{ ["--pool-x" as string]: "85%", ["--pool-y" as string]: "8%" }}>
        <Sparkle size={22} top="22px" right="26px" delay={0.8} />
        <Sparkle size={12} top="58px" right="64px" delay={2} />
        <h2 className="mk-display relative text-2xl font-semibold">Snapreel Pro</h2>
        <p className="relative mt-1 text-white">For links that look like yours.</p>
        <p className="relative mt-6 flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span className="mk-display text-5xl font-semibold tracking-[-0.03em]">{PRICE_MONTHLY}</span>
          <span>a month</span>
          <span className="w-full text-white sm:w-auto">or {PRICE_YEARLY} a year</span>
        </p>
        <p className="relative mt-2 text-sm text-white">Try the yearly plan free for 7 days.</p>
        <p className="relative mt-6 text-sm font-semibold text-sr-cream">Everything in Free, plus:</p>
        <ul className="relative mt-3 space-y-3">
          {proFeatures.map((f) => (
            <li key={f} className="flex gap-3 text-[0.9375rem] leading-snug">
              <Check className="mt-0.5 shrink-0 text-sr-cream" />
              <span>{f}</span>
            </li>
          ))}
        </ul>
        <div className="relative mt-auto pt-8">
          <p className="inline-flex items-center gap-2 rounded-full bg-white px-4 py-3 text-[0.9375rem] font-semibold text-sr-ink">
            Get Pro in the Snapreel app
          </p>
          <p className="mt-3 text-sm text-white">
            In the app, go to <strong>Settings › Snapreel Pro</strong>. Billed through your Apple Account.
          </p>
        </div>
      </div>
    </div>
  );
}

export type FaqItem = { q: string; a: string };

export function Faq({ items }: { items: FaqItem[] }) {
  return (
    <div className="divide-y divide-line overflow-hidden rounded-[24px] bg-surface ring-1 ring-line">
      {items.map((item) => (
        <details key={item.q} className="mk-faq group">
          <summary className="flex min-h-16 items-center justify-between gap-4 px-5 py-4 text-left text-[1.0625rem] font-semibold sm:px-7">
            <span>{item.q}</span>
            <span className="mk-faq-icon grid grid-cols-1 size-8 shrink-0 place-items-center rounded-full bg-fill text-text" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
                <path d="M12 5v14M5 12h14" />
              </svg>
            </span>
          </summary>
          <div className="px-5 pb-6 text-[0.9875rem] leading-relaxed text-text-2 sm:px-7">{inline(item.a)}</div>
        </details>
      ))}
    </div>
  );
}

export function DownloadCta({ id = "download" }: { id?: string }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="mt-20 scroll-mt-24 sm:mt-28">
      <Container>
        <div className="mk-field px-6 py-14 text-center sm:px-12 sm:py-20" style={{ ["--pool-x" as string]: "50%", ["--pool-y" as string]: "110%", ["--pool-size" as string]: "70%" }}>
          <Sparkle size={22} top="18px" left="20px" delay={0.2} />
          <Sparkle size={14} bottom="22px" right="26px" delay={1.4} />
          <Sparkle size={34} top="20%" left="9%" delay={0.9} className="hidden lg:block" />
          <Sparkle size={24} top="26%" right="11%" delay={1.7} className="hidden lg:block" />
          <Sparkle size={12} top="68%" right="19%" delay={2.1} className="hidden lg:block" />
          <MotionStrokes size={54} top="10%" right="22%" rotate={10} className="hidden lg:block" />
          <div className="relative mx-auto max-w-2xl">
            <h2 id={`${id}-title`} className="mk-headline text-[2.5rem] sm:text-[4rem]">
              Start recording. <b>It&rsquo;s free.</b>
            </h2>
            <p className="mx-auto mt-4 max-w-lg text-lg text-white">
              Snapreel is in TestFlight now and coming soon to the App Store. Recording, your library and everything on
              your iPhone stay free, forever.
            </p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <AppStoreBadge />
              <Link href="/pricing" className="mk-button mk-button--ghost">
                Compare Free and Pro
                <ArrowRight size={18} />
              </Link>
            </div>
          </div>
        </div>
      </Container>
    </section>
  );
}
