/** Small inline marks and icons for the marketing pages. All decorative (aria-hidden). */

/** The app's own icon (Snapreel/Resources/Assets.xcassets/AppIcon), in its rounded-square shape, as the logo. */
export function AppIcon({ size = 32, className = "" }: { size?: number; className?: string }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element -- a 2 KB fixed-size logo; next/image adds nothing here
    <img
      src="/marketing/app-icon-64.webp"
      srcSet="/marketing/app-icon-64.webp 64w, /marketing/app-icon-128.webp 128w, /marketing/app-icon-192.webp 192w"
      sizes={`${size}px`}
      width={size}
      height={size}
      alt=""
      aria-hidden="true"
      decoding="async"
      draggable={false}
      className={`mk-appicon ${className}`}
    />
  );
}

export function ArrowRight({ size = 20 }: { size?: number }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12h15M13 6l6 6-6 6" />
    </svg>
  );
}

export function Check({ size = 18, className = "" }: { size?: number; className?: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} className={className} fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="m5 12.5 4.5 4.5L19 7.5" />
    </svg>
  );
}

const paths = {
  link: "M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1",
  browser: "M3.5 6.5A2.5 2.5 0 0 1 6 4h12a2.5 2.5 0 0 1 2.5 2.5v11A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5v-11ZM3.5 9h17M7 6.6h.01M9.6 6.6h.01M10.5 12.5v4l3.5-2-3.5-2Z",
  chat: "M20 12a7.5 7.5 0 0 1-10.9 6.7L4.5 20l1.3-4.2A7.5 7.5 0 1 1 20 12ZM9 11h.01M12.5 11h.01M16 11h.01",
  chart: "M4 20V10M10 20V4M16 20v-7M21 20H3",
  lock: "M7 11V8a5 5 0 0 1 10 0v3M5.5 11h13a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5v-6A1.5 1.5 0 0 1 5.5 11ZM12 15v2",
  folder: "M3.5 7.5A2.5 2.5 0 0 1 6 5h3.6l2 2.2H18a2.5 2.5 0 0 1 2.5 2.5v7.8A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5v-10Z",
  text: "M5 6h14M5 10.5h14M5 15h9M5 19.5h6",
  photo: "M4 7.5A2.5 2.5 0 0 1 6.5 5h11A2.5 2.5 0 0 1 20 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 16.5v-9ZM4.5 16l4.5-4.5 3.5 3.5 2.5-2.5L20 17M15.5 9.5h.01",
  person: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM4.5 20a7.5 7.5 0 0 1 15 0",
  stop: "M5 7h14M10 11v6M14 11v6M6.5 7l.8 11.2A2 2 0 0 0 9.3 20h5.4a2 2 0 0 0 2-1.8L17.5 7M9.5 7V5.5A1.5 1.5 0 0 1 11 4h2a1.5 1.5 0 0 1 1.5 1.5V7",
  screen: "M7.5 3h9A1.5 1.5 0 0 1 18 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19.5v-15A1.5 1.5 0 0 1 7.5 3ZM10.5 5.5h3",
  camera: "M3.5 8.5A2.5 2.5 0 0 1 6 6h1.7l1.5-2h5.6l1.5 2H18a2.5 2.5 0 0 1 2.5 2.5v8A2.5 2.5 0 0 1 18 19H6a2.5 2.5 0 0 1-2.5-2.5v-8ZM12 16a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z",
  mic: "M12 15a3.5 3.5 0 0 0 3.5-3.5v-5a3.5 3.5 0 0 0-7 0v5A3.5 3.5 0 0 0 12 15ZM5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3",
  search: "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14ZM20 20l-3.5-3.5",
  mail: "M4 6.5A1.5 1.5 0 0 1 5.5 5h13A1.5 1.5 0 0 1 20 6.5v11a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5v-11ZM4.5 6.5 12 12l7.5-5.5",
  flag: "M5 21V4M5 4.5h11l-2 4 2 4H5",
  pencil: "M4.5 19.5 5.6 15 16 4.6a1.8 1.8 0 0 1 2.5 0l.9.9a1.8 1.8 0 0 1 0 2.5L9 18.4l-4.5 1.1Z",
  save: "M8.5 9H7a2.5 2.5 0 0 0-2.5 2.5V17A2.5 2.5 0 0 0 7 19.5h10a2.5 2.5 0 0 0 2.5-2.5v-5.5A2.5 2.5 0 0 0 17 9h-1.5M12 3.5V14M8.8 11l3.2 3.2 3.2-3.2",
  clock: "M12 20.5a8.5 8.5 0 1 0 0-17 8.5 8.5 0 0 0 0 17ZM12 7v5H8.5",
  sparkle: "M12 3c.6 4.6 3.4 7.4 8 8-4.6.6-7.4 3.4-8 8-.6-4.6-3.4-7.4-8-8 4.6-.6 7.4-3.4 8-8Z",
} as const;

export type IconName = keyof typeof paths;

export function Icon({ name, size = 20, className = "" }: { name: IconName; size?: number; className?: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} className={className} fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d={paths[name]} />
    </svg>
  );
}
