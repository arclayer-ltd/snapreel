import type { Metadata } from "next";
import type { CSSProperties } from "react";
import Link from "next/link";
import { AppStoreBadge } from "@/components/marketing/app-store-badge";
import { SceneStage, Spot, sceneVars, type SceneSlot } from "@/components/marketing/art";
import { GlassPieces } from "@/components/marketing/glass-pieces";
import { IPhone, PeekPhone } from "@/components/marketing/iphone";
import { Reveal } from "@/components/marketing/reveal";
import { ShareCallouts, ShareList } from "@/components/marketing/share-callouts";
import { getArticle } from "@/components/marketing/content";
import { ArrowRight, Check, Icon, type IconName } from "@/components/marketing/marks";
import {
  Container,
  Faq,
  InAppNote,
  PRICE_MONTHLY,
  PRICE_YEARLY,
  SectionHeading,
  type FaqItem,
} from "@/components/marketing/sections";
import { LEGAL_ENTITY } from "@/lib/legal-entity";

export const metadata: Metadata = {
  title: { absolute: "Snapreel: record your iPhone screen, camera or voice and send a link" },
  alternates: { canonical: "/" },
};

/* What the stats bar says. Not user counts or ratings: three things that are simply true. */
const facts = [
  { value: "3", label: "ways to record: screen, camera and voice" },
  { value: "0", label: "apps or accounts needed to watch a link" },
  { value: "25", label: "share links free, before you need Pro" },
];

/* Three ways to record: three whole iPhones standing on the terrace, each playing its recorded flow. */
const ways = [
  { screen: "flow-screen" as const, flow: "screen" as const, icon: "screen" as IconName, title: "Screen", text: "Your screen, with your voice over it." },
  { screen: "flow-camera" as const, flow: "camera" as const, icon: "camera" as IconName, title: "Camera", text: "Front or back, with your notes on screen." },
  { screen: "flow-voice" as const, flow: "voice" as const, icon: "mic" as IconName, title: "Voice", text: "Lock your iPhone and it keeps going." },
];

const privatePoints: { icon: IconName; title: string; text: string }[] = [
  { icon: "lock", title: "On your iPhone", text: "Nothing uploads until you tap Copy link." },
  { icon: "stop", title: "Stop sharing", text: "Deletes the uploaded copy." },
  { icon: "person", title: "No account", text: "Open the app and press record." },
  { icon: "photo", title: "Save anywhere", text: "Photos, Files or any app." },
];

const proList = [
  "Unlimited links, up to 2 hours",
  "1080p on the web",
  "Full viewer insights",
  "Password and expiry",
  "Downloads on or off",
  "Your logo, colour and button",
];

const guides: { id: string; spot: SceneSlot; tag: string }[] = [
  { id: "first-recording", spot: "spot-record", tag: "Getting started" },
  { id: "share-links", spot: "spot-share", tag: "Share links" },
  { id: "privacy", spot: "spot-private", tag: "Privacy" },
  { id: "snapreel-pro", spot: "spot-pro", tag: "Snapreel Pro" },
];

