import Link from "next/link";
import { AppIcon, ArrowRight } from "./marks";

const nav = [
  { href: "/#features", label: "Features", wide: true },
  { href: "/pricing", label: "Pricing" },
  { href: "/help", label: "Help" },
  { href: "/support", label: "Support" },
];

/** The floating white nav pill. It takes no height, so each page's scene runs up behind it. */
export function SiteHeader() {
  return (
    <header className="mk-header">
      <div className="px-[var(--mk-gutter)]">
        <div className="mk-nav">
          <Link href="/" className="flex shrink-0 items-center gap-2.5 rounded-full pr-1" aria-label="Snapreel home">
            <AppIcon size={34} />
            <span className="mk-nav-wordmark mk-display text-[1.25rem] font-bold tracking-[-0.03em]">Snapreel</span>
          </Link>
          <nav aria-label="Main" className="flex items-center gap-0.5 sm:gap-1">
            {nav.map((item) => (
              <Link key={item.href} href={item.href} className={`mk-nav-link ${item.wide ? "hidden md:inline-flex" : ""}`}>
                {item.label}
              </Link>
            ))}
          </nav>
          <a href="#download" className="mk-button mk-button--red hidden min-h-11 text-sm md:inline-flex">
            Get the app
            <span className="mk-button-dot size-8" aria-hidden="true">
              <ArrowRight size={16} />
            </span>
          </a>
        </div>
      </div>
    </header>
  );
}
