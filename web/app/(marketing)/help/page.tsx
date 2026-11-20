import type { Metadata } from "next";
import Link from "next/link";
import { Art } from "@/components/marketing/art";
import { getHelp } from "@/components/marketing/content";
import { HelpSearch } from "@/components/marketing/help-search";
import { ArrowRight, Icon, type IconName } from "@/components/marketing/marks";
import { PageBanner } from "@/components/marketing/page-banner";
import { Container } from "@/components/marketing/sections";

export const metadata: Metadata = {
  title: "Help centre",
  description: "How to record your screen, camera or voice with Snapreel, find your recordings, share them and keep them private.",
  alternates: { canonical: "/help" },
  openGraph: { url: "/help" },
};

/* A pastel tone and an icon for each help category, by id; anything new falls back to blue. */
const look: Record<string, { tone: string; icon: IconName }> = {
  start: { tone: "mk-tile--blue", icon: "sparkle" },
  recording: { tone: "mk-tile--peach", icon: "camera" },
  screen: { tone: "mk-tile--lilac", icon: "screen" },
  library: { tone: "mk-tile--mint", icon: "folder" },
  watching: { tone: "mk-tile--butter", icon: "browser" },
  notes: { tone: "mk-tile--rose", icon: "chat" },
  sharing: { tone: "mk-tile--blue", icon: "photo" },
  links: { tone: "mk-tile--rose", icon: "link" },
  privacy: { tone: "mk-tile--mint", icon: "lock" },
  trouble: { tone: "mk-tile--butter", icon: "search" },
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
                className="inline-flex min-h-10 items-center rounded-full bg-surface px-4 text-sm font-semibold shadow-[var(--mk-card-shadow)] hover:bg-fill"
              >
                {c.title}
              </a>
            ))}
          </nav>

          <div className="mt-12 grid grid-cols-1 gap-5 md:grid-cols-2 lg:grid-cols-3">
            {byCategory.map((c) => {
              const l = look[c.id] ?? { tone: "mk-tile--blue", icon: "sparkle" as IconName };
              return (
                <section key={c.id} id={c.id} aria-labelledby={`cat-${c.id}`} className={`mk-tile ${l.tone} scroll-mt-24 p-2`}>
                  <div className="flex items-center gap-3 px-4 pb-3 pt-4">
                    <span className="mk-icon !bg-white/80 dark:!bg-white/10">
                      <Icon name={l.icon} />
                    </span>
                    <h2 id={`cat-${c.id}`} className="mk-display text-xl font-bold">
                      {c.title}
                    </h2>
                  </div>
                  <ul className="overflow-hidden rounded-[22px] bg-surface">
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

          <div className="mk-card mt-14 grid grid-cols-1 items-center gap-6 overflow-hidden p-3 md:grid-cols-[minmax(0,1.3fr)_minmax(0,0.7fr)]">
            <div className="px-4 pt-5 md:px-8 md:py-8">
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
            <div className="mk-tile mk-tile--blue flex justify-center overflow-hidden px-6 pt-8 md:h-full">
              <div className="-mb-[22%] w-[64%] max-w-[230px] md:mt-auto">
                <Art slot="help" sizes="(min-width: 768px) 230px, 64vw" />
              </div>
            </div>
          </div>
        </Container>
      </section>
    </>
  );
}
