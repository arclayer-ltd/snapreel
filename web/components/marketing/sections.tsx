import type { ReactNode } from "react";
import { inline } from "./markdown";
import { Check } from "./marks";

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
  return <div className={`mx-auto w-full max-w-[var(--mk-max)] px-[var(--mk-gutter)] ${className}`}>{children}</div>;
}

/** A section's label pill, headline and intro, as the reference's "FEATURES / All the tools…". */
export function SectionHeading({
  label,
  title,
  intro,
  id,
  center = false,
  className = "",
}: {
  label?: string;
  title: ReactNode;
  intro?: ReactNode;
  id?: string;
  center?: boolean;
  className?: string;
}) {
  return (
    <div className={`${center ? "mx-auto text-center" : ""} max-w-2xl ${className}`}>
      {label ? <p className="mk-label">{label}</p> : null}
      <h2 id={id} className={`mk-title text-[2.25rem] sm:text-[3rem] ${label ? "mt-4" : ""}`}>
        {title}
      </h2>
      {intro ? (
        <p className={`mt-4 text-lg leading-relaxed text-text-2 ${center ? "mx-auto max-w-xl" : "max-w-xl"}`}>{intro}</p>
      ) : null}
    </div>
  );
}

/** "Get Pro in the Snapreel app": a label, not a button. The website sells nothing. */
export function InAppNote({ className = "" }: { className?: string }) {
  return (
    <p className={`inline-flex min-h-12 items-center gap-2.5 rounded-full bg-white px-5 text-[0.9375rem] font-semibold text-sr-ink ${className}`}>
      <svg aria-hidden="true" viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
      </svg>
      Get Pro in the Snapreel app
    </p>
  );
}

export function PlanCards({ detailed = false }: { detailed?: boolean }) {
  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
      <div className="mk-card flex flex-col p-6 sm:p-8">
        <h2 className="mk-display text-2xl font-bold">Free</h2>
        <p className="mt-1 text-text-2">Everything on your iPhone, and links to get started.</p>
        <p className="mt-6 flex items-baseline gap-2">
          <span className="mk-display text-5xl font-bold tracking-[-0.03em]">$0</span>
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

      <div className="mk-panel flex flex-col p-6 sm:p-8">
        <h2 className="mk-display flex items-center gap-2.5 text-2xl font-bold">
          Snapreel Pro
          <span className="rounded-md bg-sr-red-deep px-1.5 py-0.5 text-[0.6875rem] font-bold tracking-[0.08em] text-white">PRO</span>
        </h2>
        <p className="mt-1 text-white/75">For links that look like yours.</p>
        <p className="mt-6 flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span className="mk-display text-5xl font-bold tracking-[-0.03em]">{PRICE_MONTHLY}</span>
          <span>a month</span>
          <span className="w-full text-white/75 sm:w-auto">or {PRICE_YEARLY} a year</span>
        </p>
        <p className="mt-2 text-sm text-white/75">Try the yearly plan free for 7 days.</p>
        <p className="mt-6 text-sm font-semibold text-white">Everything in Free, plus:</p>
        <ul className="mt-3 space-y-3">
          {proFeatures.map((f) => (
            <li key={f} className="flex gap-3 text-[0.9375rem] leading-snug">
              <Check className="mt-0.5 shrink-0 text-sr-red-glow" />
              <span>{f}</span>
            </li>
          ))}
        </ul>
        <div className="mt-auto pt-8">
          <InAppNote />
          <p className="mt-3 text-sm text-white/75">
            In the app, go to <strong className="text-white">Settings › Snapreel Pro</strong>. Billed through your Apple Account.
          </p>
        </div>
      </div>
    </div>
  );
}

export type FaqItem = { q: string; a: string };

export function Faq({ items }: { items: FaqItem[] }) {
  return (
    <div className="space-y-3">
      {items.map((item) => (
        <details key={item.q} className="mk-faq mk-card group !rounded-[22px]">
          <summary className="flex min-h-16 items-center justify-between gap-4 px-5 py-4 text-left text-[1.0625rem] font-semibold sm:px-7">
            <span>{item.q}</span>
            <span className="mk-faq-icon grid size-8 shrink-0 place-items-center rounded-full bg-red-soft text-red-text" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
                <path d="M12 5v14M5 12h14" />
              </svg>
            </span>
          </summary>
          <div className="px-5 pb-6 text-[0.9875rem] leading-relaxed text-text-2 sm:px-7 [&_a]:font-medium [&_a]:text-red-text [&_a]:underline [&_a]:underline-offset-4 [&_strong]:text-text">
            {inline(item.a)}
          </div>
        </details>
      ))}
    </div>
  );
}
