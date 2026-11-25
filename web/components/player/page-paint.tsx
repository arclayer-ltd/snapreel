// First paint for the watch page, sign-in and dashboard: the theme's background in the first bytes of the HTML, so a
// dark iPhone (and the app's Safari sheet) never shows a white page while the stylesheet is on its way.
import type { Viewport } from "next";

const CSS =
  "html{background:#f4f4f6;color-scheme:light dark}@media(prefers-color-scheme:dark){html{background:#0e0f14}}";

export function PagePaint() {
  // href and precedence make React put it in <head>, once.
  return (
    <style href="sr-paint" precedence="sr-paint">
      {CSS}
    </style>
  );
}

export const appViewport: Viewport = {
  colorScheme: "light dark",
  // Lets env(safe-area-inset-*) work; .sr-safe-x and the bottom bar use it.
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f4f6" },
    { media: "(prefers-color-scheme: dark)", color: "#0e0f14" },
  ],
};
