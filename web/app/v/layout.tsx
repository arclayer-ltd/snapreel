import type { Viewport } from "next";
import { PagePaint, appViewport } from "@/components/player/page-paint";

export const viewport: Viewport = appViewport;

export default function WatchLayout({ children }: LayoutProps<"/v">) {
  return (
    <>
      <PagePaint />
      {children}
    </>
  );
}
