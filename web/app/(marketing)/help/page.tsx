import type { Metadata } from "next";
import Link from "next/link";
import { getHelp } from "@/components/marketing/content";
import { HelpSearch } from "@/components/marketing/help-search";
import { PeekPhone } from "@/components/marketing/iphone";
import { helpLook } from "@/components/marketing/help-look";
import { ArrowRight, Icon } from "@/components/marketing/marks";
import { PageBanner } from "@/components/marketing/page-banner";
import { Container } from "@/components/marketing/sections";

export const metadata: Metadata = {
  title: "Help centre",
  description: "How to record your screen, camera or voice with Snapreel, find your recordings, share them and keep them private.",
  alternates: { canonical: "/help" },
  openGraph: { url: "/help" },
};

export default function HelpPage() {
  const { categories, articles } = getHelp();
  const byCategory = categories
    .map((c) => ({ ...c, articles: articles.filter((a) => a.category === c.id) }))
    .filter((c) => c.articles.length);
  const items = articles.map((a) => ({
    id: a.id,
    title: a.title,
    summary: a.summary,
    category: categories.find((c) => c.id === a.category)?.title ?? "",
  }));

  return (
    <>
      <PageBanner
        variant="hero"
        titleId="help-title"
        label="Help centre"
        title="How can we help?"
        intro="The same articles you find in the app, under Settings › Help centre."
      >
        <HelpSearch items={items} />
      </PageBanner>

      <section aria-label="Topics" className="relative z-10 mt-8">
        <Container>
          <nav aria-label="Help topics" className="flex flex-wrap justify-center gap-2">
            {byCategory.map((c) => (
              <a
                key={c.id}
                href={`#${c.id}`}
                className="inline-flex min-h-10 items-center rounded-full bg-surface px-4 text-sm font-semibold shadow-[var(--mk-shadow-sm)] hover:bg-fill"
              >
                {c.title}
              </a>
            ))}
          </nav>

          <div className="mt-12 grid grid-cols-1 gap-5 md:grid-cols-2 lg:grid-cols-3">
            {byCategory.map((c) => {
              const l = helpLook(c.id);
              return (
                <section key={c.id} id={c.id} aria-labelledby={`cat-${c.id}`} className={`mk-tile ${l.tone} scroll-mt-24 p-2`}>
                  <div className="flex items-center gap-3 px-4 pb-3 pt-4">
                    <span className="mk-icon mk-icon--on-tile">
                      <Icon name={l.icon} />
                    </span>
                    <h2 id={`cat-${c.id}`} className="mk-display text-xl font-bold">
                      {c.title}
                    </h2>
                  </div>
                  <ul className="mk-squircle overflow-hidden rounded-[var(--mk-r-l)] bg-surface shadow-[var(--mk-shadow-sm)]">
                    {c.articles.map((a) => (
                      <li key={a.id} className="border-b border-line last:border-0">
                        <Link href={`/help/${a.id}`} className="group flex items-center gap-3 px-4 py-3.5 hover:bg-fill">
                          <span className="min-w-0 flex-1">
                            <span className="block font-semibold leading-snug">{a.title}</span>
                            <span className="mt-0.5 block text-sm leading-snug text-text-2">{a.summary}</span>
                          </span>
                          <span className="shrink-0 text-text-3 transition-transform group-hover:translate-x-0.5">
                            <ArrowRight size={18} />
                          </span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </section>
              );
            })}
          </div>

          <div className="mk-card mt-14 grid grid-cols-1 items-stretch gap-6 overflow-hidden p-3 md:grid-cols-[minmax(0,1.3fr)_minmax(0,0.7fr)]">
            <div className="self-center px-4 pt-5 md:px-8 md:py-10">
              <p className="mk-label">Still stuck?</p>
              <h2 className="mk-title mt-4 text-[2rem] sm:text-[2.5rem]">Write to a person.</h2>
              <p className="mt-3 max-w-md leading-relaxed text-text-2">
                Tell us what happened and we&rsquo;ll get back to you. You can also send a message from the app, under
                Settings › Contact support.
              </p>
              <Link href="/support" className="mk-button mk-button--red mt-6">
                Contact support
                <span className="mk-button-dot" aria-hidden="true">
                  <ArrowRight size={18} />
                </span>
              </Link>
            </div>
            <div className="mk-tile mk-tile--blue mk-tile--inset flex justify-center overflow-hidden px-6 pt-8 md:h-full">
              <PeekPhone screen="help" crop={0.42} sizes="(min-width: 768px) 230px, 64vw" className="mt-auto w-[64%] max-w-[230px]" />
            </div>
          </div>
        </Container>
      </section>
    </>
  );
}
