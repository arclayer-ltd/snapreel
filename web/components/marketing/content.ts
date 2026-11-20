import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { HelpArticle, HelpData } from "./content-types";
import { helpSnapshot, privacySnapshot, termsSnapshot } from "./content-snapshot";

/*
 * The help centre comes from the app's own help-articles.json, and the legal pages from
 * docs/legal/*.md. At build time, when the whole repo is there, the live files are read so the
 * site always matches the app. A deploy made from web/ alone falls back to the snapshot written
 * by scripts/web-sync-content.mjs.
 */

const repo = resolve(process.cwd(), "..");

function readLive(rel: string): string | null {
  try {
    return readFileSync(resolve(repo, rel), "utf8");
  } catch {
    return null;
  }
}

let helpCache: HelpData | null = null;

export function getHelp(): HelpData {
  if (helpCache) return helpCache;
  const live = readLive("Snapreel/Features/Help/help-articles.json");
  let data = helpSnapshot;
  if (live) {
    try {
      data = JSON.parse(live) as HelpData;
    } catch {
      data = helpSnapshot;
    }
  }
  helpCache = data;
  return data;
}

export function getArticle(id: string): HelpArticle | undefined {
  return getHelp().articles.find((a) => a.id === id);
}

export function getLegal(doc: "privacy" | "terms"): string {
  const rel = doc === "privacy" ? "docs/legal/privacy-policy.md" : "docs/legal/terms-of-use.md";
  return readLive(rel) ?? (doc === "privacy" ? privacySnapshot : termsSnapshot);
}
