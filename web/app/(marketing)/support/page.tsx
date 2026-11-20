import type { Metadata } from "next";
import Link from "next/link";
import { Art } from "@/components/marketing/art";
import { Icon, type IconName } from "@/components/marketing/marks";
import { PageBanner } from "@/components/marketing/page-banner";
import { Container } from "@/components/marketing/sections";
import { LEGAL_ENTITY } from "@/lib/legal-entity";

export const metadata: Metadata = {
  title: "Support",
  description: "Contact Snapreel support, report a video, or delete your Snapreel account.",
  alternates: { canonical: "/support" },
  openGraph: { url: "/support" },
};

const EMAIL = LEGAL_ENTITY.email;

function Card({ id, icon, title, children }: { id: string; icon: IconName; title: string; children: React.ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="mk-card scroll-mt-24 p-6 sm:p-8">
      <div className="flex items-center gap-3">
        <span className="mk-icon">
          <Icon name={icon} />
        </span>
        <h2 id={`${id}-title`} className="mk-display text-2xl font-bold">
          {title}
        </h2>
      </div>
      <div className="mk-prose mt-4 !text-base">{children}</div>
    </section>
  );
}

export default function SupportPage() {
  const address = [...LEGAL_ENTITY.addressLines, LEGAL_ENTITY.country].filter(Boolean);
  return (
    <>
      <PageBanner
        variant="hero"
        titleId="support-title"
        label="Support"
        title="Talk to a person."
        intro="Questions, problems or ideas: write to us and we'll get back to you. You can also send a message from the app, under Settings › Contact support."
      >
        <a href={`mailto:${EMAIL}`} className="mk-button mk-button--white">
          <Icon name="mail" size={18} />
          {EMAIL}
        </a>
      </PageBanner>

      <Container className="relative z-10 mt-8">
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_minmax(0,0.8fr)]">
          <Card id="contact" icon="mail" title="Email support">
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

          <Card id="report" icon="flag" title="Report a video">
            <p>
              If a shared Snapreel video breaks the law or our <Link href="/terms">terms</Link>, tell us. On the video&rsquo;s
              page, use <strong>Report this video</strong> under the player, or email{" "}
              <a href={`mailto:${EMAIL}?subject=Report%20a%20video`}>{EMAIL}</a> with the link and what&rsquo;s wrong.
            </p>
            <p>We look at every report and remove videos that break the rules. The person who shared it isn&rsquo;t told who reported it.</p>
          </Card>

          <figure className="mk-tile mk-tile--peach flex flex-col items-center gap-6 overflow-hidden px-6 pb-8 pt-8 md:col-span-2 lg:col-span-1 lg:row-span-2 lg:justify-center">
            <div className="w-[62%] max-w-[250px] lg:w-[88%]">
              <Art slot="support" sizes="(min-width: 1024px) 250px, 62vw" />
            </div>
            <figcaption className="max-w-[18rem] text-center text-[0.9375rem] leading-relaxed text-text-2">
              Your Account page in the app: manage Snapreel Pro, sign out or delete your account.
            </figcaption>
          </figure>

          <Card id="delete" icon="stop" title="Delete your account">
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

          <Card id="on-device" icon="lock" title="Delete what’s on your iPhone">
            <p>
              Recordings you haven&rsquo;t shared never leave your iPhone. To remove them, delete a recording in the app, use{" "}
              <strong>Settings › Storage › Delete all my data</strong>, or delete Snapreel from your iPhone.
            </p>
            <p>
              Read more in the <Link href="/privacy">privacy policy</Link>.
            </p>
          </Card>
        </div>

        <section aria-labelledby="who-title" className="mk-tile mk-tile--blue mt-4 flex flex-col gap-4 p-6 sm:flex-row sm:items-center sm:justify-between sm:p-8">
          <div>
            <h2 id="who-title" className="mk-display text-xl font-bold">
              Who makes Snapreel
            </h2>
            <p className="mt-1 text-text-2">
              Snapreel is made by {LEGAL_ENTITY.name}
              {address.length ? `, ${address.join(", ")}` : ""}.
            </p>
          </div>
          <a href={`mailto:${EMAIL}`} className="mk-link shrink-0">
            {EMAIL}
          </a>
        </section>
      </Container>
    </>
  );
}
