// 1200×630 link-preview cards for /v links that can't show their own poster.
import { ImageResponse } from "next/og";

function Mark({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32">
      <rect width="32" height="32" rx="8" fill="#13141b" />
      <circle cx="16" cy="16" r="8.9" fill="none" stroke="#f04850" strokeWidth="2.3" />
      <circle cx="16" cy="16" r="4.7" fill="#f04850" />
    </svg>
  );
}

export function previewCard(kind: "locked" | "generic") {
  const locked = kind === "locked";
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 72,
          background: "radial-gradient(circle at 30% 20%, #fe6262 0%, #d32434 45%, #5e0b16 100%)",
          color: "white",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <Mark size={72} />
          <div style={{ fontSize: 44, fontWeight: 700, letterSpacing: -1 }}>Snapreel</div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 22 }}>
            <div
              style={{
                width: 96,
                height: 96,
                borderRadius: 48,
                background: "rgba(255,255,255,0.16)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              {locked ? (
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#ffe9b8" strokeWidth="2" strokeLinecap="round">
                  <rect x="4.5" y="10.5" width="15" height="10" rx="2.5" />
                  <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
                </svg>
              ) : (
                <svg width="46" height="46" viewBox="0 0 24 24">
                  <path d="M8 5.5v13a1 1 0 0 0 1.52.85l10.4-6.5a1 1 0 0 0 0-1.7L9.52 4.65A1 1 0 0 0 8 5.5Z" fill="#ffe9b8" />
                </svg>
              )}
            </div>
            <div style={{ fontSize: 64, fontWeight: 700, letterSpacing: -1.5 }}>
              {locked ? "This video has a password" : "Watch on Snapreel"}
            </div>
          </div>
          <div style={{ fontSize: 30, color: "#ffe9b8" }}>
            {locked ? "Open the link and enter the password to watch." : "Screen, camera and voice recordings, shared as a link."}
          </div>
        </div>
      </div>
    ),
    { width: 1200, height: 630, headers: { "cache-control": "public, max-age=86400, immutable" } },
  );
}