const faq: FaqItem[] = [
  {
    q: "Is Snapreel free?",
    a: "Yes. Recording, your library, folders, tags, transcripts and saving to Photos are free, forever, with no account. Share links are free too: 25 of them, up to 5 minutes each. Snapreel Pro adds unlimited, longer links and the extras.",
  },
  {
    q: "Do the people I send a link to need the app?",
    a: "No. They open the link in any browser, on a phone, tablet or computer. No app, no account and no download.",
  },
  {
    q: "Where are my recordings kept?",
    a: "On your iPhone. A recording is uploaded only when you tap **Copy link**, and **Stop sharing** deletes the uploaded copy. Everything else stays on your phone.",
  },
  {
    q: "How do I get Snapreel Pro?",
    a: `In the app: **Settings › Snapreel Pro**. It's ${PRICE_MONTHLY} a month or ${PRICE_YEARLY} a year, and the yearly plan starts with a 7-day free trial. You pay through your Apple Account and can cancel any time in your iPhone's Settings.`,
  },
  {
    q: "Can I keep a link private?",
    a: "With Pro you can add a password, set the link to expire, and turn downloads off. You can stop sharing any link at any time, on Free or Pro.",
  },
  {
    q: "Which iPhones does it work on?",
    a: "Any iPhone with iOS 16 or later.",
  },
  {
    q: "How do I delete my account?",
    a: "In the app, go to **Settings › Account › Delete account**. It removes every video you've shared, with its comments and views. See [Support](/support#delete) for the details.",
  },
];

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Snapreel",
  operatingSystem: "iOS 16 or later",
  applicationCategory: "MultimediaApplication",
  description:
    "Record your iPhone screen, camera or voice. Tap Copy link and anyone can watch in a browser, no app or account needed.",
  url: "https://snapreel.video/",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  author: { "@type": "Person", name: LEGAL_ENTITY.name, email: LEGAL_ENTITY.email },
};

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        // JSON.stringify of our own constant; "<" is escaped so it can't close the tag.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }}
      />

      {/* ------------------------------------------------------------------ Hero */}
      <section
        aria-labelledby="hero-title"
        className="mk-scene mk-scene--cover mk-scene--top mk-hero"
        style={sceneVars("scene-hero", {
          "--fx": 0.49,
          "--px": 0.49,
          "--pb": 0.03,
          "--pw": 0.19,
          "--pw-max": "560px",
          "--tuck": "84px",
          "--pw-m": "52%",
          "--pb-m": "2.5%",
        })}
      >
        <div className="mk-scene-content mx-auto max-w-[1240px] px-[var(--mk-gutter)] pt-28 text-center sm:pt-32 lg:pt-[118px]">
          <div className="mk-hero-copy relative mx-auto max-w-[920px] lg:max-w-none">
            <h1 id="hero-title" className="mk-title mk-hero-title">
              <span className="mk-hero-line">Record it on your iPhone.</span>{" "}
              <span className="mk-hero-line">They watch it anywhere.</span>
            </h1>
            <p className="mx-auto mt-5 max-w-2xl text-lg leading-relaxed text-[var(--mk-sky-ink-2)] sm:text-xl">
              Snapreel records your screen, camera or voice. Stop, tap Copy link, and anyone can watch in their
              browser, with no app or account on their side.
            </p>
            <div className="mt-7 flex flex-wrap items-center justify-center gap-3">
              <AppStoreBadge />
              <Link href="/pricing" className="mk-button mk-button--white">
                See what&rsquo;s free
                <ArrowRight size={18} />
              </Link>
            </div>
          </div>
        </div>
        <SceneStage slot="scene-hero" priority sizes="(min-width: 1024px) max(100vw, 1680px), 100vw">
          <IPhone screen="flow-share" flow="share" priority sizes="(min-width: 1024px) max(312px, 20vw), 52vw" />
        </SceneStage>
      </section>

      {/* ------------------------------------------------------------------ Stats bar */}
      <div className="relative z-10 -mt-10 px-[var(--mk-gutter)] lg:-mt-16">
        <div className="mk-panel mx-auto grid max-w-[1080px] grid-cols-1 items-center gap-6 px-6 py-7 sm:px-10 sm:py-8 lg:grid-cols-[auto_repeat(3,minmax(0,1fr))] lg:gap-10">
          <p className="mk-display whitespace-nowrap text-[1.3125rem] font-bold leading-tight tracking-[-0.02em] min-[400px]:text-[1.5rem] lg:text-[1.625rem]">
            Free on your iPhone, forever.
          </p>
          <ul className="contents">
            {facts.map((f) => (
              <li key={f.value} className="flex items-center gap-4 border-t border-white/10 pt-5 lg:block lg:border-0 lg:pt-0">
                <span className="mk-display block w-14 shrink-0 text-[2.75rem] font-bold leading-none tracking-[-0.03em] lg:w-auto lg:text-5xl">
                  {f.value}
                </span>
                <span className="block text-[0.9375rem] leading-snug text-white/75 lg:mt-2">{f.label}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>

      {/* ------------------------------------------------------------------ Three ways */}
      <section
        id="record"
        aria-labelledby="record-title"
        className="mk-scene mk-scene--flow mt-20 scroll-mt-24 sm:mt-28"
        style={sceneVars("scene-pricing", {
          "--px": "50%",
          "--pw": "min(47%, 720px)",
          "--pb": "6%",
          "--tuck": "-24px",
          "--tuck-d": "-40px",
          "--px-m": "50%",
          "--pw-m": "92%",
          "--pb-m": "5%",
        })}
      >
        <div className="mk-scene-content px-[var(--mk-gutter)] pt-16 sm:pt-24">
          <SectionHeading
            center
            id="record-title"
            label="Record"
            title="Three ways to record. One red button."
            intro="Pick Screen, Camera or Voice and tap record. Snapreel counts you in, and you can watch it back the moment you stop."
            className="[&_p:last-child]:text-[var(--mk-sky-ink-2)]"
          />
        </div>
        <div className="relative">
          <SceneStage slot="scene-pricing" sizes="100vw">
            <Reveal className="mk-ways-row">
              <ul>
                {ways.map((w, i) => (
                  <li
                    key={w.flow}
                    className={`mk-way ${i === 1 ? "mk-way--main" : ""}`}
                    style={{ "--d": `${i * 140}ms` } as CSSProperties}
                  >
                    <p className="mk-way-tag">
                      <span className="mk-icon">
                        <Icon name={w.icon} size={18} />
                      </span>
                      <span>
                        {w.title}
                        <small>{w.text}</small>
                      </span>
                    </p>
                    <IPhone screen={w.screen} flow={w.flow} ground sizes="(min-width: 1024px) 220px, 30vw" className="w-full" />
                  </li>
                ))}
              </ul>
            </Reveal>
          </SceneStage>
        </div>
      </section>

      {/* ------------------------------------------------------------------ Share links (scene) */}
      <section
        id="features"
        aria-labelledby="features-title"
        className="mk-scene mk-scene--flow mt-20 scroll-mt-24 sm:mt-28"
        style={sceneVars("scene-features", {
          "--px": "50%",
          "--pw": "min(21.5%, 320px)",
          "--pb": "5.5%",
          "--tuck-d": "0px",
          "--tuck": "-150px",
          "--px-m": "50%",
          "--pw-m": "min(54%, 240px)",
          "--pb-m": "6%",
        })}
      >
        <div className="mk-scene-content px-[var(--mk-gutter)] pt-16 sm:pt-24">
          <SectionHeading
            center
            id="features-title"
            label="Share links"
            title="Copy link. They watch anywhere."
            intro="Every recording can become a link. Paste it in a message, an email or a ticket, and people press play in their browser."
            className="[&_p:last-child]:text-[var(--mk-sky-ink-2)]"
          />
        </div>
        <div className="relative">
          <SceneStage slot="scene-features" sizes="100vw">
            <IPhone screen="flow-comments" flow="comments" ground sizes="(min-width: 1024px) 320px, 54vw" />
            <ShareCallouts />
          </SceneStage>
          <ShareList />
        </div>
      </section>

      {/* ------------------------------------------------------------------ Private by default */}
      <section id="private" aria-labelledby="private-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <div className="mk-private grid grid-cols-1 items-center gap-12 px-6 py-12 sm:px-10 sm:py-14 lg:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)] lg:gap-6 lg:py-16 lg:pl-14 lg:pr-8">
            <div>
              <p className="mk-label">Private by default</p>
              <h2 id="private-title" className="mk-title mt-4 text-[2.25rem] text-white sm:text-[3rem]">
                Your phone.
                <br />
                Your files.
              </h2>
              <p className="mt-4 max-w-md text-lg leading-relaxed text-white/75">
                Everything you record stays on your iPhone, until you choose to share it.
              </p>
              <ul className="mt-8 grid grid-cols-1 gap-3 min-[480px]:grid-cols-2">
                {privatePoints.map((t) => (
                  <li key={t.title} className="flex items-start gap-3 rounded-[var(--mk-r-l)] bg-white/[0.06] p-4 ring-1 ring-white/[0.08]">
                    <span className="mk-icon !bg-white/10 !text-white">
                      <Icon name={t.icon} />
                    </span>
                    <span className="min-w-0">
                      <span className="block font-semibold leading-snug">{t.title}</span>
                      <span className="mt-0.5 block text-sm leading-snug text-white/65">{t.text}</span>
                    </span>
                  </li>
                ))}
              </ul>
              <Link href="/privacy" className="mk-button mk-button--white mt-8">
                Read the privacy policy
                <ArrowRight size={18} />
              </Link>
            </div>
            <Reveal className="mk-lifts py-4 lg:py-8">
              <div className="mk-private-stage">
                <GlassPieces />
                <IPhone screen="library" sizes="(min-width: 1024px) 300px, 46vw" />
              </div>
            </Reveal>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Pro */}
      <section id="pro" aria-labelledby="pro-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <div className="mk-card grid grid-cols-1 gap-8 overflow-hidden p-3 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <div className="self-center px-3 pb-2 pt-5 sm:p-8 lg:py-10 lg:pl-10 lg:pr-2">
              <p className="mk-label">Snapreel Pro</p>
              <h2 id="pro-title" className="mk-title mt-4 text-[2.25rem] sm:text-[3rem]">
                Links that look like yours.
              </h2>
              <ul className="mt-6 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
                {proList.map((t) => (
                  <li key={t} className="flex items-start gap-2.5">
                    <Check className="mt-0.5 shrink-0 text-red-text" />
                    {t}
                  </li>
                ))}
              </ul>
              <p className="mt-7 text-lg">
                <strong className="font-semibold">{PRICE_MONTHLY} a month</strong> or{" "}
                <strong className="font-semibold">{PRICE_YEARLY} a year</strong>, with a 7-day free trial on yearly.
              </p>
              <div className="mt-6 flex flex-wrap items-center gap-3">
                <InAppNote className="!bg-sr-ink !text-white dark:!bg-white dark:!text-sr-ink" />
                <Link href="/pricing" className="mk-button mk-button--quiet">
                  Compare plans
                  <ArrowRight size={18} />
                </Link>
              </div>
            </div>
            <div className="mk-tile mk-tile--rose mk-tile--inset relative flex items-end justify-center gap-[5%] overflow-hidden px-4 pt-10 sm:pt-12 lg:min-h-[540px]">
              <PeekPhone screen="insights" crop={0.34} sizes="(min-width: 1024px) 240px, 42vw" className="w-[44%] max-w-[240px]" />
              <PeekPhone screen="paywall" crop={0.2} sizes="(min-width: 1024px) 240px, 42vw" className="w-[44%] max-w-[240px]" />
            </div>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Guides */}
      <section id="guides" aria-labelledby="guides-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <SectionHeading
              id="guides-title"
              label="Help centre"
              title="Guides for your first week."
              intro="Short answers from the help centre: the same ones you find in the app."
            />
            <nav aria-label="Help topics" className="flex flex-wrap gap-2">
              {[
                ["/help#start", "Getting started"],
                ["/help#screen", "Screen recording"],
                ["/help#links", "Share links"],
              ].map(([href, label], i) => (
                <Link
                  key={href}
                  href={href}
                  className={`inline-flex min-h-10 items-center rounded-full px-4 text-sm font-semibold ${
                    i === 0 ? "bg-sr-ink text-white dark:bg-white dark:text-sr-ink" : "bg-surface text-text shadow-[var(--mk-shadow-sm)] hover:bg-fill"
                  }`}
                >
                  {label}
                </Link>
              ))}
            </nav>
          </div>

          <div className="mt-10 grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)]">
            {guides.slice(0, 1).map((g) => {
              const a = getArticle(g.id);
              if (!a) return null;
              return (
                <Link key={g.id} href={`/help/${a.id}`} className="mk-card mk-lift group flex flex-col overflow-hidden">
                  <Spot slot={g.spot} sizes="(min-width: 1024px) 600px, 100vw" className="aspect-[16/9] w-full" />
                  <span className="flex flex-1 flex-col p-6 sm:p-8">
                    <span className="w-fit rounded-full bg-red-soft px-2.5 py-1 text-xs font-semibold text-red-text">{g.tag}</span>
                    <span className="mk-display mt-3 block text-2xl font-bold leading-tight sm:text-[1.75rem]">{a.title}</span>
                    <span className="mt-2 block leading-relaxed text-text-2">{a.summary}</span>
                    <span className="mt-auto inline-flex items-center gap-2 pt-5 text-sm font-semibold text-red-text">
                      Read the guide
                      <ArrowRight size={16} />
                    </span>
                  </span>
                </Link>
              );
            })}
            <ul className="grid grid-cols-1 gap-4">
              {guides.slice(1).map((g) => {
                const a = getArticle(g.id);
                if (!a) return null;
                return (
                  <li key={g.id}>
                    <Link href={`/help/${a.id}`} className="mk-card mk-lift group flex h-full items-stretch gap-4 overflow-hidden p-3 pr-5">
                      <Spot slot={g.spot} sizes="220px" className="mk-squircle w-[32%] max-w-[150px] shrink-0 rounded-[calc(var(--mk-r-xl)-12px)]" />
                      <span className="flex min-w-0 flex-col justify-center py-2">
                        <span className="text-xs font-semibold uppercase tracking-[0.08em] text-red-text">{g.tag}</span>
                        <span className="mk-display mt-1 block text-lg font-bold leading-snug">{a.title}</span>
                        <span className="mt-1 block text-sm leading-snug text-text-2">{a.summary}</span>
                      </span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ FAQ */}
      <section id="faq" aria-labelledby="faq-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:gap-14">
          <SectionHeading
            id="faq-title"
            label="FAQ"
            title="Questions, answered."
            intro={
              <>
                Something else? Look in the{" "}
                <Link href="/help" className="mk-link">
                  help centre
                </Link>{" "}
                or write to{" "}
                <a href={`mailto:${LEGAL_ENTITY.email}`} className="mk-link">
                  {LEGAL_ENTITY.email}
                </a>
                .
              </>
            }
          />
          <Faq items={faq} />
        </Container>
      </section>
    </>
  );
}
