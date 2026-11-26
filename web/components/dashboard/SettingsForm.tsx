"use client";

// Link settings for one video. Password, expiry, downloads and the call-to-action are Pro; Free sees
// them locked. Changes are saved together, so nothing goes live half-done.
import { useId, useMemo, useState, type FormEvent } from "react";
import type { Access, UpdateVideoRequest, VideoDetail } from "@/lib/contract";
import { errorMessage, isValidCtaUrl, ownerApi } from "@/lib/client/api";
import { formatLongDate, formatUntil, isPast } from "@/lib/client/format";
import { CheckIcon, LinkIcon, LockIcon } from "@/components/player/icons";
import { Spinner, btn } from "@/components/player/ui";
import { Card, LockedHint, ProBadge, SwitchRow, inputClass } from "./kit";

type Expiry = "keep" | "never" | "1d" | "7d" | "30d" | "date";

interface FormState {
  title: string;
  access: Access;
  password: string;
  changingPassword: boolean;
  expiry: Expiry;
  expiryDate: string;
  allowDownload: boolean;
  allowComments: boolean;
  allowReactions: boolean;
  ctaOn: boolean;
  ctaLabel: string;
  ctaUrl: string;
}

function fromVideo(v: VideoDetail): FormState {
  return {
    title: v.title,
    access: v.access,
    password: "",
    changingPassword: false,
    expiry: v.expiresAt ? "keep" : "never",
    expiryDate: "",
    allowDownload: v.allowDownload,
    allowComments: v.allowComments,
    allowReactions: v.allowReactions,
    ctaOn: !!v.cta,
    ctaLabel: v.cta?.label ?? "",
    ctaUrl: v.cta?.url ?? "",
  };
}

const DAY = 86_400_000;

/** The changes to send. `now` is 0 while rendering (only "is anything different?" matters then) and the
 *  real time when saving, so relative expiry dates are worked out at the moment of saving. */
function buildPatch(v: VideoDetail, f: FormState, now: number): { patch: UpdateVideoRequest; problem: string | null } {
  const patch: UpdateVideoRequest = {};
  let problem: string | null = null;

  const title = f.title.trim();
  if (title !== v.title) {
    if (!title) problem = "Give the video a title.";
    else patch.title = title.slice(0, 120);
  }

  if (f.access !== v.access || (f.access === "password" && f.password)) {
    if (f.access === "password" && !f.password && !v.hasPassword) {
      problem ??= "Choose a password, or keep the link open to anyone.";
    } else if (f.access === "password" && f.password && f.password.length < 4) {
      problem ??= "Use at least 4 characters for the password.";
    } else {
      patch.access = f.access;
      if (f.access === "password" && f.password) patch.password = f.password;
    }
  }

  if (f.expiry === "never" && v.expiresAt) patch.expiresAt = null;
  if (f.expiry === "1d" || f.expiry === "7d" || f.expiry === "30d") {
    const days = f.expiry === "1d" ? 1 : f.expiry === "7d" ? 7 : 30;
    patch.expiresAt = new Date(now + days * DAY).toISOString();
  }
  if (f.expiry === "date") {
    if (!f.expiryDate) problem ??= "Pick the day the link should stop working.";
    else {
      const end = new Date(`${f.expiryDate}T23:59:59`);
      if (Number.isNaN(end.getTime()) || (now > 0 && end.getTime() < now)) problem ??= "Pick a day from today onwards.";
      else patch.expiresAt = end.toISOString();
    }
  }

  if (f.allowDownload !== v.allowDownload) patch.allowDownload = f.allowDownload;
  if (f.allowComments !== v.allowComments) patch.allowComments = f.allowComments;
  if (f.allowReactions !== v.allowReactions) patch.allowReactions = f.allowReactions;

  if (f.ctaOn) {
    const label = f.ctaLabel.trim();
    const url = f.ctaUrl.trim();
    if (label !== (v.cta?.label ?? "") || url !== (v.cta?.url ?? "")) {
      if (!label) problem ??= "Add the text for the button.";
      else if (!isValidCtaUrl(url)) problem ??= "The button's link needs to start with https://";
      else patch.cta = { label: label.slice(0, 40), url };
    }
  } else if (v.cta) {
    patch.cta = null;
  }

  return { patch, problem };
}

