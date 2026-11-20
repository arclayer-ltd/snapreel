#!/usr/bin/env node
// Snapshot the app's help articles and the legal pages into the website, so a deploy made from
// web/ alone still has them. The site prefers the live files when the whole repo is present at
// build time (see web/components/marketing/content.ts); this snapshot is the fallback.
//
//   node scripts/web-sync-content.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => readFileSync(resolve(root, p), "utf8");

const help = JSON.parse(read("Snapreel/Features/Help/help-articles.json"));
const privacy = read("docs/legal/privacy-policy.md");
const terms = read("docs/legal/terms-of-use.md");

const out = `// Written by scripts/web-sync-content.mjs. Don't edit by hand; edit the sources and re-run it:
//   Snapreel/Features/Help/help-articles.json, docs/legal/privacy-policy.md, docs/legal/terms-of-use.md
import type { HelpData } from "./content-types";

export const helpSnapshot: HelpData = ${JSON.stringify(help, null, 2)};

export const privacySnapshot = ${JSON.stringify(privacy)};

export const termsSnapshot = ${JSON.stringify(terms)};
`;

writeFileSync(resolve(root, "web/components/marketing/content-snapshot.ts"), out);
console.log(`help: ${help.articles.length} articles; privacy: ${privacy.length} chars; terms: ${terms.length} chars`);
