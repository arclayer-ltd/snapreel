import type { Metadata } from "next";
import Link from "next/link";
import { Art, SceneStage, sceneVars } from "@/components/marketing/art";
import { Check } from "@/components/marketing/marks";
import {
  Container,
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
      <span className="inline-flex size-7 items-center justify-center rounded-full bg-red-soft text-red-text">
        <Check size={16} />
        <span className="sr-only">Included</span>
      </span>
    );
  if (value === false)
    return (
      <span className="text-text-3" aria-label="Not included">
        –
      </span>
    );
  return <span className="font-semibold">{value}</span>;
}

export default function PricingPage() {
  return (
    <>
      <section
        aria-labelledby="pricing-hero"
        className="mk-scene mk-scene--flow mk-scene--top"
        style={sceneVars("scene-pricing", {
          "--tuck": "80px",
          "--tuck-d": "calc(17.4vw - 20px)",
          "--pw": "15%",
          "--pb": "5%",
          "--pw-m": "40%",
          "--pb-m": "4%",
        })}
      >
        <div className="mk-scene-content mx-auto max-w-[920px] px-[var(--mk-gutter)] pt-28 text-center sm:pt-32 lg:pt-36">
          <p className="mk-label">Pricing</p>
          <h1 id="pricing-hero" className="mk-title mt-4 text-[2.625rem] sm:text-[3.5rem] lg:text-[4rem]">
            Free to record. Pro when you share more.
          </h1>
          <p className="mx-auto mt-5 max-w-xl text-lg leading-relaxed text-[var(--mk-sky-ink-2)]">
            Everything on your iPhone is free, forever. Pro is for people who send a lot of links and want to know what
            happens to them. Get it in the Snapreel app.
          </p>
        </div>
        <SceneStage slot="scene-pricing" priority sizes="100vw">
          <Art slot="phone-pricing" priority sizes="(min-width: 1024px) 15vw, 40vw" />
        </SceneStage>
      </section>

      <section aria-label="Plans" className="relative z-10 mt-8">
        <Container>
          <PlanCards detailed />
          <p className="mt-5 max-w-4xl text-sm leading-relaxed text-text-2">
            Prices in US dollars. Payment is charged to your Apple Account when you confirm. Subscriptions renew
            automatically unless you cancel at least 24 hours before the end of the current period, and you can manage
            or cancel them in your iPhone&rsquo;s Settings. See the{" "}
            <Link href="/terms" className="mk-link !font-medium">
              terms of use
            </Link>{" "}
            and{" "}
            <Link href="/privacy" className="mk-link !font-medium">
              privacy policy
            </Link>
            .
          </p>
        </Container>
      </section>

      <section aria-labelledby="compare-title" className="mt-20 sm:mt-28">
        <Container>
          <SectionHeading id="compare-title" label="Compare" title="Free and Pro, side by side." />
          <div className="mk-card mt-8 overflow-hidden">
            <table className="w-full table-fixed border-collapse text-left text-[0.9375rem]">
              <caption className="sr-only">What Free and Pro include</caption>
              <colgroup>
                <col />
                <col className="w-[27%] sm:w-[20%]" />
                <col className="w-[27%] sm:w-[20%]" />
              </colgroup>
              <thead>
                <tr>
                  <th scope="col" className="px-4 py-5 font-semibold sm:px-7">
                    <span className="sr-only">Feature</span>
                  </th>
                  <th scope="col" className="mk-display px-2 py-5 text-lg font-bold sm:px-4">
                    Free
                  </th>
                  <th scope="col" className="mk-display px-2 py-5 text-lg font-bold text-red-text sm:px-4">
                    Pro
                  </th>
                </tr>
              </thead>
              {rows.map((g) => (
                <tbody key={g.group}>
                  <tr>
                    <th scope="colgroup" colSpan={3} className="bg-fill/70 px-4 py-2.5 text-xs font-semibold uppercase tracking-[0.1em] text-text-2 sm:px-7">
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
        <Container className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:gap-14">
          <SectionHeading
            id="pricing-faq"
            label="Billing"
            title="Billing, plainly."
            intro="Pro is bought, managed and cancelled through the App Store, like any other iPhone subscription."
          />
          <Faq items={faq} />
        </Container>
      </section>

      <section aria-labelledby="in-app-title" className="mt-20 sm:mt-28">
        <Container>
          <div className="mk-card grid grid-cols-1 items-center gap-8 overflow-hidden p-3 md:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)]">
            <div className="mk-tile mk-tile--rose flex justify-center overflow-hidden px-6 pt-10">
              <div className="-mb-[18%] w-[62%] max-w-[250px]">
                <Art slot="support" sizes="(min-width: 768px) 250px, 62vw" />
              </div>
            </div>
            <div className="px-4 pb-8 md:px-6 md:pb-0">
              <p className="mk-label">In the app</p>
              <h2 id="in-app-title" className="mk-title mt-4 text-[2rem] sm:text-[2.5rem]">
                Get Pro in the Snapreel app.
              </h2>
              <ol className="mt-6 space-y-3 text-[1.0625rem]">
                {["Open Snapreel on your iPhone.", "Go to Settings › Snapreel Pro.", "Pick monthly or yearly and confirm with your Apple Account."].map(
                  (step, i) => (
                    <li key={step} className="flex items-start gap-3">
                      <span className="grid size-7 shrink-0 place-items-center rounded-full bg-red-soft text-sm font-semibold text-red-text">
                        {i + 1}
                      </span>
                      <span className="pt-0.5">{step}</span>
                    </li>
                  ),
                )}
              </ol>
              <p className="mt-5 text-text-2">
                You also see the Pro offer when you reach a Free limit, like your 26th link or a recording over 5 minutes.
                Manage or cancel it later from your Account page.
              </p>
            </div>
          </div>
        </Container>
      </section>
    </>
  );
}
