"use client";

// Sign in with a 6-digit email code or with Apple (Supabase Auth, cookie session).
import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import { PREVIEW } from "@/lib/client/preview-data";
import { previewSignIn, supabaseBrowser } from "@/lib/client/supabase";
import { AppleIcon, ChevronLeftIcon, MailIcon } from "@/components/player/icons";
import { Spinner, btn } from "@/components/player/ui";

const RESEND_AFTER_S = 30;
/** Codes work for 10 minutes (the email says so); after that the page starts again from the email. */
const CODE_LIFE_MS = 10 * 60_000;

// Going to Mail for the code can reload this page: iOS drops background tabs when memory is short, and the app's
// Safari sheet starts over when it's closed. So the address and when the code went out are kept for as long as the
// code works, on this device only, and removed on sign-in. The code itself is never kept.
const PENDING_KEY = "sr_signin";

function readPending(): { email: string; sentAt: number } | null {
  try {
    const p = JSON.parse(localStorage.getItem(PENDING_KEY) ?? "null") as { email?: unknown; sentAt?: unknown } | null;
    if (!p || typeof p.email !== "string" || typeof p.sentAt !== "number") return null;
    const age = Date.now() - p.sentAt;
    return age >= 0 && age < CODE_LIFE_MS ? { email: p.email, sentAt: p.sentAt } : null;
  } catch {
    return null;
  }
}

function savePending(p: { email: string; sentAt: number } | null) {
  try {
    if (p) localStorage.setItem(PENDING_KEY, JSON.stringify(p));
    else localStorage.removeItem(PENDING_KEY);
  } catch {
    // Private mode: a reload starts from the email again.
  }
}

