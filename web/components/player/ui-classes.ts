// Class-name and colour helpers with no client code, so server components can use them too.

type Variant = "primary" | "secondary" | "ghost" | "danger" | "accent" | "quiet";
type Size = "sm" | "md" | "lg";

const variants: Record<Variant, string> = {
  primary: "bg-sr-red-deep text-white hover:bg-[#bd1f2e] active:bg-[#a81b29] disabled:bg-sr-red-deep disabled:opacity-40",
  accent:
    "bg-[var(--accent-strong,#d32434)] text-[var(--accent-ink,#fff)] hover:brightness-95 active:brightness-90 disabled:opacity-50",
  secondary: "bg-fill text-text hover:bg-line active:bg-line disabled:text-text-3",
  ghost: "text-text hover:bg-fill active:bg-line disabled:text-text-3",
  quiet: "text-text-2 hover:bg-fill hover:text-text active:bg-line disabled:text-text-3",
  danger: "bg-red-soft text-red-text hover:brightness-95 active:brightness-90 disabled:opacity-50",
};

const sizes: Record<Size, string> = {
  sm: "h-9 gap-1.5 px-3 text-sm",
  md: "h-11 gap-2 px-4 text-[15px]",
  lg: "h-12 gap-2 px-5 text-base",
};

export type ButtonVariant = Variant;
export type ButtonSize = Size;

/** Class names for a button, or a link that looks like one. */
export function btn(variant: Variant = "secondary", size: Size = "md", extra = ""): string {
  return `inline-flex shrink-0 items-center justify-center rounded-full font-semibold transition-[background-color,filter,color] duration-150 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sr-red disabled:cursor-not-allowed motion-reduce:transition-none ${variants[variant]} ${sizes[size]} ${extra}`;
}

/** White or ink text for a background colour, whichever has the better WCAG contrast. */
export function inkFor(hex: string): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return "#ffffff";
  const n = parseInt(m[1], 16);
  const channel = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  const l = 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
  const whiteContrast = 1.05 / (l + 0.05);
  const inkContrast = (l + 0.05) / (0.0074 + 0.05);
  return whiteContrast >= 4.5 || whiteContrast >= inkContrast ? "#ffffff" : "#13141b";
}

export function isHexColour(value: string | null | undefined): value is string {
  return !!value && /^#[0-9a-f]{6}$/i.test(value.trim());
}

/** CSS variables for the accent: the owner's brand colour (Pro) or Snapreel red. */
export function accentVars(brandColour: string | null | undefined): Record<string, string> {
  if (isHexColour(brandColour)) {
    return { "--accent": brandColour, "--accent-strong": brandColour, "--accent-ink": inkFor(brandColour) };
  }
  return { "--accent": "#f04850", "--accent-strong": "#d32434", "--accent-ink": "#ffffff" };
}
