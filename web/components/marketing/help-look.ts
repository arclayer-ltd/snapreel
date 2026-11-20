import type { IconName } from "./marks";

/* A pastel tone and an icon for each help category, by id; anything new falls back to blue. Used by the
   help centre's topic tiles and an article's topic card. */
const look: Record<string, { tone: string; icon: IconName }> = {
  start: { tone: "mk-tile--blue", icon: "sparkle" },
  recording: { tone: "mk-tile--peach", icon: "camera" },
  screen: { tone: "mk-tile--lilac", icon: "screen" },
  library: { tone: "mk-tile--mint", icon: "folder" },
  watching: { tone: "mk-tile--butter", icon: "browser" },
  notes: { tone: "mk-tile--rose", icon: "chat" },
  sharing: { tone: "mk-tile--blue", icon: "photo" },
  links: { tone: "mk-tile--rose", icon: "link" },
  privacy: { tone: "mk-tile--mint", icon: "lock" },
  trouble: { tone: "mk-tile--butter", icon: "search" },
};

export function helpLook(categoryId: string | undefined): { tone: string; icon: IconName } {
  return (categoryId && look[categoryId]) || { tone: "mk-tile--blue", icon: "sparkle" };
}
