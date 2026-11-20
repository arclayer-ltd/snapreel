"use client";

import { useRouter } from "next/navigation";
import { useId, useState, useTransition, type FormEvent } from "react";
import { ApiError, errorMessage, publicApi } from "@/lib/client/api";
import { LockIcon } from "../icons";
import { Spinner, btn } from "../ui";
import { WatchFooter, WatchHeader } from "./WatchChrome";

export function PasswordGate({ slug }: { slug: string }) {
  const router = useRouter();
  const id = useId();
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, startRefresh] = useTransition();

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!password) {
      setError("Enter the password to watch.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await publicApi.unlock(slug, password);
      startRefresh(() => router.refresh());
    } catch (err) {
      if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
        setError("That password isn’t right. Check it with the person who sent the link.");
      } else {
        setError(errorMessage(err, "Couldn’t check the password. Try again."));
      }
    } finally {
      setBusy(false);
    }
  }

  const working = busy || refreshing;

  return (
    <div className="flex min-h-svh flex-col">
      <WatchHeader logoUrl={null} ownerName={null} showBadge />
      <main className="flex flex-1 items-center justify-center px-4 py-10">
        <form
          onSubmit={submit}
          className="w-full max-w-sm rounded-3xl border border-line bg-surface p-6 text-center shadow-[0_12px_40px_rgb(19_20_27/0.08)] sm:p-8"
          noValidate
        >
          <span className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-red-soft text-red-text">
            <LockIcon size={26} />
          </span>
          <h1 className="mt-4 text-xl font-semibold tracking-tight">This video has a password</h1>
          <p className="mt-2 text-[15px] leading-relaxed text-text-2">Enter the password you were given to watch it.</p>
          <label htmlFor={id} className="sr-only">
            Password
          </label>
          <input
            id={id}
            type="password"
            autoComplete="off"
            autoFocus
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            aria-invalid={!!error}
            aria-describedby={error ? `${id}-error` : undefined}
            placeholder="Password"
            className="mt-5 block h-12 w-full rounded-2xl border border-line bg-canvas px-4 text-center text-base placeholder:text-text-3 focus:border-sr-red focus:outline-none focus:ring-2 focus:ring-sr-red/25"
          />
          {error && (
            <p id={`${id}-error`} role="alert" className="mt-3 text-sm text-red-text">
              {error}
            </p>
          )}
          <button type="submit" disabled={working} className={btn("primary", "lg", "mt-4 w-full")}>
            {working ? <Spinner size={18} /> : "Watch video"}
          </button>
        </form>
      </main>
      <WatchFooter showBadge={false} />
    </div>
  );
}
