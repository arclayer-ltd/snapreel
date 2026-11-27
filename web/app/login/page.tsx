import type { Metadata } from "next";
import Image from "next/image";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import { getSessionUser } from "@/app/app/_lib/session";
import { LoginForm } from "@/components/dashboard/LoginForm";
import sending from "@/components/dashboard/art/sending.webp";
import { SnapreelWordmark } from "@/components/player/watch/WatchChrome";
import { SITE_URL, safeNext } from "@/lib/client/links";

export const metadata: Metadata = {
  title: "Sign in",
  description: "Sign in to see who watched your Snapreel links, reply to comments and change link settings.",
  robots: { index: false, follow: true },
};

export default function LoginPage({ searchParams }: PageProps<"/login">) {
  return (
    <div className="sr-safe-x flex min-h-svh flex-col lg:flex-row">
      <aside className="relative hidden overflow-hidden bg-[radial-gradient(circle_at_30%_20%,#fe6262_0%,#d32434_42%,#5e0b16_100%)] lg:flex lg:w-[46%] lg:flex-col lg:justify-between lg:p-12">
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.12]"
          style={{
            backgroundImage:
              "linear-gradient(rgb(255 255 255 / 0.5) 1px, transparent 1px), linear-gradient(90deg, rgb(255 255 255 / 0.5) 1px, transparent 1px)",
            backgroundSize: "44px 44px",
          }}
          aria-hidden="true"
        />
        <a href={SITE_URL} className="relative w-fit rounded-lg text-white focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white [&_span]:text-white">
          <SnapreelWordmark size={30} />
        </a>
        <div className="relative mx-auto w-full max-w-md">
          <div className="overflow-hidden rounded-[2rem] shadow-[0_30px_80px_rgb(46_4_10/0.45)] ring-1 ring-white/15">
            <Image src={sending} alt="" priority sizes="448px" className="h-auto w-full" />
          </div>
        </div>
        <p className="relative max-w-sm text-[22px] font-semibold leading-snug tracking-tight text-white">
          Your links, who watched them, and what they said. <span className="text-sr-cream">All in one place.</span>
        </p>
      </aside>

      <main className="flex flex-1 flex-col px-5 pb-[calc(1.5rem+env(safe-area-inset-bottom))] pt-5 sm:px-8 sm:py-8">
        <a href={SITE_URL} className="flex min-h-11 w-fit items-center rounded-lg focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-sr-red lg:hidden">
          <SnapreelWordmark />
        </a>
        <div className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-start pb-8 pt-8 sm:pt-[12vh]">
          <Suspense fallback={<FormSkeleton />}>
            <Gate searchParams={searchParams} />
          </Suspense>
        </div>
        <p className="mx-auto max-w-sm text-center text-[13px] leading-relaxed text-text-2">
          Signing in for the first time creates your account. By carrying on you agree to the{" "}
          <a href={`${SITE_URL}/terms`} className="-my-3 inline-block py-3 underline underline-offset-2 hover:text-text">
            Terms
          </a>{" "}
          and{" "}
          <a href={`${SITE_URL}/privacy`} className="-my-3 inline-block py-3 underline underline-offset-2 hover:text-text">
            Privacy Policy
          </a>
          .
        </p>
      </main>
    </div>
  );
}

async function Gate({ searchParams }: { searchParams: PageProps<"/login">["searchParams"] }) {
  const params = await searchParams;
  const nextParam = Array.isArray(params.next) ? params.next[0] : params.next;
  const next = safeNext(nextParam);
  if (await getSessionUser()) redirect(next);
  const error = Array.isArray(params.error) ? params.error[0] : params.error;
  const notice = params.deleted ? "Your account and links are deleted. Thanks for using Snapreel." : null;
  return <LoginForm next={next} initialError={error ?? null} notice={notice} />;
}

function FormSkeleton() {
  return (
    <div aria-busy="true" className="space-y-3">
      <div className="h-8 w-3/4 rounded-lg bg-fill motion-safe:animate-pulse" />
      <div className="h-4 w-full rounded bg-fill motion-safe:animate-pulse" />
      <div className="mt-6 h-12 w-full rounded-full bg-fill motion-safe:animate-pulse" />
      <div className="h-12 w-full rounded-2xl bg-fill motion-safe:animate-pulse" />
    </div>
  );
}