export function SettingsForm({
  video,
  pro,
  onSaved,
}: {
  video: VideoDetail;
  pro: boolean;
  onSaved: (v: VideoDetail) => void;
}) {
  const ids = useId();
  const [form, setForm] = useState<FormState>(() => fromVideo(video));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const { patch, problem } = useMemo(() => buildPatch(video, form, 0), [video, form]);
  const dirty = Object.keys(patch).length > 0 || (problem !== null && JSON.stringify(form) !== JSON.stringify(fromVideo(video)));

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) => {
    setForm((f) => ({ ...f, [key]: value }));
    setSaved(false);
    setError(null);
  };

  async function save(e: FormEvent) {
    e.preventDefault();
    const { patch, problem } = buildPatch(video, form, Date.now());
    if (problem) {
      setError(problem);
      return;
    }
    if (!Object.keys(patch).length) return;
    setBusy(true);
    setError(null);
    try {
      const next = await ownerApi.updateVideo(video.id, patch);
      onSaved(next);
      setForm(fromVideo(next));
      setSaved(true);
    } catch (err) {
      setError(errorMessage(err, "Your changes weren't saved. Try again."));
    } finally {
      setBusy(false);
    }
  }

  const expired = video.expiresAt ? isPast(video.expiresAt) : false;

  return (
    <Card title="Link settings" id="settings">
      <form onSubmit={save} className="space-y-6" noValidate>
        <div>
          <label htmlFor={`${ids}-title`} className="mb-1.5 block text-sm font-medium">
            Title
          </label>
          <input
            id={`${ids}-title`}
            value={form.title}
            onChange={(e) => set("title", e.target.value)}
            maxLength={120}
            className={inputClass}
          />
          <p className="mt-1 text-xs text-text-3">Shown on the watch page and in link previews.</p>
        </div>

        <div className="space-y-3 border-t border-line pt-5">
          <div className="flex items-center gap-2">
            <h3 className="font-semibold">Privacy</h3>
            {!pro && <ProBadge />}
          </div>
          {!pro && <LockedHint>Password, expiry, downloads and the button are part of Snapreel Pro. Upgrade in the Snapreel app on your iPhone.</LockedHint>}

          <fieldset disabled={!pro} className="space-y-2">
            <legend className="mb-1.5 text-sm font-medium">Who can watch</legend>
            {(
              [
                ["link", "Anyone with the link", "No sign-in or password needed.", LinkIcon],
                ["password", "People with the password", "They type it once in each browser.", LockIcon],
              ] as const
            ).map(([value, label, hint, Icon]) => (
              <label
                key={value}
                className={`flex cursor-pointer items-start gap-3 rounded-2xl border px-3.5 py-3 transition-colors has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60 motion-reduce:transition-none ${
                  form.access === value ? "border-sr-red bg-red-soft/50" : "border-line hover:bg-fill"
                }`}
              >
                <input
                  type="radio"
                  name={`${ids}-access`}
                  value={value}
                  checked={form.access === value}
                  onChange={() => set("access", value)}
                  className="mt-1 h-4 w-4 accent-[#d32434]"
                />
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-2 font-medium">
                    <Icon size={16} className="text-text-2" />
                    {label}
                  </span>
                  <span className="mt-0.5 block text-sm text-text-2">{hint}</span>
                </span>
              </label>
            ))}
            {form.access === "password" && (
              <div className="pt-1">
                {video.hasPassword && !form.changingPassword && video.access === "password" ? (
                  <div className="flex items-center justify-between gap-3 rounded-2xl bg-fill px-3.5 py-3 text-sm">
                    <span className="flex items-center gap-2">
                      <CheckIcon size={16} className="text-red-text" /> A password is set.
                    </span>
                    <button type="button" className={btn("secondary", "sm")} onClick={() => set("changingPassword", true)}>
                      Change
                    </button>
                  </div>
                ) : (
                  <>
                    <label htmlFor={`${ids}-pw`} className="mb-1.5 block text-sm font-medium">
                      {video.hasPassword ? "New password" : "Password"}
                    </label>
                    <input
                      id={`${ids}-pw`}
                      type="text"
                      autoComplete="off"
                      autoCapitalize="none"
                      autoCorrect="off"
                      spellCheck={false}
                      value={form.password}
                      onChange={(e) => set("password", e.target.value)}
                      maxLength={72}
                      placeholder="At least 4 characters"
                      className={inputClass}
                    />
                    <p className="mt-1 text-xs text-text-3">Send it to people separately from the link.</p>
                  </>
                )}
              </div>
            )}
          </fieldset>

          <div>
            <label htmlFor={`${ids}-expiry`} className="mb-1.5 block text-sm font-medium">
              Link stops working
            </label>
            <select
              id={`${ids}-expiry`}
              value={form.expiry}
              onChange={(e) => set("expiry", e.target.value as Expiry)}
              disabled={!pro}
              className={`${inputClass} cursor-pointer`}
            >
              {video.expiresAt && (
                <option value="keep">
                  {expired ? "Expired" : "On"} {formatLongDate(video.expiresAt)}
                </option>
              )}
              <option value="never">Never</option>
              <option value="1d">In 1 day</option>
              <option value="7d">In 7 days</option>
              <option value="30d">In 30 days</option>
              <option value="date">On a day you choose…</option>
            </select>
            {form.expiry === "date" && (
              <input
                type="date"
                aria-label="Day the link stops working"
                value={form.expiryDate}
                min={new Date().toISOString().slice(0, 10)}
                onChange={(e) => set("expiryDate", e.target.value)}
                className={`${inputClass} mt-2`}
              />
            )}
            {video.expiresAt && form.expiry === "keep" && (
              <p className={`mt-1 text-xs ${expired ? "text-red-text" : "text-text-3"}`}>
                {expired
                  ? "This link has expired, so it no longer plays. Pick a new date or Never to share it again."
                  : `It stops working ${formatUntil(video.expiresAt)}.`}
              </p>
            )}
          </div>
        </div>

        <div className="divide-y divide-line border-t border-line">
          <SwitchRow
            title="Comments"
            description="Viewers can comment at moments in the video."
            checked={form.allowComments}
            onChange={(v) => set("allowComments", v)}
          />
          <SwitchRow
            title="Reactions"
            description="Viewers can react with emoji."
            checked={form.allowReactions}
            onChange={(v) => set("allowReactions", v)}
          />
          <SwitchRow
            title="Downloads"
            description="Viewers can save the video file."
            checked={form.allowDownload}
            onChange={(v) => set("allowDownload", v)}
            disabled={!pro}
            pro={!pro}
          />
        </div>

        <div className="border-t border-line pt-1">
          <SwitchRow
            title="Call-to-action button"
            description="A button under the video and at the end, like “Book a call”."
            checked={form.ctaOn}
            onChange={(v) => set("ctaOn", v)}
            disabled={!pro}
            pro={!pro}
          />
          {form.ctaOn && (
            <div className="grid gap-3 pb-2 sm:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
              <div>
                <label htmlFor={`${ids}-cta-label`} className="mb-1.5 block text-sm font-medium">
                  Button text
                </label>
                <input
                  id={`${ids}-cta-label`}
                  value={form.ctaLabel}
                  onChange={(e) => set("ctaLabel", e.target.value)}
                  maxLength={40}
                  placeholder="Book a call"
                  disabled={!pro}
                  className={inputClass}
                />
              </div>
              <div>
                <label htmlFor={`${ids}-cta-url`} className="mb-1.5 block text-sm font-medium">
                  Link
                </label>
                <input
                  id={`${ids}-cta-url`}
                  type="url"
                  inputMode="url"
                  autoCapitalize="none"
                  autoCorrect="off"
                  value={form.ctaUrl}
                  onChange={(e) => set("ctaUrl", e.target.value)}
                  placeholder="https://"
                  disabled={!pro}
                  className={inputClass}
                />
              </div>
            </div>
          )}
        </div>

        {error && (
          <p role="alert" className="rounded-2xl bg-red-soft px-3.5 py-3 text-sm text-red-text">
            {error}
          </p>
        )}

        <div
          className={`sticky bottom-[calc(4.25rem+env(safe-area-inset-bottom))] z-10 sm:bottom-3 flex items-center gap-2 rounded-2xl border border-line bg-surface/95 p-2 pl-4 shadow-[0_10px_30px_rgb(19_20_27/0.12)] backdrop-blur ${
            dirty || saved ? "" : "hidden"
          }`}
        >
          <p className="flex-1 text-sm text-text-2" role="status">
            {saved ? (
              <span className="inline-flex items-center gap-1.5 text-text">
                <CheckIcon size={16} className="text-red-text" /> Saved
              </span>
            ) : (
              "Unsaved changes"
            )}
          </p>
          {dirty && (
            <>
              <button
                type="button"
                onClick={() => {
                  setForm(fromVideo(video));
                  setError(null);
                }}
                className={btn("ghost", "sm")}
              >
                Discard
              </button>
              <button type="submit" disabled={busy} className={btn("primary", "sm", "min-w-[5.5rem]")}>
                {busy ? <Spinner size={15} /> : "Save"}
              </button>
            </>
          )}
        </div>
      </form>
    </Card>
  );
}
