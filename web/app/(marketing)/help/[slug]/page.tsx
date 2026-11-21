import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getArticle, getHelp } from "@/components/marketing/content";
import { HelpBody } from "@/components/marketing/help-body";
import { helpLook } from "@/components/marketing/help-look";
import { ArrowRight, Icon } from "@/components/marketing/marks";
import { PageBanner } from "@/components/marketing/page-banner";
import { Container } from "@/components/marketing/sections";

export function generateStaticParams() {
  return getHelp().articles.map((a) => ({ slug: a.id }));
}

export async function generateMetadata({ params }: PageProps<"/help/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const article = getArticle(slug);
  if (!article) return { title: "Help" };
  return {
    title: article.title,
    description: article.summary,
    alternates: { canonical: `/help/${article.id}` },
    openGraph: { url: `/help/${article.id}`, title: article.title, description: article.summary },
  };
}

export default async function HelpArticlePage({ params }: PageProps<"/help/[slug]">) {
  const { slug } = await params;
  const { categories, articles } = getHelp();
  const article = articles.find((a) => a.id === slug);
  if (!article) notFound();
  const category = categories.find((c) => c.id === article.category);
  const related = (article.related ?? [])
    .map((id) => articles.find((a) => a.id === id))
    .filter((a): a is NonNullable<typeof a> => Boolean(a));
  const inTopic = articles.filter((a) => a.category === article.category);
  const { icon } = helpLook(category?.id);

  return (
    <>
      <PageBanner variant="strip" />
      <Container className="relative z-10 -mt-20 sm:-mt-24">
        <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_300px] lg:gap-8">
          <article className="mk-card min-w-0 px-6 pb-10 pt-7 sm:px-12 sm:pb-14 sm:pt-10 lg:px-16">
            <nav aria-label="Breadcrumb" className="text-sm font-medium text-text-2">
              <ol className="flex flex-wrap items-center gap-1">
                <li>
                  <Link href="/help" className="inline-flex min-h-8 items-center rounded-full px-2.5 hover:bg-fill hover:text-text -ml-2.5">
                    Help centre
                  </Link>
                </li>
                {category ? (
                  <>
                    <li aria-hidden="true" className="text-text-3">
                      <Chevron />
                    </li>
                    <li>
                      <Link href={`/help#${category.id}`} className="inline-flex min-h-8 items-center rounded-full px-2.5 hover:bg-fill hover:text-text">
                        {category.title}
                      </Link>
                    </li>
                  </>
                ) : null}
              </ol>
            </nav>
            <div className="max-w-[680px]">
              <h1 className="mk-title mt-5 text-[2.25rem] sm:text-[2.875rem]">{article.title}</h1>
              <p className="mt-4 text-lg leading-relaxed text-text-2 sm:text-xl">{article.summary}</p>
              <div className="mt-8 border-t border-line pt-8">
                <HelpBody blocks={article.body} />
              </div>
            </div>

            {related.length ? (
              <section aria-labelledby="related" className="mt-14 border-t border-line pt-10">
                <h2 id="related" className="mk-display text-xl font-bold">
                  Related
                </h2>
                <ul className="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  {related.map((r) => (
                    <li key={r.id}>
                      <Link
                        href={`/help/${r.id}`}
                        className="mk-card mk-card--s mk-lift group flex h-full items-start gap-3.5 p-4 shadow-[var(--mk-shadow-sm)] sm:p-5"
                      >
                        <span className="mk-icon size-9">
                          <Icon name="text" size={18} />
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block font-semibold leading-snug">{r.title}</span>
                          <span className="mt-1 block text-sm leading-snug text-text-2">{r.summary}</span>
                        </span>
                        <span className="mt-2 shrink-0 text-text-3 transition-transform group-hover:translate-x-0.5 group-hover:text-red-text">
                          <ArrowRight size={18} />
                        </span>
                      </Link>
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}
          </article>

          <aside className="flex flex-col gap-4 lg:sticky lg:top-24">
            <nav aria-labelledby="topic-title" className="mk-card mk-card--s p-2">
              <div className="flex items-center gap-3 px-3 pb-2 pt-3">
                <span className="mk-icon size-9">
                  <Icon name={icon} size={18} />
                </span>
                <h2 id="topic-title" className="mk-display text-lg font-bold leading-tight">
                  {category?.title ?? "More help"}
                </h2>
              </div>
              <ul className="mt-1 space-y-0.5">
                {inTopic.map((s) => {
                  const current = s.id === article.id;
                  return (
                    <li key={s.id}>
                      <Link
                        href={`/help/${s.id}`}
                        aria-current={current ? "page" : undefined}
                        className={`mk-squircle flex items-center gap-2 rounded-[var(--mk-r-m)] px-3 py-2.5 text-[0.9375rem] leading-snug ${
                          current ? "bg-red-soft font-semibold text-red-text" : "text-text hover:bg-fill"
                        }`}
                      >
                        <span className="min-w-0 flex-1">{s.title}</span>
                        {current ? <span className="size-1.5 shrink-0 rounded-full bg-current" aria-hidden="true" /> : null}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </nav>
            <div className="mk-card mk-card--s p-5">
              <p className="font-semibold">Can&rsquo;t find what you need?</p>
              <p className="mt-1 text-sm leading-relaxed text-text-2">Write to us and a person will get back to you.</p>
              <Link href="/support" className="mk-button mk-button--quiet mt-4 min-h-10 w-full text-sm">
                Contact support
                <ArrowRight size={16} />
              </Link>
            </div>
          </aside>
        </div>
      </Container>
    </>
  );
}

function Chevron() {
  return (
    <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="m9 6 6 6-6 6" />
    </svg>
  );
}
