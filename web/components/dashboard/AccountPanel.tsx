"use client";

// Account and plan: name, email, plan and renewal, email alerts, brand colour (Pro), sign out, delete.
// Pro is bought and managed only through the App Store; nothing here sells.
import { useRouter } from "next/navigation";
import { useId, useState } from "react";
import type { Me } from "@/lib/contract";
import { PRODUCT_MONTHLY } from "@/lib/contract";
import { errorMessage, ownerApi } from "@/lib/client/api";
import { formatLongDate } from "@/lib/client/format";
import { MANAGE_SUBSCRIPTIONS_URL } from "@/lib/client/links";
import { signOut } from "@/lib/client/supabase";
import { CheckIcon, ExternalIcon, LogOutIcon, SparkIcon, TrashIcon } from "@/components/player/icons";
import { Avatar, Dialog, Spinner, btn } from "@/components/player/ui";
import { inkFor, isHexColour } from "@/components/player/ui-classes";
import { Card, LockedHint, ProBadge, SwitchRow, inputClass } from "./kit";

export function AccountPanel({ initial }: { initial: Me }) {
  const router = useRouter();
  const ids = useId();
  const [me, setMe] = useState(initial);
  const [name, setName] = useState(initial.user.displayName ?? "");
  const [colour, setColour] = useState(initial.user.brandColor ?? "#d32434");
  const [saving, setSaving] = useState<"name" | "colour" | "alerts" | null>(null);
  const [saved, setSaved] = useState<"name" | "colour" | "alerts" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [failedOn, setFailedOn] = useState<"name" | "colour" | "alerts" | null>(null);
  const [signingOut, setSigningOut] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [alertsWanted, setAlertsWanted] = useState<boolean | null>(null);
  const [understood, setUnderstood] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const pro = me.plan.tier === "pro";
  const nameChanged = name.trim() !== (me.user.displayName ?? "");
  const colourChanged = isHexColour(colour) && colour.toLowerCase() !== (me.user.brandColor ?? "").toLowerCase();

  async function update(which: "name" | "colour" | "alerts", body: Parameters<typeof ownerApi.updateMe>[0]) {
    setSaving(which);
    setSaved(null);
    setError(null);
    setFailedOn(null);
    try {
      const next = await ownerApi.updateMe(body);
      setMe(next);
      setSaved(which);
      // So the other pages show the new name and settings without a reload.
      router.refresh();
    } catch (err) {
      setError(errorMessage(err, "That change wasn't saved. Try again."));
      setFailedOn(which);
    } finally {
      setSaving(null);
    }
  }

  async function doSignOut() {
    setSigningOut(true);
    await signOut();
    router.replace("/login");
    router.refresh();
  }

  async function deleteAccount() {
    setDeleting(true);
    setDeleteError(null);
    try {
      await ownerApi.deleteAccount();
      await signOut().catch(() => {});
      router.replace("/login?deleted=1");
      router.refresh();
    } catch (err) {
      setDeleting(false);
      setDeleteError(errorMessage(err, "Your account wasn't deleted. Try again, or email support@snapreel.video."));
    }
  }

  const yearly = me.plan.productId && me.plan.productId !== PRODUCT_MONTHLY;

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="flex items-center gap-4">
        <Avatar name={me.user.displayName ?? me.user.email} size={56} />
        <div className="min-w-0">
          <h1 className="truncate text-[26px] font-semibold tracking-tight">{me.user.displayName || "Your account"}</h1>
          <p className="truncate text-[15px] text-text-2">{me.user.email}</p>
        </div>
      </div>

      <Card title="Plan" id="plan">
        {pro ? (
          <div className="space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-sr-ink p-4 text-white">
              <div>
                <p className="flex items-center gap-2 text-lg font-semibold">
                  <SparkIcon size={18} className="text-sr-cream" />
                  Snapreel Pro
                </p>
                <p className="mt-0.5 text-sm text-white/75">
                  {yearly ? "Yearly" : "Monthly"}
                  {me.plan.expiresAt && <> · Renews {formatLongDate(me.plan.expiresAt)}</>}
                </p>
              </div>
              <a
                href={MANAGE_SUBSCRIPTIONS_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-10 items-center gap-1.5 rounded-full bg-white px-4 text-sm font-semibold text-sr-ink hover:bg-white/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
              >
                Manage subscription
                <ExternalIcon size={15} />
              </a>
            </div>
            <p className="text-sm text-text-2">
              Unlimited links up to 2 hours long, {me.usage.quality}, full insights, passwords, expiry, downloads, a
              call-to-action button and your own colour. Cancel any time in the App Store.
            </p>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-lg font-semibold">Free</p>
                <p className="text-sm text-text-2">
                  {me.usage.activeLinks} of {me.usage.linkLimit ?? 25} links · videos up to {Math.round(me.usage.maxDurationS / 60)}{" "}
                  minutes · {me.usage.quality}
                </p>
              </div>
            </div>
            <div className="rounded-2xl border border-line p-4">
              <p className="flex items-center gap-2 font-semibold">
                <ProBadge /> Upgrade in the Snapreel app
              </p>
              <ul className="mt-3 grid gap-x-4 gap-y-1.5 text-sm text-text-2 sm:grid-cols-2">
                {[
                  "Unlimited links",
                  "Videos up to 2 hours, in 1080p",
                  "Who watched and where they stopped",
                  "Passwords, expiry and downloads",
                  "A call-to-action button",
                  "Your colour, no Snapreel badge",
                ].map((f) => (
                  <li key={f} className="flex items-start gap-2">
                    <CheckIcon size={15} className="mt-0.5 shrink-0 text-red-text" />
                    {f}
                  </li>
                ))}
              </ul>
              <p className="mt-3 text-sm text-text-2">Open Snapreel on your iPhone, then Settings, then Snapreel Pro.</p>
            </div>
          </div>
        )}
      </Card>

      <Card title="Profile" id="profile">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (nameChanged && name.trim()) void update("name", { displayName: name.trim() });
          }}
          className="space-y-4"
        >
          <div>
            <label htmlFor={`${ids}-name`} className="mb-1.5 block text-sm font-medium">
              Name
            </label>
            <div className="flex gap-2">
              <input
                id={`${ids}-name`}
                value={name}
                onChange={(e) => {
                  setName(e.target.value);
                  setSaved(null);
                }}
                maxLength={60}
                autoComplete="name"
                enterKeyHint="done"
                className={inputClass}
              />
              <button type="submit" disabled={!nameChanged || !name.trim() || saving === "name"} aria-label="Save name" className={btn("secondary", "md", "min-w-[5rem]")}>
                {saving === "name" ? <Spinner size={16} /> : "Save"}
              </button>
            </div>
            <SaveNote
              saved={saved === "name" && !nameChanged}
              error={failedOn === "name" ? error : null}
              idle={name.trim() ? "Viewers see it on your watch pages and next to your replies." : "Add a name so viewers know who sent the video."}
            />
          </div>
          <div>
            <p className="mb-1.5 text-sm font-medium">Email</p>
            <p className="rounded-xl bg-fill px-3 py-2.5 text-[15px] text-text-2">{me.user.email ?? "Signed in with Apple"}</p>
          </div>
        </form>
      </Card>

      <Card title="Notifications" id="alerts">
        <SwitchRow
          title="Email me about activity"
          description="New viewers, comments and reactions on your links. Your iPhone gets notifications either way."
          // Moves at once; goes back if it didn't save.
          checked={alertsWanted ?? me.user.emailAlerts}
          disabled={saving === "alerts"}
          onChange={(v) => {
            setAlertsWanted(v);
            void update("alerts", { emailAlerts: v }).finally(() => setAlertsWanted(null));
          }}
        />
        <SaveNote
          saved={saved === "alerts"}
          error={failedOn === "alerts" ? error : null}
          idle={saving === "alerts" ? "Saving…" : ""}
        />
      </Card>

      <Card
        title={
          <span className="flex items-center gap-2">
            Watch page colour {!pro && <ProBadge />}
          </span>
        }
        id="brand"
        description="Buttons and the progress bar on your watch pages use it."
      >
        {pro ? (
          <div className="flex flex-wrap items-center gap-3">
            <label className="relative h-11 w-11 shrink-0 cursor-pointer overflow-hidden rounded-full border border-line" style={{ background: colour }}>
              <span className="sr-only">Pick a colour</span>
              <input type="color" value={isHexColour(colour) ? colour : "#d32434"} onChange={(e) => setColour(e.target.value)} className="absolute inset-0 h-full w-full cursor-pointer opacity-0" />
            </label>
            <label htmlFor={`${ids}-hex`} className="sr-only">
              Colour code
            </label>
            <input
              id={`${ids}-hex`}
              value={colour}
              onChange={(e) => setColour(e.target.value)}
              maxLength={7}
              spellCheck={false}
              className={`${inputClass.replace("w-full", "w-32")} font-mono uppercase`}
            />
            <span
              className="inline-flex h-11 items-center rounded-full px-4 text-[15px] font-semibold"
              style={isHexColour(colour) ? { background: colour, color: inkFor(colour) } : undefined}
              aria-hidden="true"
            >
              Preview
            </span>
            <button
              type="button"
              disabled={!colourChanged || saving === "colour"}
              onClick={() => void update("colour", { brandColor: colour.toLowerCase() })}
              aria-label="Save colour"
              className={btn("secondary", "md", "ml-auto min-w-[5rem]")}
            >
              {saving === "colour" ? <Spinner size={16} /> : "Save"}
            </button>
            {me.user.brandColor && (
              <button type="button" onClick={() => void update("colour", { brandColor: null })} className={btn("quiet", "sm")}>
                Use Snapreel red
              </button>
            )}
            <div className="w-full">
              <SaveNote saved={saved === "colour" && !colourChanged} error={failedOn === "colour" ? error : null} idle="" />
            </div>
          </div>
        ) : (
          <LockedHint>Your own colour, and no &ldquo;Made with Snapreel&rdquo; badge, come with Snapreel Pro. Upgrade in the Snapreel app on your iPhone.</LockedHint>
        )}
      </Card>

      <Card title="Signed in" id="session">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-text-2">Signing out here doesn&rsquo;t sign you out on your iPhone.</p>
          <button type="button" onClick={doSignOut} disabled={signingOut} className={btn("secondary", "md")}>
            {signingOut ? <Spinner size={16} /> : <LogOutIcon size={18} />}
            Sign out
          </button>
        </div>
      </Card>

      <section className="rounded-3xl border border-sr-red/40 p-4 sm:p-6" aria-labelledby={`${ids}-danger`}>
        <h2 id={`${ids}-danger`} className="text-[17px] font-semibold tracking-tight text-red-text">
          Delete account
        </h2>
        <p className="mt-1 text-sm leading-relaxed text-text-2">
          Deletes your account, every shared link and all their views, comments and reactions. Recordings on your iPhone stay.
        </p>
        <button type="button" onClick={() => setDeleteOpen(true)} className={btn("danger", "md", "mt-4")}>
          <TrashIcon size={18} />
          Delete account…
        </button>
      </section>

      <Dialog
        open={deleteOpen}
        onClose={() => {
          setDeleteOpen(false);
          setUnderstood(false);
        }}
        title="Delete your Snapreel account?"
      >
        <div className="space-y-3 text-[15px] leading-relaxed text-text-2">
          <p>
            This deletes your account and every link you&rsquo;ve shared, with their views, comments and reactions. It
            can&rsquo;t be undone. Recordings on your iPhone aren&rsquo;t touched.
          </p>
          {pro && (
            <p className="rounded-2xl bg-fill px-3.5 py-3 text-sm text-text">
              <strong>Your App Store subscription doesn&rsquo;t stop by itself.</strong> Cancel it in Settings on your iPhone
              (tap your name, then Subscriptions) or at{" "}
              <a href={MANAGE_SUBSCRIPTIONS_URL} target="_blank" rel="noopener noreferrer" className="font-medium underline underline-offset-2">
                apps.apple.com/account/subscriptions
              </a>
              , or Apple keeps charging you.
            </p>
          )}
          {!pro && (
            <p className="text-sm">If you ever bought Snapreel Pro, cancel it separately in the App Store: deleting your account doesn&rsquo;t.</p>
          )}
          <label className="flex min-h-11 cursor-pointer items-start gap-3 py-2 text-text">
            <input
              type="checkbox"
              checked={understood}
              onChange={(e) => setUnderstood(e.target.checked)}
              className="mt-0.5 h-5 w-5 shrink-0 accent-[#d32434]"
            />
            <span className="text-sm">I understand my links stop working and this can&rsquo;t be undone.</span>
          </label>
        </div>
        {deleteError && (
          <p role="alert" className="mt-3 text-sm text-red-text">
            {deleteError}
          </p>
        )}
        <div className="mt-4 flex justify-end gap-2">
          <button type="button" className={btn("ghost", "md", "max-sm:flex-1")} onClick={() => setDeleteOpen(false)}>
            Cancel
          </button>
          <button type="button" className={btn("primary", "md", "min-w-[9rem] max-sm:flex-1")} disabled={!understood || deleting} onClick={deleteAccount}>
            {deleting ? <Spinner size={16} /> : "Delete account"}
          </button>
        </div>
      </Dialog>
    </div>
  );
}

/** What happened to a change, right under the field that was changed. */
function SaveNote({ saved, error, idle }: { saved: boolean; error: string | null; idle: string }) {
  if (error) {
    return (
      <p role="alert" className="mt-1.5 text-sm text-red-text">
        {error}
      </p>
    );
  }
  return (
    <p role="status" className={`mt-1.5 min-h-5 text-sm ${saved ? "font-medium text-text" : "text-text-2"}`}>
      {saved ? (
        <span className="inline-flex items-center gap-1.5">
          <CheckIcon size={16} className="text-red-text" /> Saved
        </span>
      ) : (
        idle
      )}
    </p>
  );
}
