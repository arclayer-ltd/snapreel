import { getLegal } from "./content";
import { Blocks, prepareLegal } from "./markdown";
import { PageBanner } from "./page-banner";
import { Container } from "./sections";

/** Renders docs/legal/{privacy-policy,terms-of-use}.md at build time. */
export function LegalPage({ doc, fallbackTitle }: { doc: "privacy" | "terms"; fallbackTitle: string }) {
  const { title, updated, draft, blocks } = prepareLegal(getLegal(doc));
  return (
    <>
      <PageBanner variant="strip" />
      <Container className="relative z-10 -mt-16 sm:-mt-20">
        <article className="mk-card mx-auto max-w-[800px] px-5 py-8 sm:px-14 sm:py-14">
          <p className="mk-label">Legal</p>
          <h1 className="mk-title mt-4 text-[2.5rem] sm:text-[3.25rem]">{title || fallbackTitle}</h1>
          {updated ? <p className="mt-3 text-text-2">{updated}</p> : null}
          {draft ? (
            <p className="mk-squircle mt-6 rounded-[var(--mk-r-m)] bg-red-soft px-4 py-3 text-[0.95rem] text-text">
              This is a draft while Snapreel is in TestFlight. It may change before the App Store release, and the date
              above will change with it.
            </p>
          ) : null}
          <div className="mk-prose mt-8">
            <Blocks blocks={blocks} />
          </div>
        </article>
      </Container>
    </>
  );
}
