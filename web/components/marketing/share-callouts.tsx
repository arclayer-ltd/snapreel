/* The Copy link scene's callouts: pieces of the phone's screen lifted out beside it (the link a viewer opens,
   the reactions, two comments), each tied by a thin line to the place it comes from on the screen. They live in
   the phone's own box (.mk-scene-phone), so --y and --tx are percentages of the phone's height and width and
   the lines meet their targets at any size. Wide screens only; phones get the short list in page.tsx.

   A viewer comments with a name only, so the app shows a commenter's initial; the lifted comments do the same. */
import type { CSSProperties, ReactNode } from "react";
import { Icon, type IconName } from "./marks";
import { Reveal } from "./reveal";

type Callout = {
  side: "l" | "r";
  /** Target on the phone, in % of its height (y) and width (tx). The card's middle sits at y. */
  y: number;
  tx: number;
  w: number;
  icon?: IconName;
  title?: string;
  piece: ReactNode;
};

/** The commenter's initial in a circle, as the app draws it. */
function Initial({ name }: { name: string }) {
  return (
    <span className="grid size-8 shrink-0 place-items-center rounded-full bg-fill text-[13px] font-semibold text-text-2">
      {name.charAt(0)}
    </span>
  );
}

function Comment({ name, ago, at, text }: { name: string; ago: string; at: string; text: string }) {
  return (
    <div className="flex items-start gap-2.5">
      <Initial name={name} />
      <div className="min-w-0">
        <p className="text-[13px] leading-tight">
          <span className="font-semibold">{name}</span> <span className="text-text-3">{ago}</span>
        </p>
        <p className="mt-0.5 text-[13px] leading-snug text-text-2">{text}</p>
        <span className="mt-1.5 inline-flex items-center gap-1 rounded-full bg-red-soft px-2 py-0.5 text-[11px] font-semibold text-red-text">
          <svg width="8" height="8" viewBox="0 0 8 8" aria-hidden="true">
            <path d="M1.5 1v6l5-3-5-3Z" fill="currentColor" />
          </svg>
          {at}
        </span>
      </div>
    </div>
  );
}

const reactions: [string, number][] = [
  ["👍", 3],
  ["🔥", 3],
  ["👏", 2],
  ["😮", 1],
  ["❤️", 1],
];

const callouts: Callout[] = [
  {
    side: "l",
    y: 21.5,
    tx: 22,
    w: 248,
    icon: "browser",
    title: "Plays in any browser",
    piece: (
      <span className="flex items-center gap-2 rounded-full bg-fill px-3 py-2 text-[13px] text-text-2">
        <Icon name="lock" size={14} className="shrink-0" />
        <span className="truncate">snapreel.video/v/k7Qm2xRb9L</span>
      </span>
    ),
  },
  {
    side: "l",
    y: 46,
    tx: 12,
    w: 278,
    icon: "sparkle",
    title: "Reactions on the moment",
    piece: (
      <span className="flex gap-1.5">
        {reactions.map(([emoji, n]) => (
          <span key={emoji} className="inline-flex items-center gap-1 rounded-full bg-fill px-2 py-1 text-[12px] font-semibold">
            <span aria-hidden="true">{emoji}</span>
            {n}
          </span>
        ))}
      </span>
    ),
  },
  {
    side: "r",
    y: 51,
    tx: 88,
    w: 268,
    icon: "chat",
    title: "Comments at the second",
    piece: <Comment name="Priya Shah" ago="25m ago" at="0:14" text="The total still shows £42 after I remove the coupon." />,
  },
  {
    side: "r",
    y: 73,
    tx: 88,
    w: 248,
    piece: <Comment name="Tom Becker" ago="Yesterday" at="0:41" text="Autocomplete is so much quicker now 🙌" />,
  },
];

export function ShareCallouts() {
  return (
    <Reveal className="mk-callouts" ariaHidden>
      {callouts.map((c, i) => (
        <div
          key={i}
          className={`mk-callout mk-callout--${c.side}`}
          style={{ "--y": c.y, "--tx": c.tx, "--w": `${c.w}px`, "--d": `${120 + i * 110}ms` } as CSSProperties}
        >
          <span className="mk-callout-line" />
          <div className="mk-callout-card">
            {c.title ? (
              <p className="mb-2 flex items-center gap-1.5 text-[13px] font-semibold">
                {c.icon ? <Icon name={c.icon} size={16} className="text-red-text" /> : null}
                {c.title}
              </p>
            ) : null}
            {c.piece}
          </div>
        </div>
      ))}
    </Reveal>
  );
}

/** Phones: the same three ideas as a short list under the scene. */
export function ShareList() {
  const items: { icon: IconName; title: string; text: ReactNode }[] = [
    { icon: "browser", title: "Plays in any browser", text: "No app or account to watch." },
    {
      icon: "chat",
      title: "Comments at the second",
      text: "Viewers comment at the exact moment they mean.",
    },
    { icon: "sparkle", title: "Reactions on the moment", text: "You get an alert for each one." },
  ];
  return (
    <ul className="grid grid-cols-1 gap-3 px-[var(--mk-gutter)] pt-6 sm:grid-cols-3 lg:hidden">
      {items.map((f) => (
        <li key={f.title} className="mk-card mk-card--s flex items-start gap-3 p-4">
          <span className="mk-icon">
            <Icon name={f.icon} />
          </span>
          <span className="min-w-0">
            <span className="block font-semibold leading-snug">{f.title}</span>
            <span className="mt-0.5 block text-sm leading-snug text-text-2">{f.text}</span>
          </span>
        </li>
      ))}
    </ul>
  );
}
