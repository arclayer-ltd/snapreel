import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getArticle, getHelp } from "@/components/marketing/content";
import { HelpBody } from "@/components/marketing/help-body";
import { ArrowRight } from "@/components/marketing/marks";
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
  const siblings = articles.filter((a) => a.category === article.category && a.id !== article.id);

  return (
    <>
      <PageBanner variant="strip" />
      <Container className="relative z-10 -mt-16 sm:-mt-20">
        <div className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_320px] lg:gap-10">
          <article className="mk-card min-w-0 px-5 py-8 sm:px-10 sm:py-12">
            <nav aria-label="Breadcrumb" className="text-sm text-text-2">
              <ol className="flex flex-wrap items-center gap-1.5">
                <li>
                  <Link href="/help" className="underline-offset-4 hover:text-text hover:underline">
                    Help centre
                  </Link>
                </li>
                {category ? (
                  <>
                    <li aria-hidden="true">›</li>
                    <li>
                      <Link href={`/help#${category.id}`} className="underline-offset-4 hover:text-text hover:underline">
                        {category.title}
                      </Link>
                    </li>
                  </>
                ) : null}
              </ol>
            </nav>
            <div className="max-w-[680px]">
              <h1 className="mk-title mt-4 text-[2.25rem] sm:text-[3rem]">{article.title}</h1>
              <p className="mt-4 text-xl leading-relaxed text-text-2">{article.summary}</p>
              <div className="mt-8">
                <HelpBody blocks={article.body} />
              </div>
            </div>

            {related.length ? (
              <section aria-labelledby="related" className="mt-14 border-t border-line pt-10">
                <h2 id="related" className="mk-display text-xl font-bold">
                  Related
                </h2>
                <ul className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  {related.map((r) => (
                    <li key={r.id}>
                      <Link href={`/help/${r.id}`} className="mk-tile mk-tile--blue group flex h-full items-start gap-3 p-4 hover:brightness-[0.98]">
                        <span className="min-w-0 flex-1">
                          <span className="block font-semibold leading-snug">{r.title}</span>
                          <span className="mt-1 block text-sm text-text-2">{r.summary}</span>
                        </span>
                        <span className="mt-0.5 shrink-0 text-text-2">
                          <ArrowRight size={18} />
                        </span>
                      </Link>
                    </li>
                  ))}
                </ul>
              </section>
            ) : null}
          </article>

          <aside className="lg:pt-0">
            <div className="mk-card p-5 lg:sticky lg:top-24">
              <h2 className="text-sm font-semibold uppercase tracking-[0.1em] text-text-2">{category?.title ?? "More help"}</h2>
              <ul className="mt-3 space-y-0.5">
                {siblings.map((s) => (
                  <li key={s.id}>
                    <Link href={`/help/${s.id}`} className="block rounded-xl px-3 py-2.5 text-[0.9375rem] hover:bg-fill">
                      {s.title}
                    </Link>
                  </li>
                ))}
              </ul>
              <div className="mt-5 border-t border-line pt-5">
                <p className="text-sm text-text-2">Can&rsquo;t find what you need?</p>
                <Link href="/support" className="mk-link mt-2 inline-flex">
                  Contact support
                </Link>
              </div>
            </div>
          </aside>
        </div>
      </Container>
    </>
  );
}
