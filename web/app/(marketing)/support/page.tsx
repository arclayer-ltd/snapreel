import type { Metadata } from "next";
import Link from "next/link";
import { Spot } from "@/components/marketing/art";
import { IPhone } from "@/components/marketing/iphone";
import { AppIcon, Icon, type IconName } from "@/components/marketing/marks";
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

/** A flat pastel tile: an icon, a title and its text. */
function HelpTile({
  id,
  icon,
  tone,
  title,
  className = "",
  children,
}: {
  id: string;
  icon: IconName;
  tone: string;
  title: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className={`mk-tile mk-help-tile ${tone} ${className}`}>
      <span className="mk-icon mk-icon--on-tile">
        <Icon name={icon} size={24} />
      </span>
      <h2 id={`${id}-title`} className="mk-display">
        {title}
      </h2>
      <div className="mk-prose">{children}</div>
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

      <Container className="relative z-10 mt-14 sm:mt-20">
        <div className="grid grid-cols-1 gap-5 sm:gap-7 lg:grid-cols-2">
          <HelpTile id="contact" icon="mail" tone="mk-tile--blue" title="Email support">
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
          </HelpTile>

          <HelpTile id="report" icon="flag" tone="mk-tile--butter" title="Report a video">
            <p>
              If a shared Snapreel video breaks the law or our <Link href="/terms">terms</Link>, tell us. On the video&rsquo;s
              page, use <strong>Report this video</strong> under the player, or email{" "}
              <a href={`mailto:${EMAIL}?subject=Report%20a%20video`}>{EMAIL}</a> with the link and what&rsquo;s wrong.
            </p>
            <p>We look at every report and remove videos that break the rules. The person who shared it isn&rsquo;t told who reported it.</p>
          </HelpTile>

          {/* Delete your account, beside the page in the app where it is done. */}
          <div className="mk-tile mk-tile--peach grid grid-cols-1 overflow-hidden items-center lg:col-span-2 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
            <HelpTile id="delete" icon="stop" tone="!shadow-none" title="Delete your account">
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
            </HelpTile>
            <figure className="flex flex-col items-center px-7 pb-9 sm:px-11 lg:px-8 lg:py-11">
              <div className="w-[68%] max-w-[270px]">
                <IPhone screen="account" sizes="270px" />
              </div>
              <figcaption className="mt-6 max-w-[19rem] text-center text-[0.9375rem] leading-relaxed text-text-2">
                Your Account page in the app: manage Snapreel Pro, sign out or delete your account.
              </figcaption>
            </figure>
          </div>

          <section
            id="on-device"
            aria-labelledby="on-device-title"
            className="mk-tile mk-help-tile mk-tile--mint grid grid-cols-1 gap-x-12 lg:col-span-2 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:items-center"
          >
            <div>
              <span className="mk-icon mk-icon--on-tile">
                <Icon name="lock" size={24} />
              </span>
              <h2 id="on-device-title" className="mk-display text-balance">
                Delete what&rsquo;s on your iPhone
              </h2>
            </div>
            <div className="mk-prose">
              <p>
                Recordings you haven&rsquo;t shared never leave your iPhone. To remove them, delete a recording in the app, use{" "}
                <strong>Settings › Storage › Delete all my data</strong>, or delete Snapreel from your iPhone.
              </p>
              <p>
                Read more in the <Link href="/privacy">privacy policy</Link>.
              </p>
            </div>
          </section>

          <section
            aria-labelledby="who-title"
            className="mk-panel mk-who grid grid-cols-1 gap-3 overflow-hidden p-3 lg:col-span-2 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]"
          >
            <div className="flex flex-col items-start justify-center p-5 sm:p-9">
              <AppIcon size={60} className="mk-appicon--on-dark" />
              <h2 id="who-title" className="mk-display mt-6 text-[1.75rem] font-bold leading-tight sm:text-[2.25rem]">
                Who makes Snapreel
              </h2>
              <p className="mt-3 text-lg leading-relaxed text-white/75">
                Snapreel is made by {LEGAL_ENTITY.name}
                {address.length ? `, ${address.join(", ")}` : ""}.
              </p>
              <a href={`mailto:${EMAIL}`} className="mk-button mk-button--white mt-7">
                <Icon name="mail" size={18} />
                {EMAIL}
              </a>
            </div>
            <Spot
              slot="spot-share"
              sizes="(min-width: 1024px) 480px, 100vw"
              className="mk-squircle min-h-[220px] rounded-[calc(var(--mk-r-xl)-12px)] sm:min-h-[300px]"
            />
          </section>
        </div>
      </Container>
    </>
  );
}
