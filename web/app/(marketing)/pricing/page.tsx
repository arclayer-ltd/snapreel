import type { Metadata } from "next";
import { Art } from "@/components/marketing/art";
import { Check, MotionStrokes, Sparkle } from "@/components/marketing/marks";
import {
  Container,
  DownloadCta,
  Faq,
  PlanCards,
  PRICE_MONTHLY,
  PRICE_YEARLY,
  SectionHeading,
  type FaqItem,
} from "@/components/marketing/sections";

export const metadata: Metadata = {
  title: "Pricing",
  description: `Snapreel is free on your iPhone, forever. Snapreel Pro adds unlimited share links, full viewer insights, passwords and your branding for ${PRICE_MONTHLY} a month or ${PRICE_YEARLY} a year, in the app.`,
  alternates: { canonical: "/pricing" },
  openGraph: { url: "/pricing" },
};

type Row = { label: string; free: string | boolean; pro: string | boolean };

const rows: { group: string; rows: Row[] }[] = [
  {
    group: "On your iPhone",
    rows: [
      { label: "Record your screen, camera or voice", free: true, pro: true },
      { label: "Library, folders, tags and search", free: true, pro: true },
      { label: "Transcripts and notes", free: true, pro: true },
      { label: "Save to Photos, send the video file", free: true, pro: true },
    ],
  },
  {
    group: "Share links",
    rows: [
      { label: "Active links", free: "25", pro: "Unlimited" },
      { label: "Length of each video", free: "Up to 5 minutes", pro: "Up to 2 hours" },
      { label: "Quality on the web", free: "720p", pro: "1080p" },
      { label: "Views and unique viewers", free: true, pro: true },
      { label: "Who watched, how far, drop-off and countries", free: false, pro: true },
      { label: "Comments and emoji reactions, with alerts", free: true, pro: true },
      { label: "Password, expiry, downloads on or off", free: false, pro: true },
      { label: "Call-to-action button", free: false, pro: true },
      { label: "Your logo and colour, no “Made with Snapreel”", free: false, pro: true },
      { label: "Web dashboard at snapreel.video/app", free: true, pro: true },
    ],
  },
];

const faq: FaqItem[] = [
  {
    q: "Where do I buy Pro?",
    a: "Inside the Snapreel app on your iPhone, at **Settings › Snapreel Pro**. Pro is sold through the App Store, so there's nothing to buy on this website.",
  },
  {
    q: "How does the free trial work?",
    a: `The yearly plan starts with 7 days free. If you don't cancel at least 24 hours before the trial ends, it becomes ${PRICE_YEARLY} a year. You won't be charged during the trial.`,
  },
  {
    q: "How do I cancel?",
    a: "On your iPhone, open **Settings**, tap your name, then **Subscriptions › Snapreel**. You keep Pro until the end of the period you've paid for.",
  },
  {
    q: "Does Pro change anything on my iPhone?",
    a: "No. Recording, your library and everything on your iPhone are the same on Free and Pro. Pro only changes what your share links can do.",
  },
  {
    q: "Are the prices the same everywhere?",
    a: "The prices here are in US dollars. The App Store shows the price in your own currency before you confirm, including any local taxes.",
  },
];

function Cell({ value }: { value: string | boolean }) {
  if (value === true)
    return (
      <span className="inline-flex items-center gap-1.5 text-red-text">
        <Check />
        <span className="sr-only">Included</span>
      </span>
    );
  if (value === false)
    return (
      <span className="text-text-3" aria-label="Not included">
        –
      </span>
    );
  return <span className="font-medium">{value}</span>;
}

