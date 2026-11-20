"use client";

// Sign in with a 6-digit email code or with Apple (Supabase Auth, cookie session).
import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import { PREVIEW } from "@/lib/client/preview-data";
import { previewSignIn, supabaseBrowser } from "@/lib/client/supabase";
import { AppleIcon, ChevronLeftIcon, MailIcon } from "@/components/player/icons";
import { Spinner, btn } from "@/components/player/ui";

const RESEND_AFTER_S = 30;

function authMessage(err: unknown, fallback: string): string {
  const e = err as { status?: number; code?: string; message?: string } | null;
  const code = e?.code ?? "";
  const msg = e?.message ?? "";
  if (e?.status === 429 || code.includes("rate_limit") || /rate limit/i.test(msg)) {
    return "Too many tries. Wait a minute, then try again.";
  }
  if (code === "otp_expired" || /expired|invalid/i.test(msg)) {
    return "That code didn’t work. It may have expired, so send a new one.";
  }
  if (/network|fetch/i.test(msg)) return "Couldn’t reach Snapreel. Check your connection.";
  return fallback;
}

export function LoginForm({
  next,
  initialError,
  notice = null,
}: {
  next: string;
  initialError: string | null;
  notice?: string | null;
}) {
  const router = useRouter();
  const ids = useId();
  const codeRef = useRef<HTMLInputElement>(null);
  const [step, setStep] = useState<"email" | "code">("email");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState<"apple" | "email" | "code" | null>(null);
  const [error, setError] = useState<string | null>(
    initialError ? "Sign in with Apple didn’t finish. Try again, or use your email." : null,
  );
  const [cooldown, setCooldown] = useState(0);
  const lastTried = useRef("");

  useEffect(() => {
    if (cooldown <= 0) return;
    const id = window.setTimeout(() => setCooldown((c) => c - 1), 1000);
    return () => window.clearTimeout(id);
  }, [cooldown]);

  useEffect(() => {
    if (step === "code") codeRef.current?.focus();
  }, [step]);

  // Already signed in in this browser (for example after the session refreshed): go straight on.
  useEffect(() => {
    const sb = supabaseBrowser();
    if (!sb) return;
    let cancelled = false;
    void sb.auth.getSession().then(({ data }) => {
      if (!cancelled && data.session) {
        router.replace(next);
        router.refresh();
      }
    });
    return () => {
      cancelled = true;
    };
  }, [next, router]);

  function finish() {
    router.replace(next);
    router.refresh();
  }

  async function withApple() {
    setError(null);
    setBusy("apple");
    if (PREVIEW) {
      previewSignIn("pro");
      finish();
      return;
    }
    const sb = supabaseBrowser()!;
    const { error: err } = await sb.auth.signInWithOAuth({
      provider: "apple",
      options: { redirectTo: `${location.origin}/login/callback?next=${encodeURIComponent(next)}` },
    });
    if (err) {
      setBusy(null);
      setError(authMessage(err, "Sign in with Apple isn’t available right now. Use your email instead."));
    }
  }

  async function sendCode(e?: FormEvent) {
    e?.preventDefault();
    const address = email.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) {
      setError("Enter your email address, like name@example.com.");
      return;
    }
    setError(null);
    setBusy("email");
    try {
      if (!PREVIEW) {
        const { error: err } = await supabaseBrowser()!.auth.signInWithOtp({
          email: address,
          options: { shouldCreateUser: true },
        });
        if (err) throw err;
      }
      setCode("");
      lastTried.current = "";
      setStep("code");
      setCooldown(RESEND_AFTER_S);
    } catch (err) {
      setError(authMessage(err, "We couldn’t send a code. Check the address and try again."));
    } finally {
      setBusy(null);
    }
  }

  async function verify(token: string) {
    if (token.length !== 6 || lastTried.current === token) return;
    lastTried.current = token;
    setError(null);
    setBusy("code");
    try {
      if (PREVIEW) {
        previewSignIn(/pro/i.test(email) ? "pro" : "free");
      } else {
        const { error: err } = await supabaseBrowser()!.auth.verifyOtp({ email: email.trim(), token, type: "email" });
        if (err) throw err;
      }
      finish();
    } catch (err) {
      setBusy(null);
      setError(authMessage(err, "That code didn’t work. Check it and try again."));
      codeRef.current?.select();
    }
  }

  return (
    <div className="w-full">
      {PREVIEW && (
        <p className="mb-4 rounded-2xl bg-sr-cream px-4 py-3 text-sm leading-relaxed text-sr-ink">
          <strong>Preview mode.</strong> Supabase isn&rsquo;t set up here, so any 6-digit code signs you in to sample
          data. Put &ldquo;pro&rdquo; in the email to see Pro.
        </p>
      )}

      {notice && step === "email" && (
        <p role="status" className="mb-5 rounded-2xl bg-fill px-4 py-3 text-sm leading-relaxed">
          {notice}
        </p>
      )}

      {step === "email" ? (
        <>
          <h1 className="text-2xl font-semibold tracking-tight">Sign in to Snapreel</h1>
          <p className="mt-2 text-pretty text-[15px] leading-relaxed text-text-2">
            See who watched your links, reply to comments and change link settings.
          </p>

          <button
            type="button"
            onClick={withApple}
            disabled={busy !== null}
            className="mt-6 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-black text-[16px] font-semibold text-white transition-opacity hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sr-red disabled:opacity-60 dark:bg-white dark:text-black motion-reduce:transition-none"
          >
            {busy === "apple" ? <Spinner size={18} /> : <AppleIcon size={20} className="-mt-0.5" />}
            Continue with Apple
          </button>

          <div className="my-5 flex items-center gap-3 text-[13px] text-text-3" aria-hidden="true">
            <span className="h-px flex-1 bg-line" />
            or
            <span className="h-px flex-1 bg-line" />
          </div>

          <form onSubmit={sendCode} noValidate>
            <label htmlFor={`${ids}-email`} className="mb-1.5 block text-sm font-medium">
              Email
            </label>
            <input
              id={`${ids}-email`}
              type="email"
              inputMode="email"
              autoComplete="email"
              autoCapitalize="none"
              spellCheck={false}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="name@example.com"
              aria-invalid={!!error}
              aria-describedby={error ? `${ids}-error` : undefined}
              className="block h-12 w-full rounded-2xl border border-line bg-canvas px-4 text-base placeholder:text-text-3 focus:border-sr-red focus:outline-none focus:ring-2 focus:ring-sr-red/25"
            />
            <button type="submit" disabled={busy !== null} className={btn("primary", "lg", "mt-3 w-full")}>
              {busy === "email" ? <Spinner size={18} /> : <MailIcon size={19} />}
              Email me a code
            </button>
          </form>
        </>
      ) : (
        <>
          <button
            type="button"
            onClick={() => {
              setStep("email");
              setError(null);
            }}
            className={btn("quiet", "sm", "-ml-3 mb-3")}
          >
            <ChevronLeftIcon size={17} />
            Use a different email
          </button>
          <h1 className="text-2xl font-semibold tracking-tight">Check your email</h1>
          <p className="mt-2 text-[15px] leading-relaxed text-text-2">
            We sent a 6-digit code to <span className="font-medium text-text">{email.trim()}</span>. It works for a few minutes.
          </p>

          <form
            onSubmit={(e) => {
              e.preventDefault();
              lastTried.current = "";
              void verify(code);
            }}
            className="mt-6"
            noValidate
          >
            <label htmlFor={`${ids}-code`} className="mb-2 block text-sm font-medium">
              6-digit code
            </label>
            <div className="relative">
              <div className="grid grid-cols-6 gap-2" aria-hidden="true">
                {Array.from({ length: 6 }, (_, i) => {
                  const filled = i < code.length;
                  const current = i === Math.min(code.length, 5);
                  return (
                    <div
                      key={i}
                      className={`flex h-14 items-center justify-center rounded-2xl border bg-canvas text-2xl font-semibold tabular-nums transition-colors motion-reduce:transition-none ${
                        current && busy !== "code" ? "border-sr-red ring-2 ring-sr-red/25" : filled ? "border-text-3" : "border-line"
                      }`}
                    >
                      {code[i] ?? ""}
                    </div>
                  );
                })}
              </div>
              <input
                ref={codeRef}
                id={`${ids}-code`}
                value={code}
                onChange={(e) => {
                  const digits = e.target.value.replace(/\D/g, "").slice(0, 6);
                  setCode(digits);
                  if (digits.length === 6) void verify(digits);
                }}
                onPaste={(e) => {
                  // "123 456" or "Your code is 123456": keep the digits. No maxLength, so nothing is cut first.
                  const digits = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
                  if (!digits) return;
                  e.preventDefault();
                  setCode(digits);
                  if (digits.length === 6) void verify(digits);
                }}
                inputMode="numeric"
                autoComplete="one-time-code"
                aria-invalid={!!error}
                aria-describedby={error ? `${ids}-error` : undefined}
                className="absolute inset-0 h-full w-full bg-transparent text-transparent caret-transparent selection:bg-transparent focus:outline-none"
              />
            </div>
            <button type="submit" disabled={busy !== null || code.length !== 6} className={btn("primary", "lg", "mt-4 w-full")}>
              {busy === "code" ? <Spinner size={18} /> : "Sign in"}
            </button>
          </form>
          <p className="mt-4 text-center text-sm text-text-2">
            No email?{" "}
            {cooldown > 0 ? (
              <span className="tabular-nums">You can send another in {cooldown} s.</span>
            ) : (
              <button
                type="button"
                onClick={() => void sendCode()}
                className="rounded font-semibold text-red-text underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-sr-red"
              >
                Send a new code
              </button>
            )}
          </p>
        </>
      )}

      {error && (
        <p id={`${ids}-error`} role="alert" className="mt-4 rounded-2xl bg-red-soft px-4 py-3 text-sm text-red-text">
          {error}
        </p>
      )}
    </div>
  );
}
