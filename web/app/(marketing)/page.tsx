import type { Metadata } from "next";
import Link from "next/link";
import { AppStoreBadge } from "@/components/marketing/app-store-badge";
import { SceneStage, Spot, sceneVars, type SceneSlot } from "@/components/marketing/art";
import { IPhone, PeekPhone } from "@/components/marketing/iphone";
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

const ways = [
  {
    screen: "rec-screen" as const,
    icon: "screen" as IconName,
    tone: "mk-tile--blue",
    title: "Screen",
    text: "Show anything on your iPhone, with your voice over it. Snapreel keeps recording while you use other apps.",
  },
  {
    screen: "rec-camera" as const,
    icon: "camera" as IconName,
    tone: "mk-tile--peach",
    title: "Camera",
    text: "Talk to the front or back camera, with your notes on screen so you never lose your place.",
  },
  {
    screen: "rec-voice" as const,
    icon: "mic" as IconName,
    tone: "mk-tile--mint",
    title: "Voice",
    text: "Just your voice, with a live waveform. Lock your iPhone and it keeps going.",
  },
];

/* The floating cards around the phone in the features scene. */
const linkFeatures: { icon: IconName; title: string; text: string; pro?: boolean }[] = [
  { icon: "link", title: "Ready the moment you stop", text: "Tap Copy link and paste it anywhere. The video uploads while people open it." },
  { icon: "browser", title: "Plays in any browser", text: "On a phone, a tablet or a laptop. Previews show in Messages, Slack and WhatsApp." },
  { icon: "chat", title: "Comments at the second", text: "Viewers comment or react at the exact moment they mean. You get an alert." },
  { icon: "chart", title: "See who watched", text: "Views and unique viewers on every link. With Pro: who, how far, and where." },
];

