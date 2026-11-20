import "server-only";

// The comment word filter (App Review guideline 1.2, "a method for filtering objectionable material").
//
// A viewer's comment whose name or text matches this list is stored as held: other viewers never see it, and the
// video's owner approves or deletes it from the dashboard or the app. A reaction's typed name that matches is
// dropped (the reaction stays, anonymous). The owner's own comments are never held.
//
// Kept short on purpose: slurs and the strongest abuse, so ordinary comments are never held by mistake. The owner
// decides everything else. Server-side only; never send this list to a browser.
const STEMS = [
  "\\w*fuck\\w*",
  "shits?",
  "shitty",
  "shithead",
  "cunts?",
  "bitch(?:es|y)?",
  "whores?",
  "sluts?",
  "twats?",
  "wankers?",
  "assholes?",
  "pussy",
  "nigg(?:er|ers|a|as|az)",
  "faggots?",
  "fags?",
  "retard(?:s|ed)?",
  "kikes?",
  "spics?",
  "chinks?",
  "rap(?:e|ed|es|ist|ists)",
  "kys",
  "kill (?:yo)?urself",
];
const WORDS = new RegExp(`\\b(?:${STEMS.join("|")})\\b`, "i");

// Common look-alikes: "sh1t", "@ss", "$lut".
const LOOKALIKE: Record<string, string> = { "0": "o", "1": "i", "!": "i", "|": "i", "3": "e", "4": "a", "@": "a", "5": "s", $: "s", "7": "t" };

function variants(input: string): string[] {
  const plain = input
    .normalize("NFKD")
    .replace(/\p{M}/gu, "") // accents: "fück" -> "fuck"
    .toLowerCase()
    .replace(/[01!|34@5$7]/g, (c) => LOOKALIKE[c] ?? c)
    // Letters spaced out or dotted: "f u c k", "s.l.u.t" -> "fuck", "slut".
    .replace(/\b(?:\p{L}[\s._*-]){2,}\p{L}\b/gu, (m) => m.replace(/[\s._*-]/g, ""));
  // Stretched letters: runs of 3+ collapse to one ("fuuuck") and to two ("asssshole"); ordinary double letters
  // are left alone, so "Niger" or "Dickens" never change.
  return [plain, plain.replace(/(\p{L})\1{2,}/gu, "$1"), plain.replace(/(\p{L})\1{2,}/gu, "$1$1")];
}

/** True when the text matches the word list and a comment carrying it should wait for the owner. */
export function needsReview(...texts: string[]): boolean {
  return texts.some((t) => t && variants(t).some((v) => WORDS.test(v)));
}
