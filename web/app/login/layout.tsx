import type { Viewport } from "next";
import { PagePaint, appViewport } from "@/components/player/page-paint";

export const viewport: Viewport = appViewport;

export default function LoginLayout({ children }: LayoutProps<"/login">) {
  return (
    <>
      <PagePaint />
      {children}
    </>
  );
}