export default function PricingPage() {
  return (
    <>
      <section aria-labelledby="pricing-hero" className="pt-3 sm:pt-5">
        <Container>
          <div className="mk-field grid grid-cols-1 items-end [--pool-x:50%] [--pool-y:86%] md:grid-cols-[minmax(0,1.2fr)_minmax(0,0.8fr)] md:[--pool-x:78%] md:[--pool-y:55%]">
            <div className="relative z-10 self-center px-6 pt-10 sm:px-12 md:py-16">
              <p className="mk-pill w-fit">Pricing</p>
              <h1 id="pricing-hero" className="mk-headline mt-5 text-[2.75rem] sm:text-[4rem]">
                Free to record. <b>Pro when you share more.</b>
              </h1>
              <p className="mt-5 max-w-xl text-lg leading-relaxed text-white">
                Everything on your iPhone is free, forever. Pro is for people who send a lot of links and want to know
                what happens to them. Get it in the Snapreel app.
              </p>
            </div>
            <div className="relative mx-auto w-[70%] max-w-[300px] py-8 md:pt-12">
              <Sparkle size={34} top="6%" right="4%" delay={0.3} />
              <Sparkle size={16} top="40%" left="-4%" delay={1.4} />
              <MotionStrokes size={54} top="0%" left="18%" rotate={-12} />
              <div className="mk-float">
                <Art slot="celebrate" priority sizes="(min-width: 768px) 300px, 70vw" />
              </div>
              <span className="mk-ground" aria-hidden="true" />
            </div>
          </div>
        </Container>
      </section>

      <section aria-label="Plans" className="mt-6">
        <Container>
          <PlanCards detailed />
          <p className="mt-4 text-sm leading-relaxed text-text-2">
            Prices in US dollars. Payment is charged to your Apple Account when you confirm. Subscriptions renew
            automatically unless you cancel at least 24 hours before the end of the current period, and you can manage
            or cancel them in your iPhone&rsquo;s Settings. See the{" "}
            <a href="/terms" className="text-red-text underline underline-offset-4">
              terms of use
            </a>{" "}
            and{" "}
            <a href="/privacy" className="text-red-text underline underline-offset-4">
              privacy policy
            </a>
            .
          </p>
        </Container>
      </section>

      <section aria-labelledby="compare-title" className="mt-20 sm:mt-28">
        <Container>
          <SectionHeading
            id="compare-title"
            title={
              <>
                Compare <b>Free and Pro.</b>
              </>
            }
          />
          <div className="mt-8 overflow-hidden rounded-[24px] bg-surface ring-1 ring-line">
            <table className="w-full table-fixed border-collapse text-left text-[0.9375rem]">
              <caption className="sr-only">What Free and Pro include</caption>
              <colgroup>
                <col />
                <col className="w-[27%] sm:w-[22%]" />
                <col className="w-[27%] sm:w-[22%]" />
              </colgroup>
              <thead>
                <tr className="border-b border-line">
                  <th scope="col" className="px-4 py-4 font-semibold sm:px-7">
                    <span className="sr-only">Feature</span>
                  </th>
                  <th scope="col" className="mk-display px-2 py-4 text-lg font-semibold sm:px-4">
                    Free
                  </th>
                  <th scope="col" className="mk-display px-2 py-4 text-lg font-semibold text-red-text sm:px-4">
                    Pro
                  </th>
                </tr>
              </thead>
              {rows.map((g) => (
                <tbody key={g.group}>
                  <tr>
                    <th scope="colgroup" colSpan={3} className="bg-fill/60 px-4 py-2.5 text-xs font-semibold uppercase tracking-[0.1em] text-text-2 sm:px-7">
                      {g.group}
                    </th>
                  </tr>
                  {g.rows.map((r) => (
                    <tr key={r.label} className="border-t border-line">
                      <th scope="row" className="px-4 py-3.5 font-normal leading-snug sm:px-7">
                        {r.label}
                      </th>
                      <td className="px-2 py-3.5 sm:px-4">
                        <Cell value={r.free} />
                      </td>
                      <td className="px-2 py-3.5 sm:px-4">
                        <Cell value={r.pro} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              ))}
            </table>
          </div>
        </Container>
      </section>

      <section aria-labelledby="pricing-faq" className="mt-20 sm:mt-28">
        <Container className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
          <SectionHeading
            id="pricing-faq"
            title={
              <>
                Billing, <b>plainly.</b>
              </>
            }
            intro="Pro is bought, managed and cancelled through the App Store, like any other iPhone subscription."
          />
          <Faq items={faq} />
        </Container>
      </section>

      <section aria-label="Pro in the app" className="mt-20 sm:mt-28">
        <Container>
          <div className="grid grid-cols-1 items-center gap-8 rounded-[28px] bg-surface p-3 ring-1 ring-line md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
            <div className="mk-field flex justify-center px-6 py-8 [--pool-x:50%] [--pool-y:50%]">
              <Sparkle size={24} top="10%" left="14%" delay={0.5} />
              <Sparkle size={12} top="30%" right="16%" delay={1.6} />
              <div className="w-[58%] max-w-[240px]">
                <Art slot="pro" sizes="(min-width: 768px) 240px, 58vw" />
              </div>
            </div>
            <div className="mk-on-canvas px-4 pb-6 md:px-6 md:pb-0">
              <h2 className="mk-headline text-[2rem] text-text sm:text-[2.75rem]">
                Get Pro <b>in the Snapreel app.</b>
              </h2>
              <ol className="mt-5 space-y-3 text-[1.0625rem]">
                {["Open Snapreel on your iPhone.", "Go to Settings › Snapreel Pro.", "Pick monthly or yearly and confirm with your Apple Account."].map(
                  (step, i) => (
                    <li key={step} className="flex items-start gap-3">
                      <span className="grid grid-cols-1 size-7 shrink-0 place-items-center rounded-full bg-red-soft text-sm font-semibold text-red-text">
                        {i + 1}
                      </span>
                      <span className="pt-0.5">{step}</span>
                    </li>
                  ),
                )}
              </ol>
              <p className="mt-5 text-text-2">You also see the Pro offer when you reach a Free limit, like your 26th link or a recording over 5 minutes.</p>
            </div>
          </div>
        </Container>
      </section>

      <DownloadCta />
    </>
  );
}
