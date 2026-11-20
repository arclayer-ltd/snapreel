import type { Metadata } from "next";
import Link from "next/link";
import { Art } from "@/components/marketing/art";
import { getHelp } from "@/components/marketing/content";
import { HelpSearch } from "@/components/marketing/help-search";
import { ArrowRight, Sparkle } from "@/components/marketing/marks";
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
      <section aria-labelledby="help-title" className="pt-3 sm:pt-5">
        <Container>
          <div className="mk-field grid grid-cols-1 items-end [--pool-x:50%] [--pool-y:90%] md:grid-cols-[minmax(0,1.3fr)_minmax(0,0.7fr)] md:[--pool-x:80%] md:[--pool-y:60%]">
            <div className="relative z-20 self-center px-6 pb-8 pt-10 sm:px-12 md:py-16">
              <p className="mk-pill w-fit">Help centre</p>
              <h1 id="help-title" className="mk-headline mt-5 text-[2.75rem] sm:text-[4rem]">
                How can <b>we help?</b>
              </h1>
              <p className="mt-4 max-w-lg text-lg text-white">The same articles you find in the app, under Settings › Help centre.</p>
              <div className="mt-7 max-w-xl">
                <HelpSearch items={items} />
              </div>
            </div>
            <div className="relative mx-auto hidden w-[62%] max-w-[260px] pt-10 md:block">
              <Sparkle size={30} top="4%" right="0%" delay={0.4} />
              <Sparkle size={14} top="36%" left="-8%" delay={1.5} />
              <Art slot="help" sizes="260px" />
            </div>
          </div>
        </Container>
      </section>

      <section aria-label="Topics" className="mt-6">
        <Container>
          <nav aria-label="Help topics" className="flex flex-wrap gap-2">
            {byCategory.map((c) => (
              <a key={c.id} href={`#${c.id}`} className="inline-flex min-h-10 items-center rounded-full bg-surface px-4 text-sm font-medium ring-1 ring-line hover:bg-fill">
                {c.title}
              </a>
            ))}
          </nav>

          <div className="mt-10 grid grid-cols-1 gap-x-8 gap-y-12 md:grid-cols-2 lg:grid-cols-3">
            {byCategory.map((c) => (
              <section key={c.id} id={c.id} aria-labelledby={`cat-${c.id}`} className="scroll-mt-24">
                <h2 id={`cat-${c.id}`} className="mk-display text-xl font-semibold">
                  {c.title}
                </h2>
                <ul className="mt-3 overflow-hidden rounded-[20px] bg-surface ring-1 ring-line">
                  {c.articles.map((a) => (
                    <li key={a.id} className="border-b border-line last:border-0">
                      <Link href={`/help/${a.id}`} className="group flex items-center gap-3 px-4 py-3.5 hover:bg-fill">
                        <span className="min-w-0 flex-1">
                          <span className="block font-medium leading-snug">{a.title}</span>
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
            ))}
          </div>

          <div className="mt-14 flex flex-col items-start justify-between gap-4 rounded-[24px] bg-surface p-6 ring-1 ring-line sm:flex-row sm:items-center sm:p-8">
            <div>
              <h2 className="mk-display text-xl font-semibold">Still stuck?</h2>
              <p className="mt-1 text-text-2">Write to us and a person will get back to you.</p>
            </div>
            <Link href="/support" className="mk-button mk-button--red">
              Contact support
            </Link>
          </div>
        </Container>
      </section>
    </>
  );
}
