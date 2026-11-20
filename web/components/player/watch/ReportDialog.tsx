"use client";

import { useId, useState, type FormEvent } from "react";
import type { NewReport } from "@/lib/contract";
import { errorMessage, publicApi } from "@/lib/client/api";
import { CheckIcon } from "../icons";
import { Dialog, Spinner, btn } from "../ui";

const REASONS: { value: NewReport["reason"]; label: string; hint: string }[] = [
  { value: "spam", label: "Spam or a scam", hint: "Misleading, phishing or unwanted promotion" },
  { value: "abuse", label: "Harassment or hate", hint: "Bullying, threats or hateful content" },
  { value: "illegal", label: "Illegal content", hint: "Something that breaks the law" },
  { value: "copyright", label: "Copyright", hint: "It uses work that belongs to you or someone else" },
  { value: "other", label: "Something else", hint: "Tell us what's wrong" },
];

export function ReportDialog({ slug, open, onClose }: { slug: string; open: boolean; onClose: () => void }) {
  const ids = useId();
  const [reason, setReason] = useState<NewReport["reason"] | null>(null);
  const [details, setDetails] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  function close() {
    onClose();
    if (sent) {
      setSent(false);
      setReason(null);
      setDetails("");
      setEmail("");
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!reason) {
      setError("Choose what's wrong with this video.");
      return;
    }
    if (reason === "other" && !details.trim()) {
      setError("Tell us a little about the problem.");
      return;
    }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError("That email address doesn't look right.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await publicApi.report(slug, { reason, details: details.trim(), email: email.trim() || null });
      setSent(true);
    } catch (err) {
      setError(errorMessage(err, "Your report didn't send. Try again, or email support@snapreel.video."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onClose={close} title={sent ? "Thanks for telling us" : "Report this video"} wide>
      {sent ? (
        <div className="space-y-4">
          <div className="flex items-start gap-3">
            <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-red-soft text-red-text">
              <CheckIcon size={18} />
            </span>
            <p className="text-[15px] leading-relaxed text-text-2">
              We&rsquo;ve got your report and will look at this video. If it breaks our rules, we&rsquo;ll take it down.
              {email.trim() ? " We'll email you when we've looked at it." : ""}
            </p>
          </div>
          <div className="flex justify-end">
            <button type="button" className={btn("secondary")} onClick={close}>
              Done
            </button>
          </div>
        </div>
      ) : (
        <form onSubmit={submit} className="space-y-4" noValidate>
          <fieldset>
            <legend className="mb-2 text-[15px] text-text-2">What&rsquo;s wrong with it?</legend>
            <div className="space-y-2">
              {REASONS.map((r) => (
                <label
                  key={r.value}
                  className={`flex cursor-pointer items-start gap-3 rounded-2xl border px-3.5 py-3 transition-colors motion-reduce:transition-none ${
                    reason === r.value ? "border-sr-red bg-red-soft/60" : "border-line hover:bg-fill"
                  }`}
                >
                  <input
                    type="radio"
                    name={`${ids}-reason`}
                    value={r.value}
                    checked={reason === r.value}
                    onChange={() => setReason(r.value)}
                    className="mt-1 h-4 w-4 accent-[#d32434]"
                  />
                  <span>
                    <span className="block font-medium">{r.label}</span>
                    <span className="block text-sm text-text-2">{r.hint}</span>
                  </span>
                </label>
              ))}
            </div>
          </fieldset>
          <div>
            <label htmlFor={`${ids}-details`} className="mb-1 block text-sm font-medium">
              Details {reason !== "other" && <span className="font-normal text-text-3">(optional)</span>}
            </label>
            <textarea
              id={`${ids}-details`}
              value={details}
              onChange={(e) => setDetails(e.target.value)}
              rows={3}
              maxLength={2000}
              className="block w-full resize-none rounded-xl border border-line bg-canvas px-3 py-2 text-[15px] focus:border-sr-red focus:outline-none focus:ring-2 focus:ring-sr-red/25"
            />
          </div>
          <div>
            <label htmlFor={`${ids}-email`} className="mb-1 block text-sm font-medium">
              Your email <span className="font-normal text-text-3">(optional, for a reply)</span>
            </label>
            <input
              id={`${ids}-email`}
              type="email"
              inputMode="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="block h-11 w-full rounded-xl border border-line bg-canvas px-3 text-[15px] focus:border-sr-red focus:outline-none focus:ring-2 focus:ring-sr-red/25"
            />
          </div>
          {error && (
            <p role="alert" className="text-sm text-red-text">
              {error}
            </p>
          )}
          <div className="flex justify-end gap-2">
            <button type="button" className={btn("ghost")} onClick={close}>
              Cancel
            </button>
            <button type="submit" disabled={busy} className={btn("primary", "md", "min-w-[8rem]")}>
              {busy ? <Spinner size={16} /> : "Send report"}
            </button>
          </div>
        </form>
      )}
    </Dialog>
  );
}
