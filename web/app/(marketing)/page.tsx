import type { Metadata } from "next";
import Link from "next/link";
import { AppStoreBadge } from "@/components/marketing/app-store-badge";
import { Art } from "@/components/marketing/art";
import { ArrowRight, Check, Loop, MotionStrokes, Sparkle } from "@/components/marketing/marks";
import {
  Container,
  DownloadCta,
  Faq,
  PRICE_MONTHLY,
  PRICE_YEARLY,
  SectionHeading,
  type FaqItem,
} from "@/components/marketing/sections";

export const metadata: Metadata = {
  title: { absolute: "Snapreel: record your iPhone screen, camera or voice and send a link" },
  alternates: { canonical: "/" },
};

const ways = [
  {
    slot: "record-screen" as const,
    title: "Screen",
    text: "Show anything on your iPhone, with your voice over it. Snapreel keeps recording while you use other apps.",
  },
  {
    slot: "record-camera" as const,
    title: "Camera",
    text: "Talk to the front or back camera, with your notes on screen so you never lose your place.",
  },
  {
    slot: "record-voice" as const,
    title: "Voice",
    text: "Just your voice, with a live waveform. Lock your iPhone and it keeps going.",
  },
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

export default function Home() {
  return (
    <>
      {/* ------------------------------------------------------------------ Hero */}
      <section aria-labelledby="hero-title" className="pt-3 sm:pt-5">
        <Container>
          <div className="mk-field grid grid-cols-1 overflow-hidden [--pool-size:50%] [--pool-x:50%] [--pool-y:95%] lg:min-h-[640px] lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] lg:[--pool-size:52%] lg:[--pool-x:74%] lg:[--pool-y:54%]">
            <div className="relative z-10 flex flex-col justify-center px-6 pb-4 pt-10 sm:px-12 sm:pt-14 lg:py-16 lg:pl-16 lg:pr-4">
              <p className="mk-pill w-fit">
                <span className="size-2 rounded-full bg-sr-cream" aria-hidden="true" />
                Screen, camera and voice recorder for iPhone
              </p>
              <h1 id="hero-title" className="mk-headline mt-6 text-[2.75rem] sm:text-[4rem] xl:text-[4.75rem]">
                Record it on your iPhone. <b>They watch it anywhere.</b>
              </h1>
              <p className="mt-5 max-w-xl text-lg leading-relaxed text-white sm:text-xl">
                Snapreel records your screen, camera or voice. Stop, tap Copy link, and anyone can watch in their
                browser, with no app or account on their side.
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-3">
                <AppStoreBadge />
                <Link href="/pricing" className="mk-button mk-button--ghost">
                  See what&rsquo;s free
                  <ArrowRight size={18} />
                </Link>
              </div>
              <p className="mk-pill mt-5 w-fit !font-medium">Free on your iPhone, forever. In TestFlight now.</p>
            </div>

            <div className="relative mx-auto w-full max-w-[560px] self-end lg:-ml-10 lg:max-w-none">
              <Sparkle size={40} top="9%" right="10%" delay={0} />
              <Sparkle size={20} top="27%" right="4%" delay={1.2} />
              <Sparkle size={16} top="5%" left="40%" delay={2.1} />
              <Sparkle size={26} top="62%" left="3%" delay={0.7} />
              <MotionStrokes size={64} top="4%" right="22%" rotate={8} />
              <MotionStrokes size={44} top="44%" left="1%" rotate={-110} count={2} />
              <Art slot="hero" priority className="relative" sizes="(min-width: 1280px) 640px, (min-width: 1024px) 50vw, (min-width: 640px) 560px, calc(100vw - 32px)" />
            </div>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Three ways */}
      <section id="record" aria-labelledby="record-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <div className="mk-field grid grid-cols-1 items-end [--pool-x:50%] [--pool-y:80%] md:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)] md:[--pool-x:76%] md:[--pool-y:50%]">
            <div className="relative z-10 self-center px-6 pt-10 sm:px-12 md:py-14">
              <h2 id="record-title" className="mk-headline text-[2.25rem] sm:text-[3.25rem]">
                Three ways to record. <b>One red button.</b>
              </h2>
              <p className="mt-4 max-w-md text-lg leading-relaxed text-white">
                Pick Screen, Camera or Voice, tap record, and Snapreel counts you in. When you stop, you can watch it
                back, give it a title and send it.
              </p>
            </div>
            <div className="relative mx-auto w-full max-w-[340px] py-6 md:max-w-[420px] md:py-8">
              <Sparkle size={30} top="8%" right="6%" delay={0.5} />
              <Sparkle size={14} top="30%" left="2%" delay={1.7} />
              <MotionStrokes size={50} top="2%" left="12%" rotate={-20} />
              <div className="mk-float">
                <Art slot="jump" sizes="(min-width: 768px) 420px, 340px" />
              </div>
              <span className="mk-ground" aria-hidden="true" />
            </div>
          </div>

          <ul className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
            {ways.map((w, i) => (
              <li key={w.slot} className="grid grid-cols-[42%_minmax(0,1fr)] items-center gap-4 sm:grid-cols-1 sm:items-start">
                <div className="mk-field flex aspect-[4/5] items-center justify-center px-[12%] py-[8%] [--pool-x:50%] [--pool-y:45%] [--pool-size:70%]">
                  <Sparkle size={16} top="9%" right="12%" delay={i * 0.6} />
                  <div className="w-full max-w-[220px]">
                    <Art slot={w.slot} sizes="(min-width: 640px) 220px, 120px" />
                  </div>
                </div>
                <div className="sm:px-2">
                  <h3 className="mk-display text-2xl font-semibold">{w.title}</h3>
                  <p className="mt-1.5 leading-relaxed text-text-2">{w.text}</p>
                </div>
              </li>
            ))}
          </ul>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Links */}
      <section id="links" aria-labelledby="links-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <SectionHeading
            id="links-title"
            eyebrow="Share links"
            title={
              <>
                Copy link. <b>They watch anywhere.</b>
              </>
            }
            intro="Every recording can become a link. Paste it in a message, an email or a ticket, and people press play in their browser."
          />
          <div className="mt-10 grid grid-cols-1 gap-4 md:grid-cols-2">
            <article className="mk-field flex flex-col [--pool-x:52%] [--pool-y:72%]">
              <div className="relative z-10 px-6 pt-10 text-center sm:px-10">
                <h3 className="mk-headline text-[2rem] sm:text-[2.5rem]">
                  The link is ready <b>the moment you stop.</b>
                </h3>
                <p className="mx-auto mt-3 max-w-sm text-white">
                  Tap Copy link and paste it anywhere. The video uploads in the background while people open it.
                </p>
              </div>
              <div className="relative mx-auto mt-auto w-[88%] max-w-[460px] pt-4">
                <Sparkle size={26} top="12%" left="2%" delay={0.3} />
                <MotionStrokes size={56} top="30%" left="-4%" rotate={-100} />
                <Art slot="run-link" sizes="(min-width: 768px) 460px, 88vw" />
              </div>
            </article>
            <article className="mk-field flex flex-col [--pool-x:58%] [--pool-y:68%]">
              <div className="relative z-10 px-6 pt-10 text-center sm:px-10">
                <h3 className="mk-headline text-[2rem] sm:text-[2.5rem]">
                  They watch <b>in any browser.</b>
                </h3>
                <p className="mx-auto mt-3 max-w-sm text-white">
                  On a laptop, a phone or a tablet. No app, no account. Links show a preview in Messages, Slack and
                  WhatsApp.
                </p>
              </div>
              <div className="relative mx-auto mt-auto w-[92%] max-w-[500px] pt-4">
                <Sparkle size={30} top="8%" right="4%" delay={1.1} />
                <Sparkle size={14} top="30%" right="14%" delay={2.3} />
                <Art slot="watch-laptop" sizes="(min-width: 768px) 500px, 92vw" />
              </div>
            </article>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Insights + comments */}
      <section aria-labelledby="insights-title" className="mt-20 sm:mt-28">
        <Container>
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            <article id="insights" className="scroll-mt-24 rounded-[28px] bg-surface p-3 ring-1 ring-line">
              <div className="mk-field flex justify-center px-6 pb-2 pt-8 [--pool-x:50%] [--pool-y:55%]">
                <Sparkle size={22} top="12%" left="14%" delay={0.4} />
                <Sparkle size={12} top="28%" right="16%" delay={1.9} />
                <Loop width={150} top="62%" left="8%" rotate={-12} opacity={0.75} />
                <div className="w-[62%] max-w-[260px]">
                  <Art slot="insights" sizes="(min-width: 640px) 260px, 60vw" />
                </div>
              </div>
              <div className="mk-on-canvas px-4 pb-5 pt-6 sm:px-6">
                <h2 id="insights-title" className="mk-headline text-[2rem] text-text sm:text-[2.5rem]">
                  See who <b>watched.</b>
                </h2>
                <p className="mt-3 leading-relaxed text-text-2">
                  Every link counts its views and unique viewers, free. With Pro, see who watched, how far they got,
                  where they dropped off and which countries they&rsquo;re in.
                </p>
                <ul className="mt-4 space-y-2 text-[0.9375rem]">
                  <li className="flex gap-2.5">
                    <Check className="mt-0.5 shrink-0 text-red-text" />A view counts after 5 seconds of watching.
                  </li>
                  <li className="flex gap-2.5">
                    <Check className="mt-0.5 shrink-0 text-red-text" />
                    Your own views never count.
                  </li>
                </ul>
              </div>
            </article>

            <article id="comments" className="scroll-mt-24 rounded-[28px] bg-surface p-3 ring-1 ring-line">
              <div className="mk-field flex justify-center px-6 pb-2 pt-8 [--pool-x:50%] [--pool-y:55%]">
                <Sparkle size={24} top="10%" right="14%" delay={0.9} />
                <Sparkle size={12} top="40%" left="12%" delay={2.4} />
                <MotionStrokes size={48} top="8%" left="14%" rotate={-24} />
                <div className="w-[62%] max-w-[260px]">
                  <Art slot="comments" sizes="(min-width: 640px) 260px, 60vw" />
                </div>
              </div>
              <div className="mk-on-canvas px-4 pb-5 pt-6 sm:px-6">
                <h2 className="mk-headline text-[2rem] text-text sm:text-[2.5rem]">
                  Comments and <b>reactions.</b>
                </h2>
                <p className="mt-3 leading-relaxed text-text-2">
                  Viewers can leave a comment or an emoji at the exact second they mean. You get a notification on your
                  iPhone and see every comment next to the video in the app.
                </p>
                <ul className="mt-4 space-y-2 text-[0.9375rem]">
                  <li className="flex gap-2.5">
                    <Check className="mt-0.5 shrink-0 text-red-text" />
                    Delete any comment, and block someone from all your videos.
                  </li>
                  <li className="flex gap-2.5">
                    <Check className="mt-0.5 shrink-0 text-red-text" />
                    Turn comments or reactions off for any link.
                  </li>
                </ul>
              </div>
            </article>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Your files */}
      <section id="private" aria-labelledby="files-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <div className="mk-field mk-field--deep grid grid-cols-1 items-center gap-2 [--pool-x:50%] [--pool-y:82%] md:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)] md:[--pool-x:76%] md:[--pool-y:50%]">
            <div className="relative z-10 px-6 pt-10 sm:px-12 md:py-16">
              <h2 id="files-title" className="mk-headline text-[2.25rem] sm:text-[3.25rem]">
                Your phone. <b>Your files.</b>
              </h2>
              <p className="mt-4 max-w-lg text-lg leading-relaxed text-white">
                Everything you record stays on your iPhone, private by default. Nothing is uploaded until you tap Copy
                link, and Stop sharing deletes the uploaded copy.
              </p>
              <ul className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
                {[
                  "No account to record",
                  "Library, folders and tags",
                  "Transcripts made on your iPhone",
                  "Save to Photos or Files",
                ].map((t) => (
                  <li key={t} className="flex items-center gap-2.5 text-white">
                    <span className="grid grid-cols-1 size-6 shrink-0 place-items-center rounded-full bg-white/15">
                      <Check size={14} className="text-sr-cream" />
                    </span>
                    {t}
                  </li>
                ))}
              </ul>
              <p className="mt-6 text-sm font-semibold text-sr-cream">Local recording is free, forever.</p>
            </div>
            <div className="relative mx-auto w-[64%] max-w-[300px] py-10 md:w-full md:max-w-[320px]">
              <Sparkle size={30} top="6%" right="2%" delay={0.2} />
              <Sparkle size={14} top="50%" left="-6%" delay={1.5} />
              <Art slot="files" sizes="(min-width: 768px) 320px, 64vw" />
            </div>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Pro */}
      <section id="pro" aria-labelledby="pro-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container>
          <div className="mk-field grid grid-cols-1 items-end [--pool-size:50%] [--pool-x:50%] [--pool-y:93%] lg:[--pool-size:58%] lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:[--pool-x:72%] lg:[--pool-y:55%]">
            <div className="relative z-10 self-center px-6 pt-10 sm:px-12 lg:py-16">
              <p className="mk-pill w-fit">Snapreel Pro</p>
              <h2 id="pro-title" className="mk-headline mt-5 text-[2.25rem] sm:text-[3.25rem]">
                Links that look <b>like yours.</b>
              </h2>
              <ul className="mt-6 grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
                {[
                  "Unlimited links, up to 2 hours",
                  "1080p on the web",
                  "Full viewer insights",
                  "Password and expiry",
                  "Downloads on or off",
                  "Your logo, colour and button",
                ].map((t) => (
                  <li key={t} className="flex items-start gap-2.5 text-white">
                    <Check className="mt-0.5 shrink-0 text-sr-cream" />
                    {t}
                  </li>
                ))}
              </ul>
              <p className="mt-7 text-lg text-white">
                <strong className="font-semibold">{PRICE_MONTHLY} a month</strong> or{" "}
                <strong className="font-semibold">{PRICE_YEARLY} a year</strong>, with a 7-day free trial on yearly.
              </p>
              <div className="mt-6 flex flex-wrap items-center gap-3">
                <span className="inline-flex min-h-12 items-center rounded-full bg-white px-5 font-semibold text-sr-ink">
                  Get Pro in the Snapreel app
                </span>
                <Link href="/pricing" className="mk-button mk-button--ghost">
                  Compare plans
                  <ArrowRight size={18} />
                </Link>
              </div>
            </div>
            <div className="relative mx-auto grid w-full max-w-[560px] grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)] items-end px-4 pt-6 sm:px-8">
              <Sparkle size={36} top="6%" left="8%" delay={0} />
              <Sparkle size={18} top="26%" left="40%" delay={1} />
              <Sparkle size={22} top="2%" right="10%" delay={1.8} />
              <MotionStrokes size={58} top="0%" left="26%" rotate={-6} />
              <div className="relative -mr-6">
                <div className="mk-float">
                  <Art slot="celebrate" sizes="(min-width: 1024px) 300px, 52vw" />
                </div>
                <span className="mk-ground" aria-hidden="true" />
              </div>
              <div className="relative mb-10 pb-4">
                <Art slot="pro" sizes="(min-width: 1024px) 240px, 40vw" />
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ Pricing teaser */}
      <section aria-labelledby="pricing-title" className="mt-20 sm:mt-28">
        <Container>
          <div className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <SectionHeading
              id="pricing-title"
              eyebrow="Pricing"
              title={
                <>
                  Free to record. <b>Pro when you share more.</b>
                </>
              }
            />
            <Link href="/pricing" className="mk-button mk-button--quiet w-fit shrink-0">
              See all features
              <ArrowRight size={18} />
            </Link>
          </div>
          <div className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-2">
            <Link href="/pricing" className="group rounded-[24px] bg-surface p-6 ring-1 ring-line transition-shadow hover:shadow-lg sm:p-8">
              <p className="mk-display text-xl font-semibold">Free</p>
              <p className="mt-2 flex items-baseline gap-2">
                <span className="mk-display text-4xl font-semibold tracking-[-0.03em]">$0</span>
                <span className="text-text-2">forever</span>
              </p>
              <p className="mt-3 text-text-2">Unlimited recording on your iPhone, and 25 share links of up to 5 minutes.</p>
            </Link>
            <Link href="/pricing" className="mk-field mk-field--deep group block p-6 sm:p-8 [--pool-x:90%] [--pool-y:0%]">
              <p className="mk-display relative text-xl font-semibold">Pro</p>
              <p className="relative mt-2 flex flex-wrap items-baseline gap-x-2">
                <span className="mk-display text-4xl font-semibold tracking-[-0.03em]">{PRICE_MONTHLY}</span>
                <span>a month, or {PRICE_YEARLY} a year</span>
              </p>
              <p className="relative mt-3 text-white">Unlimited links up to 2 hours, full insights, passwords and your branding.</p>
            </Link>
          </div>
        </Container>
      </section>

      {/* ------------------------------------------------------------------ FAQ */}
      <section id="faq" aria-labelledby="faq-title" className="mt-20 scroll-mt-24 sm:mt-28">
        <Container className="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
          <SectionHeading
            id="faq-title"
            title={
              <>
                Questions, <b>answered.</b>
              </>
            }
            intro={
              <>
                Something else? Look in the{" "}
                <Link href="/help" className="font-medium text-red-text underline underline-offset-4">
                  help centre
                </Link>{" "}
                or write to{" "}
                <a href="mailto:support@snapreel.video" className="font-medium text-red-text underline underline-offset-4">
                  support@snapreel.video
                </a>
                .
              </>
            }
          />
          <Faq items={faq} />
        </Container>
      </section>

      <DownloadCta />
    </>
  );
}