function authMessage(err: unknown, fallback: string): string {
  const e = err as { status?: number; code?: string; message?: string } | null;
  const code = e?.code ?? "";
  const msg = e?.message ?? "";
  if (e?.status === 429 || code.includes("rate_limit") || /rate limit/i.test(msg)) {
    return "Too many tries. Wait a minute, then try again.";
  }
  if (code === "otp_expired" || /expired|invalid/i.test(msg)) {
    return "That code didn’t work. Use the newest email: each new code replaces the one before.";
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
  const [sentAt, setSentAt] = useState(0);
  const [sentFor, setSentFor] = useState("");
  const [now, setNow] = useState(0);
  const [codeFocused, setCodeFocused] = useState(false);
  const [canPaste, setCanPaste] = useState(false);
  const [resent, setResent] = useState(false);
  const lastTried = useRef("");
  const cooldown = sentAt > 0 ? Math.max(0, Math.ceil((sentAt + RESEND_AFTER_S * 1000 - now) / 1000)) : 0;

  // Shown again after being hidden (the router keeps pages it has left): nothing is still "working".
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- resets a spinner left from before the page was hidden
    setBusy(null);
  }, []);

  // Back from Mail to a page that had to reload: straight to the code, not the email again.
  useEffect(() => {
    const pending = readPending();
    /* eslint-disable react-hooks/set-state-in-effect -- localStorage and the clipboard are only known after mount */
    setCanPaste(typeof navigator.clipboard?.readText === "function");
    if (!pending) return;
    setEmail(pending.email);
    setSentAt(pending.sentAt);
    setSentFor(pending.email);
    setNow(Date.now());
    setStep("code");
    /* eslint-enable react-hooks/set-state-in-effect */
  }, []);

  // The resend wait runs on the clock, not on ticks: iOS stops timers while Mail is open.
  const counting = cooldown > 0;
  useEffect(() => {
    if (!counting) return;
    const tick = () => setNow(Date.now());
    const id = window.setInterval(tick, 1000);
    document.addEventListener("visibilitychange", tick);
    return () => {
      window.clearInterval(id);
      document.removeEventListener("visibilitychange", tick);
    };
  }, [counting]);

  useEffect(() => {
    if (step === "code") codeRef.current?.focus({ preventScroll: true });
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
    savePending(null);
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
    if (cooldown > 0 && address.toLowerCase() === sentFor.toLowerCase()) {
      setError(`A code was just sent to that address. You can ask for another in ${cooldown} s.`);
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
      const at = Date.now();
      setResent(step === "code");
      setSentAt(at);
      setSentFor(address);
      setNow(at);
      savePending({ email: address, sentAt: at });
      setStep("code");
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

  function takeCode(text: string) {
    const digits = text.replace(/\D/g, "").slice(0, 6);
    if (!digits) return false;
    setCode(digits);
    if (digits.length === 6) void verify(digits);
    return true;
  }

  // iOS shows its own "Paste" bubble for this, so one tap here and one there.
  async function pasteCode() {
    try {
      const text = await navigator.clipboard.readText();
      // "Your code is 123456" is fine; a long page of other text isn't a code.
      const six = /(?:^|\D)(\d{3}[ -]?\d{3})(?!\d)/.exec(text)?.[1];
      if (!six || !takeCode(six)) setError("There’s no 6-digit code on the clipboard. Copy it from the email first.");
    } catch {
      codeRef.current?.focus();
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
              name="email"
              type="email"
              inputMode="email"
              autoComplete="email"
              autoCapitalize="none"
              autoCorrect="off"
              enterKeyHint="send"
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
              savePending(null);
              // The resend wait stays for that address, so going back can't be used to skip it.
              setCode("");
              setResent(false);
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
            We sent a 6-digit code to <span className="break-words font-medium text-text">{email.trim()}</span>. It works for 10 minutes.
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
              <div className="grid grid-cols-6 gap-1.5 sm:gap-2" aria-hidden="true">
                {Array.from({ length: 6 }, (_, i) => {
                  const filled = i < code.length;
                  const current = i === Math.min(code.length, 5);
                  return (
                    <div
                      key={i}
                      className={`flex h-14 items-center justify-center rounded-2xl border bg-canvas text-2xl font-semibold tabular-nums transition-colors motion-reduce:transition-none ${
                        current && codeFocused && busy !== "code" ? "border-sr-red ring-2 ring-sr-red/25" : filled ? "border-text-3" : "border-line"
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
                name="code"
                onFocus={() => setCodeFocused(true)}
                onBlur={() => setCodeFocused(false)}
                onChange={(e) => {
                  const digits = e.target.value.replace(/\D/g, "").slice(0, 6);
                  setCode(digits);
                  setError(null);
                  if (digits.length === 6) void verify(digits);
                }}
                onPaste={(e) => {
                  // "123 456" or "Your code is 123456": keep the digits. No maxLength, so nothing is cut first.
                  if (takeCode(e.clipboardData.getData("text"))) e.preventDefault();
                }}
                inputMode="numeric"
                autoComplete="one-time-code"
                enterKeyHint="go"
                autoCorrect="off"
                aria-invalid={!!error}
                aria-describedby={error ? `${ids}-error` : undefined}
                className="absolute inset-0 h-full w-full bg-transparent text-transparent caret-transparent selection:bg-transparent focus:outline-none"
              />
            </div>
            <button type="submit" disabled={busy !== null || code.length !== 6} className={btn("primary", "lg", "mt-4 w-full")}>
              {busy === "code" ? <Spinner size={18} /> : "Sign in"}
            </button>
            {canPaste && code.length < 6 && busy !== "code" && (
              <button type="button" onClick={() => void pasteCode()} className={btn("secondary", "lg", "mt-2.5 w-full")}>
                Paste code
              </button>
            )}
          </form>
          <p className="mt-2 min-h-11 text-center text-sm leading-[2.75rem] text-text-2" role="status">
            {resent && cooldown > 0 ? "New code sent. " : "No email? "}
            {cooldown > 0 ? (
              <span className="tabular-nums" aria-hidden="true">
                You can send another in {cooldown} s.
              </span>
            ) : (
              <button
                type="button"
                onClick={() => void sendCode()}
                disabled={busy !== null}
                className="inline-flex min-h-11 items-center rounded font-semibold leading-normal disabled:opacity-60 text-red-text underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-sr-red"
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
