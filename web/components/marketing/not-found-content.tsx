import Link from "next/link";
import { Spot } from "./art";
import { ArrowRight } from "./marks";
import { PageBanner } from "./page-banner";
import { Container } from "./sections";

/** The 404 page body: a missing help article (app/(marketing)/not-found.tsx) or an address that matches no
 *  route at all (app/not-found.tsx). */
export function NotFoundContent() {
  return (
    <>
      <PageBanner variant="strip" />
      <Container className="relative z-10 -mt-16 sm:-mt-20">
        <div className="mk-card mx-auto grid max-w-[880px] grid-cols-1 items-center gap-8 overflow-hidden p-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,0.8fr)]">
          <div className="px-4 pb-2 pt-6 sm:px-8 sm:py-10">
            <p className="mk-label">Page not found</p>
            <h1 className="mk-title mt-4 text-[2.5rem] sm:text-[3rem]">This path doesn&rsquo;t go anywhere.</h1>
            <p className="mt-4 leading-relaxed text-text-2">
              The page may have moved, or the address has a typo. The help centre and the home page are a good place to
              start again.
            </p>
            <div className="mt-6 flex flex-wrap gap-3">
              <Link href="/" className="mk-button mk-button--red">
                Go home
                <span className="mk-button-dot" aria-hidden="true">
                  <ArrowRight size={18} />
                </span>
              </Link>
              <Link href="/help" className="mk-button mk-button--quiet">
                Help centre
              </Link>
            </div>
          </div>
          <Spot slot="spot-watch" sizes="(min-width: 640px) 360px, 100vw" className="mk-squircle aspect-[4/5] rounded-[calc(var(--mk-r-xl)-12px)] sm:aspect-auto sm:h-full sm:min-h-[380px]" />
        </div>
      </Container>
    </>
  );
}