const privateTiles: { icon: IconName; tone: string; title: string; text: string }[] = [
  {
    icon: "person",
    tone: "mk-tile--blue",
    title: "No account to record",
    text: "Open the app and press record. You sign in only when you make your first link.",
  },
  {
    icon: "text",
    tone: "mk-tile--mint",
    title: "Transcripts made on your iPhone",
    text: "Read a recording, search it, and jump to the moment you need.",
  },
  {
    icon: "stop",
    tone: "mk-tile--butter",
    title: "Stop sharing deletes the copy",
    text: "Turn a link off and the uploaded video is deleted. The recording stays on your iPhone.",
  },
  {
    icon: "photo",
    tone: "mk-tile--peach",
    title: "Save to Photos or Files",
    text: "It's your video. Keep a copy in Photos, or send the file with any app.",
  },
  {
    icon: "lock",
    tone: "mk-tile--rose",
    title: "Free on your iPhone, forever",
    text: "No trial and no catch. Pro only changes what your share links can do.",
  },
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
          "--pw": 0.2,
          "--pw-max": "560px",
          "--tuck": "84px",
          "--pw-m": "52%",
          "--pb-m": "2.5%",
        })}
      >
        <div className="mk-scene-content mx-auto max-w-[1240px] px-[var(--mk-gutter)] pt-28 text-center sm:pt-32 lg:pt-[118px]">
          <div className="mk-hero-copy relative mx-auto max-w-[920px] lg:max-w-none">
            <h1 id="hero-title" className="mk-title mk-hero-title">
              Record it on your iPhone. They watch it anywhere.
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
        <SceneStage slot="scene-hero" priority sizes="(min-width: 1024px) max(100vw, 1480px), 100vw">
          <IPhone screen="player-ready" priority sizes="(min-width: 1024px) max(312px, 20vw), 52vw" />
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
      <section id="record" aria-labelledby="record-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <SectionHeading
            id="record-title"
            label="Record"
            title="Three ways to record. One red button."
            intro="Pick Screen, Camera or Voice, tap record, and Snapreel counts you in. When you stop, you can watch it back, give it a title and send it."
          />
          <ul className="mt-10 grid grid-cols-1 gap-4 md:grid-cols-3">
            {ways.map((w) => (
              <li key={w.screen} className={`mk-tile ${w.tone} flex flex-col overflow-hidden`}>
                <div className="px-6 pt-6 sm:px-7 sm:pt-7">
                  <span className="mk-icon mk-icon--on-tile">
                    <Icon name={w.icon} />
                  </span>
                  <h3 className="mk-display mt-4 text-2xl font-bold">{w.title}</h3>
                  <p className="mt-1.5 leading-relaxed text-text-2">{w.text}</p>
                </div>
                <PeekPhone
                  screen={w.screen}
                  crop={0.06}
                  sizes="(min-width: 768px) 250px, 66vw"
                  className="mx-auto mt-auto w-[68%] max-w-[250px] pt-8"
                />
              </li>
            ))}
          </ul>
        </Container>
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
            <IPhone screen="player-comments" ground sizes="(min-width: 1024px) 320px, 54vw" />
          </SceneStage>
          {/* Wide screens: the cards sit around the phone (320 px wide at most, centred), overlapping its
              edges. --pe is the phone's half width. */}
          <ul className="mk-share-comp grid grid-cols-1 gap-3 bg-canvas px-[var(--mk-gutter)] pt-6 sm:grid-cols-2 lg:block lg:bg-transparent lg:p-0 lg:[--pe:min(10.75cqw,160px)]">
            {linkFeatures.map((f, i) => (
              <li
                key={f.title}
                className={`mk-card mk-card--s mk-card--float mk-share-card flex items-start gap-3.5 p-4 sm:p-5 ${
                  [
                    "lg:right-[calc(50%+var(--pe)-48px)] lg:top-[16%]",
                    "lg:right-[calc(50%+var(--pe)-28px)] lg:top-[45%]",
                    "lg:left-[calc(50%+var(--pe)-40px)] lg:top-[24%]",
                    "lg:left-[calc(50%+var(--pe)-60px)] lg:top-[53%]",
                  ][i]
                }`}
              >
                <span className="mk-icon">
                  <Icon name={f.icon} />
                </span>
                <span className="min-w-0">
                  <span className="block font-semibold leading-snug">{f.title}</span>
                  <span className="mt-1 block text-sm leading-snug text-text-2">{f.text}</span>
                </span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* ------------------------------------------------------------------ Private by default */}
      <section id="private" aria-labelledby="private-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container className="grid grid-cols-1 gap-10 lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)] lg:gap-14">
          <div className="lg:sticky lg:top-28 lg:self-start">
            <SectionHeading
              id="private-title"
              label="Private by default"
              title="Your phone. Your files."
              intro="Everything you record stays on your iPhone. Nothing is uploaded until you tap Copy link, and Stop sharing deletes the uploaded copy."
            />
            <Link href="/privacy" className="mk-button mk-button--quiet mt-7">
              Read the privacy policy
              <ArrowRight size={18} />
            </Link>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-4">
              <div className="mk-tile mk-tile--lilac overflow-hidden">
                <div className="px-6 pt-6">
                  <span className="mk-icon mk-icon--on-tile">
                    <Icon name="folder" />
                  </span>
                  <h3 className="mt-4 text-lg font-semibold leading-snug">Library, folders and tags</h3>
                  <p className="mt-1 text-[0.9375rem] leading-relaxed text-text-2">Find any recording with folders, tags and search.</p>
                </div>
                <PeekPhone screen="library" crop={0.36} sizes="(min-width: 640px) 240px, 72vw" className="mx-auto mt-7 w-[74%] max-w-[240px]" />
              </div>
              {privateTiles.slice(0, 1).map((t) => (
                <PrivateTile key={t.title} {...t} />
              ))}
            </div>
            <div className="flex flex-col gap-4">
              {privateTiles.slice(1).map((t) => (
                <PrivateTile key={t.title} {...t} />
              ))}
            </div>
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
                      <Spot slot={g.spot} sizes="140px" className="mk-squircle w-[32%] max-w-[150px] shrink-0 rounded-[calc(var(--mk-r-xl)-12px)]" />
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

function PrivateTile({ icon, tone, title, text }: { icon: IconName; tone: string; title: string; text: string }) {
  return (
    <div className={`mk-tile ${tone} p-6`}>
      <span className="mk-icon mk-icon--on-tile">
        <Icon name={icon} />
      </span>
      <h3 className="mt-4 text-lg font-semibold leading-snug">{title}</h3>
      <p className="mt-1 text-[0.9375rem] leading-relaxed text-text-2">{text}</p>
    </div>
  );
}
