import { getLegal } from "./content";
import { Blocks, prepareLegal } from "./markdown";
import { Container } from "./sections";

/** Renders docs/legal/{privacy-policy,terms-of-use}.md at build time. */
export function LegalPage({ doc, fallbackTitle }: { doc: "privacy" | "terms"; fallbackTitle: string }) {
  const { title, updated, draft, blocks } = prepareLegal(getLegal(doc));
  return (
    <Container className="pt-6 sm:pt-10">
      <div className="mx-auto max-w-[760px]">
        <p className="text-sm font-semibold uppercase tracking-[0.12em] text-red-text">Legal</p>
        <h1 className="mk-headline mt-3 text-[2.75rem] text-text sm:text-[3.5rem]">{title || fallbackTitle}</h1>
        {updated ? <p className="mt-3 text-text-2">{updated}</p> : null}
        {draft ? (
          <p className="mt-6 rounded-2xl bg-red-soft px-4 py-3 text-[0.95rem] text-text">
            This is a draft while Snapreel is in TestFlight. It may change before the App Store release, and the date
            above will change with it.
          </p>
        ) : null}
        <div className="mk-prose mt-8">
          <Blocks blocks={blocks} />
        </div>
      </div>
    </Container>
  );
}
