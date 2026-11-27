"use client";

// Small building blocks shared by the watch page, login and dashboard.
import { useEffect, useId, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { formatRelative, initials, nameHue } from "@/lib/client/format";
import { CheckIcon, CloseIcon, LinkIcon } from "./icons";
import "./player.css";
import { btn, type ButtonSize, type ButtonVariant } from "./ui-classes";

export { btn };

export function Avatar({ name, size = 32, owner = false }: { name: string | null; size?: number; owner?: boolean }) {
  const hue = nameHue(name);
  const colours: Record<string, string> = owner
    ? { "--av-bg": "var(--sr-red-deep)", "--av-ink": "#fff" }
    : {
        "--av-bg": `hsl(${hue} 70% 91%)`,
        "--av-ink": `hsl(${hue} 62% 27%)`,
        "--av-bg-dark": `hsl(${hue} 32% 26%)`,
        "--av-ink-dark": `hsl(${hue} 85% 86%)`,
      };
  return (
    <span
      aria-hidden="true"
      className="sr-avatar inline-flex shrink-0 select-none items-center justify-center rounded-full font-semibold"
      style={{ width: size, height: size, fontSize: Math.round(size * 0.38), ...colours } as CSSProperties}
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

// Background scroll lock. iOS Safari keeps scrolling a page behind a dialog whatever `overflow` says, so the body is
// pinned where it is and put back on close.
let locks = 0;
let lockedAt = 0;

function lockScroll(): () => void {
  locks += 1;
  if (locks === 1) {
    lockedAt = window.scrollY;
    Object.assign(document.body.style, { position: "fixed", top: `-${lockedAt}px`, left: "0", right: "0" });
  }
  let released = false;
  return () => {
    if (released) return;
    released = true;
    locks -= 1;
    if (locks > 0) return;
    Object.assign(document.body.style, { position: "", top: "", left: "", right: "" });
    window.scrollTo({ top: lockedAt, behavior: "instant" });
  };
}

/** A native modal dialog: Escape, the close button and the backdrop close it, focus is trapped by the browser. On
 *  phones it's a sheet above the keyboard that scrolls inside. */
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
  const titleId = useId();

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
    if (!open) return;

    const unlock = lockScroll();
    const vv = window.visualViewport;
    const fit = () => {
      // Pinch-zoomed: leave the sheet where it is and let people pan around it.
      if (!vv || vv.scale > 1.02) return;
      d.style.setProperty("--vv-height", `${vv.height}px`);
      d.style.setProperty("--vv-top", `${vv.offsetTop}px`);
      d.toggleAttribute("data-keyboard", window.innerHeight - vv.height > 120);
    };
    // Once the keyboard is up, bring the field being typed in into the part that's left.
    let timer = 0;
    const onFocus = (e: FocusEvent) => {
      const field = e.target;
      if (!(field instanceof HTMLElement) || !field.matches("textarea, input:not([type=radio]):not([type=checkbox])")) return;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => field.scrollIntoView({ block: "center" }), 320);
    };
    fit();
    vv?.addEventListener("resize", fit);
    vv?.addEventListener("scroll", fit);
    d.addEventListener("focusin", onFocus);
    return () => {
      unlock();
      window.clearTimeout(timer);
      vv?.removeEventListener("resize", fit);
      vv?.removeEventListener("scroll", fit);
      d.removeEventListener("focusin", onFocus);
    };
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
      aria-labelledby={titleId}
      className={`sr-dialog ${wide ? "max-w-lg" : "max-w-md"} border border-line bg-surface p-0 text-text shadow-[0_24px_80px_rgb(0_0_0/0.35)]`}
    >
      {open && (
        <>
          <div className="flex shrink-0 items-center justify-between gap-4 px-5 pb-2 pt-4 sm:px-6 sm:pt-5">
            <h2 id={titleId} className="text-lg font-semibold leading-snug">
              {title}
            </h2>
            <button
              type="button"
              onClick={onClose}
              className="-mr-2.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-text-2 hover:bg-fill hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
              aria-label="Close"
            >
              <CloseIcon size={18} />
            </button>
          </div>
          <div className="sr-dialog-body px-5 pb-5 pt-1 sm:px-6 sm:pb-6">{children}</div>
        </>
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
