"use client";

// A new dashboard page starts at the top. The router keeps the scroll position when the new page's top is already in
// view or the page was kept from before, so a video opened from far down the list landed part-way down its own page.
import { usePathname } from "next/navigation";
import { useEffect, useRef } from "react";

export function ScrollToTop() {
  const pathname = usePathname();
  const last = useRef(pathname);
  useEffect(() => {
    if (last.current === pathname) return;
    last.current = pathname;
    window.scrollTo({ top: 0, behavior: "instant" });
  }, [pathname]);
  return null;
}
