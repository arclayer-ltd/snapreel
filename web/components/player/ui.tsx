"use client";

// Small building blocks shared by the watch page, login and dashboard.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { formatRelative, initials, nameHue } from "@/lib/client/format";
import { CheckIcon, CloseIcon, LinkIcon } from "./icons";
import { btn, type ButtonSize, type ButtonVariant } from "./ui-classes";

export { btn };

export function Avatar({ name, size = 32, owner = false }: { name: string | null; size?: number; owner?: boolean }) {
  const hue = nameHue(name);
  return (
    <span
      aria-hidden="true"
      className="inline-flex shrink-0 select-none items-center justify-center rounded-full font-semibold"
      style={{
        width: size,
        height: size,
        fontSize: Math.round(size * 0.38),
        background: owner
          ? "var(--sr-red-deep)"
          : `light-dark(hsl(${hue} 70% 91%), hsl(${hue} 32% 26%))`,
        color: owner ? "#fff" : `light-dark(hsl(${hue} 62% 27%), hsl(${hue} 85% 86%))`,
      }}
    >
      {initials(name)}
    </span>
  );
}

/** "5 min ago", kept fresh, and allowed to differ between server and browser. */
export function RelativeTime({ iso, className }: { iso: string; className?: string }) {
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the clock starts after hydration
    setNow(Date.now());
    const id = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(id);
  }, []);
  return (
    <time dateTime={iso} className={className} suppressHydrationWarning title={new Date(iso).toLocaleString("en-GB")}>
      {formatRelative(iso, now ?? undefined)}
    </time>
  );
}

/** A native modal dialog: Escape and the backdrop close it, focus is trapped by the browser. */
export function Dialog({
  open,
  onClose,
  title,
  children,
  wide = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      aria-labelledby="sr-dialog-title"
      className={`m-auto w-[calc(100%-2rem)] ${wide ? "max-w-lg" : "max-w-md"} rounded-3xl border border-line bg-surface p-0 text-text shadow-[0_24px_80px_rgb(0_0_0/0.35)] backdrop:bg-black/55 backdrop:backdrop-blur-[2px]`}
    >
      {open && (
        <div className="p-5 sm:p-6">
          <div className="mb-4 flex items-start justify-between gap-4">
            <h2 id="sr-dialog-title" className="text-lg font-semibold leading-snug">
              {title}
            </h2>
            <button type="button" onClick={onClose} className={btn("quiet", "sm", "-mr-2 -mt-1 w-9 px-0")} aria-label="Close">
              <CloseIcon size={18} />
            </button>
          </div>
          {children}
        </div>
      )}
    </dialog>
  );
}

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand("copy");
    ta.remove();
    return ok;
  }
}

export function CopyLinkButton({
  url,
  label = "Copy link",
  variant = "secondary",
  size = "sm",
  className = "",
}: {
  url: string;
  label?: string;
  variant?: ButtonVariant;
  size?: ButtonSize;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const id = window.setTimeout(() => setCopied(false), 2000);
    return () => window.clearTimeout(id);
  }, [copied]);
  return (
    <button
      type="button"
      className={btn(variant, size, className)}
      onClick={async () => setCopied(await copyText(url))}
      aria-live="polite"
    >
      {copied ? <CheckIcon size={17} /> : <LinkIcon size={17} />}
      {copied ? "Copied" : label}
    </button>
  );
}

export function Spinner({ size = 18, className = "" }: { size?: number; className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={`inline-block animate-spin rounded-full border-2 border-current border-r-transparent motion-reduce:animate-[spin_2.4s_linear_infinite] ${className}`}
      style={{ width: size, height: size }}
    />
  );
}
