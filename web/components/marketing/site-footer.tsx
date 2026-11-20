import Link from "next/link";
import { Art } from "./art";
import { LogoMark, MotionStrokes, Sparkle } from "./marks";

const columns = [
  {
    title: "Snapreel",
    links: [
      { href: "/#record", label: "Ways to record" },
      { href: "/#links", label: "Share links" },
      { href: "/#pro", label: "Snapreel Pro" },
      { href: "/pricing", label: "Pricing" },
    ],
  },
  {
    title: "Help",
    links: [
      { href: "/help", label: "Help centre" },
      { href: "/support", label: "Contact support" },
      { href: "/support#report", label: "Report a video" },
      { href: "/support#delete", label: "Delete your account" },
    ],
  },
  {
    title: "Legal",
    links: [
      { href: "/privacy", label: "Privacy policy" },
      { href: "/terms", label: "Terms of use" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="mt-16 pb-10 sm:mt-24">
      <div className="mx-auto max-w-[1280px] px-[var(--mk-gutter)]">
        <div className="mk-field mk-field--deep px-6 pt-10 sm:px-12 sm:pt-14" style={{ ["--pool-y" as string]: "85%", ["--pool-x" as string]: "50%" }}>
          <Sparkle size={22} top="16px" right="18px" delay={0.4} />
          <Sparkle size={30} top="18%" left="7%" delay={1.6} className="hidden md:block" />
          <Sparkle size={16} top="34%" right="8%" delay={2.2} className="hidden md:block" />
          <MotionStrokes size={52} top="12%" left="20%" rotate={-30} className="hidden lg:block" />
          <div className="relative z-10 mx-auto flex max-w-2xl flex-col items-center text-center">
            <p className="mk-headline text-[2rem] sm:text-[2.75rem]">
              Show it, <b>don&rsquo;t type it.</b>
            </p>
          </div>
          <div className="relative mx-auto mt-6 max-w-[1000px] sm:mt-2">
            <Art slot="group" sizes="(min-width: 1080px) 1000px, 92vw" />
          </div>
        </div>

        <div className="mt-12 grid grid-cols-2 gap-x-6 gap-y-10 sm:grid-cols-[minmax(0,1.4fr)_repeat(3,minmax(0,1fr))]">
          <div className="col-span-2 sm:col-span-1">
            <Link href="/" className="inline-flex items-center gap-2 rounded-lg" aria-label="Snapreel home">
              <LogoMark size={26} />
              <span className="mk-display text-xl font-semibold tracking-[-0.03em]">Snapreel</span>
            </Link>
            <p className="mt-3 max-w-xs text-sm leading-relaxed text-text-2">
              A screen, camera and voice recorder for iPhone, made by Arclayer Ltd.
            </p>
            <a href="mailto:support@snapreel.video" className="mt-3 inline-block text-sm font-medium text-red-text underline underline-offset-4">
              support@snapreel.video
            </a>
          </div>
          {columns.map((col) => (
            <nav key={col.title} aria-label={col.title}>
              <h2 className="text-sm font-semibold text-text">{col.title}</h2>
              <ul className="mt-3 space-y-1">
                {col.links.map((l) => (
                  <li key={l.href}>
                    <Link href={l.href} className="inline-flex min-h-9 items-center text-sm text-text-2 transition-colors hover:text-text">
                      {l.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <p className="mt-10 border-t border-line pt-6 text-xs leading-relaxed text-text-2">
          © 2026 Arclayer Ltd. Apple, the Apple logo, iPhone and App Store are trademarks of Apple Inc. Snapreel isn&rsquo;t
          affiliated with Apple.
        </p>
      </div>
    </footer>
  );
}
