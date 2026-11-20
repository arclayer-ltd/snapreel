import type { Metadata } from "next";
import Link from "next/link";
import { Art } from "@/components/marketing/art";
import { MotionStrokes, Sparkle } from "@/components/marketing/marks";
import { Container } from "@/components/marketing/sections";

export const metadata: Metadata = {
  title: "Support",
  description: "Contact Snapreel support, report a video, or delete your Snapreel account.",
  alternates: { canonical: "/support" },
  openGraph: { url: "/support" },
};

const EMAIL = "support@snapreel.video";

function Card({ id, title, children }: { id: string; title: string; children: React.ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-24 rounded-[24px] bg-surface p-6 ring-1 ring-line sm:p-8">
      <h2 id={`${id}-title`} className="mk-display text-2xl font-semibold">
        {title}
      </h2>
      <div className="mk-prose mt-4 !text-base">{children}</div>
    </section>
  );
}

export default function SupportPage() {
  return (
    <>
      <section aria-labelledby="support-title" className="pt-3 sm:pt-5">
        <Container>
          <div className="mk-field grid grid-cols-1 items-end [--pool-x:50%] [--pool-y:90%] md:grid-cols-[minmax(0,1.3fr)_minmax(0,0.7fr)] md:[--pool-x:80%] md:[--pool-y:60%]">
            <div className="relative z-10 self-center px-6 pb-10 pt-10 sm:px-12 md:py-16">
              <p className="mk-pill w-fit">Support</p>
              <h1 id="support-title" className="mk-headline mt-5 text-[2.75rem] sm:text-[4rem]">
                Talk to <b>a person.</b>
              </h1>
              <p className="mt-4 max-w-lg text-lg text-white">
                Questions, problems or ideas: write to us and we&rsquo;ll get back to you. You can also send a message
                from the app, under Settings › Contact support.
              </p>
              <a href={`mailto:${EMAIL}`} className="mk-button mk-button--light mt-7">
                {EMAIL}
              </a>
            </div>
            <div className="relative mx-auto hidden w-[62%] max-w-[260px] pt-10 md:block">
              <Sparkle size={28} top="4%" right="0%" delay={0.2} />
              <MotionStrokes size={50} top="-2%" left="-10%" rotate={-30} />
              <Art slot="support" sizes="260px" />
            </div>
          </div>
        </Container>
      </section>

      <Container className="mt-6">
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Card id="contact" title="Email support">
            <p>
              Write to <a href={`mailto:${EMAIL}`}>{EMAIL}</a>. It helps to tell us:
            </p>
            <ul>
              <li>what you were doing and what happened;</li>
              <li>your iPhone model and iOS version;</li>
              <li>the link, if it&rsquo;s about a shared video.</li>
            </ul>
            <p>
              Many answers are already in the <Link href="/help">help centre</Link>.
            </p>
          </Card>

          <Card id="report" title="Report a video">
            <p>
              If a shared Snapreel video breaks the law or our <Link href="/terms">terms</Link>, tell us. On the video&rsquo;s
              page, use <strong>Report this video</strong> under the player, or email{" "}
              <a href={`mailto:${EMAIL}?subject=Report%20a%20video`}>{EMAIL}</a> with the link and what&rsquo;s wrong.
            </p>
            <p>We look at every report and remove videos that break the rules. The person who shared it isn&rsquo;t told who reported it.</p>
          </Card>

          <Card id="delete" title="Delete your account">
            <ol>
              <li>Open Snapreel on your iPhone.</li>
              <li>
                Go to <strong>Settings › Account › Delete account</strong> and confirm.
              </li>
            </ol>
            <p>
              This deletes every video you&rsquo;ve shared, with its comments, reactions and views, your push tokens and the
              account itself, and revokes Snapreel&rsquo;s access to your Sign in with Apple ID. It can&rsquo;t be undone.
            </p>
            <p>
              Deleting your account doesn&rsquo;t cancel a Pro subscription, because Apple handles billing. To cancel, open{" "}
              <strong>Settings</strong> on your iPhone, tap your name, then <strong>Subscriptions</strong>.
            </p>
            <p>
              Can&rsquo;t use the app? Email <a href={`mailto:${EMAIL}?subject=Delete%20my%20account`}>{EMAIL}</a> from the
              address on your account and we&rsquo;ll delete it for you.
            </p>
          </Card>

          <Card id="on-device" title="Delete what&rsquo;s on your iPhone">
            <p>
              Recordings you haven&rsquo;t shared never leave your iPhone. To remove them, delete a recording in the app, use{" "}
              <strong>Settings › Storage › Delete all my data</strong>, or delete Snapreel from your iPhone.
            </p>
            <p>
              Read more in the <Link href="/privacy">privacy policy</Link>.
            </p>
          </Card>
        </div>
      </Container>
    </>
  );
}
