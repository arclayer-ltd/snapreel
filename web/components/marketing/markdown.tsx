import Link from "next/link";
import type { ReactNode } from "react";

/*
 * A small Markdown renderer for the legal pages and help text: headings, paragraphs, lists,
 * blockquotes, rules, and inline **bold**, *italic*, `code` and [links](url). It covers what
 * docs/legal/*.md and help-articles.json use, without adding a dependency.
 */

// Bold is tried before italic, so "**x**" never reads as two italics.
const INLINE = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)\s]+\)|\*[^*\s][^*]*\*)/g;

export function inline(text: string, keyBase = "i"): ReactNode[] {
  const parts = text.split(INLINE).filter((p) => p !== "");
  return parts.map((part, i) => {
    const key = `${keyBase}-${i}`;
    if (part.startsWith("**") && part.endsWith("**")) return <strong key={key}>{inline(part.slice(2, -2), key)}</strong>;
    if (part.startsWith("`") && part.endsWith("`")) return <code key={key}>{part.slice(1, -1)}</code>;
    if (part.startsWith("[")) {
      const m = /^\[([^\]]+)\]\(([^)\s]+)\)$/.exec(part);
      if (m) {
        const [, label, href] = m;
        if (href.startsWith("/")) {
          return (
            <Link key={key} href={href}>
              {inline(label, key)}
            </Link>
          );
        }
        const external = /^https?:/.test(href);
        return (
          <a key={key} href={href} {...(external ? { rel: "noopener noreferrer" } : {})}>
            {inline(label, key)}
          </a>
        );
      }
    }
    if (part.length > 2 && part.startsWith("*") && part.endsWith("*")) return <em key={key}>{part.slice(1, -1)}</em>;
    return part;
  });
}

type Block =
  | { kind: "h"; level: number; text: string }
  | { kind: "p"; text: string }
  | { kind: "ul" | "ol"; items: string[] }
  | { kind: "quote"; text: string }
  | { kind: "hr" };

export function parseBlocks(md: string): Block[] {
  const lines = md.replace(/\r\n?/g, "\n").split("\n");
  const blocks: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      i++;
      continue;
    }
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    if (h) {
      blocks.push({ kind: "h", level: h[1].length, text: h[2].trim() });
      i++;
      continue;
    }
    if (/^(-{3,}|\*{3,})\s*$/.test(line)) {
      blocks.push({ kind: "hr" });
      i++;
      continue;
    }
    if (line.startsWith(">")) {
      const buf: string[] = [];
      while (i < lines.length && lines[i].startsWith(">")) buf.push(lines[i++].replace(/^>\s?/, ""));
      blocks.push({ kind: "quote", text: buf.join(" ") });
      continue;
    }
    if (/^\s*[-*]\s+/.test(line) || /^\s*\d+[.)]\s+/.test(line)) {
      const ordered = /^\s*\d+[.)]\s+/.test(line);
      const items: string[] = [];
      while (i < lines.length && (ordered ? /^\s*\d+[.)]\s+/ : /^\s*[-*]\s+/).test(lines[i])) {
        let item = lines[i].replace(ordered ? /^\s*\d+[.)]\s+/ : /^\s*[-*]\s+/, "");
        i++;
        while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*]|\d+[.)])\s+/.test(lines[i])) {
          item += " " + lines[i].trim();
          i++;
        }
        items.push(item);
      }
      blocks.push({ kind: ordered ? "ol" : "ul", items });
      continue;
    }
    const buf: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() &&
      !/^(#{1,4})\s/.test(lines[i]) &&
      !lines[i].startsWith(">") &&
      !/^\s*([-*]|\d+[.)])\s+/.test(lines[i])
    ) {
      buf.push(lines[i++].trim());
    }
    blocks.push({ kind: "p", text: buf.join(" ") });
  }
  return blocks;
}

export function Blocks({ blocks, shiftHeadings = 0 }: { blocks: Block[]; shiftHeadings?: number }) {
  return (
    <>
      {blocks.map((b, i) => {
        const k = `b${i}`;
        switch (b.kind) {
          case "h": {
            const level = Math.min(4, Math.max(2, b.level + shiftHeadings));
            const Tag = `h${level}` as "h2" | "h3" | "h4";
            const id = b.text
              .toLowerCase()
              .replace(/[^a-z0-9]+/g, "-")
              .replace(/^-|-$/g, "");
            return (
              <Tag key={k} id={id}>
                {inline(b.text, k)}
              </Tag>
            );
          }
          case "p":
            return <p key={k}>{inline(b.text, k)}</p>;
          case "ul":
            return (
              <ul key={k}>
                {b.items.map((it, j) => (
                  <li key={j}>{inline(it, `${k}-${j}`)}</li>
                ))}
              </ul>
            );
          case "ol":
            return (
              <ol key={k}>
                {b.items.map((it, j) => (
                  <li key={j}>{inline(it, `${k}-${j}`)}</li>
                ))}
              </ol>
            );
          case "quote":
            return <blockquote key={k}>{inline(b.text, k)}</blockquote>;
          case "hr":
            return <hr key={k} className="border-line" />;
        }
      })}
    </>
  );
}

/**
 * Split a legal document into its title, "Last updated" line and body. The drafts in
 * docs/legal start with a note to the owner ("DRAFT for owner review"); that note is for the
 * owner, not for visitors, so it's replaced by a plain "draft" flag the page shows politely.
 */
export function prepareLegal(md: string) {
  let blocks = parseBlocks(md);
  let draft = false;
  blocks = blocks.filter((b) => {
    if (b.kind === "quote" && /\bDRAFT\b/.test(b.text)) {
      draft = true;
      return false;
    }
    return true;
  });
  let title = "";
  const titleIdx = blocks.findIndex((b) => b.kind === "h" && b.level === 1);
  if (titleIdx >= 0) {
    title = (blocks[titleIdx] as { text: string }).text;
    blocks.splice(titleIdx, 1);
  }
  let updated = "";
  const upIdx = blocks.findIndex((b) => b.kind === "p" && /^last updated/i.test(b.text));
  if (upIdx >= 0) {
    updated = (blocks[upIdx] as { text: string }).text;
    blocks.splice(upIdx, 1);
  }
  return { title, updated, draft, blocks };
}
