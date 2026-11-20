import Link from "next/link";
import { LEGAL_ENTITY } from "@/lib/legal-entity";
import { AppStoreBadge } from "./app-store-badge";
import { SceneStage, sceneVars } from "./art";
import { ArrowRight, LogoMark } from "./marks";

const columns = [
  {
    title: "Snapreel",
    links: [
      { href: "/#record", label: "Ways to record" },
      { href: "/#features", label: "Share links" },
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

/** Every page ends on the hilltop: the download call to action over the sky, then the links. */
export function SiteFooter() {
  return (
    <footer className="mt-20 sm:mt-28">
      <section
        id="download"
        aria-labelledby="download-title"
        className="mk-scene mk-scene--flow scroll-mt-24"
        style={sceneVars("scene-footer", { "--tuck": "40px", "--tuck-d": "120px" })}
      >
        <div className="mk-scene-content mx-auto max-w-2xl px-[var(--mk-gutter)] pt-16 text-center sm:pt-24">
          <p className="mk-label">Get Snapreel</p>
          <h2 id="download-title" className="mk-title mt-4 text-[2.5rem] sm:text-[3.5rem]">
            Start recording. It&rsquo;s free.
          </h2>
          <p className="mx-auto mt-4 max-w-lg text-lg leading-relaxed text-[var(--mk-sky-ink-2)]">
            Snapreel is in TestFlight now and coming soon to the App Store. Recording, your library and everything on your
            iPhone stay free, forever.
          </p>
          <div className="mt-7 flex flex-wrap items-center justify-center gap-3">
            <AppStoreBadge />
            <Link href="/pricing" className="mk-button mk-button--white">
              Compare Free and Pro
              <ArrowRight size={18} />
            </Link>
          </div>
        </div>
        <SceneStage slot="scene-footer" sizes="100vw" />
      </section>

      <div className="relative z-10 mx-auto -mt-10 max-w-[var(--mk-max)] px-[var(--mk-gutter)] pb-8 sm:-mt-16">
        <div className="mk-panel px-6 py-10 sm:px-10 sm:py-12">
          <div className="grid grid-cols-2 gap-x-6 gap-y-10 sm:grid-cols-[minmax(0,1.5fr)_repeat(3,minmax(0,1fr))]">
            <div className="col-span-2 sm:col-span-1">
              <Link href="/" className="inline-flex items-center gap-2 rounded-full" aria-label="Snapreel home">
                <LogoMark size={28} />
                <span className="mk-display text-xl font-bold tracking-[-0.03em] text-white">Snapreel</span>
              </Link>
              <p className="mt-3 max-w-xs text-sm leading-relaxed text-white/75">
                A screen, camera and voice recorder for iPhone, made by {LEGAL_ENTITY.name}.
              </p>
              <a href={`mailto:${LEGAL_ENTITY.email}`} className="mt-3 inline-block text-sm font-semibold text-white underline underline-offset-4">
                {LEGAL_ENTITY.email}
              </a>
            </div>
            {columns.map((col) => (
              <nav key={col.title} aria-label={col.title}>
                <h2 className="text-sm font-semibold text-white">{col.title}</h2>
                <ul className="mt-3 space-y-1">
                  {col.links.map((l) => (
                    <li key={l.href}>
                      <Link href={l.href} className="inline-flex min-h-9 items-center text-sm text-white/75 transition-colors hover:text-white">
                        {l.label}
                      </Link>
                    </li>
                  ))}
                </ul>
              </nav>
            ))}
          </div>
          <p className="mt-10 border-t border-white/10 pt-6 text-xs leading-relaxed text-white/70">
            © 2026 {LEGAL_ENTITY.name}. Apple, the Apple logo, iPhone and App Store are trademarks of Apple Inc. Snapreel
            isn&rsquo;t affiliated with Apple.
          </p>
        </div>
      </div>
    </footer>
  );
}
