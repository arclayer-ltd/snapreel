import Link from "next/link";
import { LogoMark } from "./marks";

const nav = [
  { href: "/#record", label: "Features", wide: true },
  { href: "/pricing", label: "Pricing" },
  { href: "/help", label: "Help" },
  { href: "/support", label: "Support" },
];

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-line/70 bg-canvas/85 backdrop-blur-xl supports-[backdrop-filter]:bg-canvas/70">
      <div className="mx-auto flex h-16 max-w-[1280px] items-center justify-between gap-4 px-[var(--mk-gutter)]">
        <Link href="/" className="flex items-center gap-2 rounded-lg" aria-label="Snapreel home">
          <LogoMark size={28} />
          <span className="mk-display text-[1.3rem] font-semibold tracking-[-0.03em] text-text">Snapreel</span>
        </Link>
        <nav aria-label="Main" className="flex items-center gap-1 sm:gap-2">
          {nav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`${item.wide ? "hidden sm:inline-flex" : "inline-flex"} min-h-11 items-center rounded-full px-2.5 text-[0.9375rem] font-medium text-text-2 transition-colors hover:text-text sm:px-3`}
            >
              {item.label}
            </Link>
          ))}
          <Link href="/#download" className="mk-button mk-button--red ml-2 hidden !min-h-10 !px-4 !text-sm md:inline-flex">
            Get the app
          </Link>
        </nav>
      </div>
    </header>
  );
}
