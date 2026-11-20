// The app's six quick reactions (EmojiCatalog.quick) and a wider set for the picker.

export const QUICK_EMOJI = ["👍", "❤️", "😂", "😮", "🔥", "👏"] as const;

export const QUICK_EMOJI_NAMES: Record<string, string> = {
  "👍": "thumbs up",
  "❤️": "red heart",
  "😂": "laughing",
  "😮": "surprised",
  "🔥": "fire",
  "👏": "clapping",
};

export interface EmojiGroup {
  name: string;
  items: [emoji: string, name: string][];
}

export const EMOJI_GROUPS: EmojiGroup[] = [
  {
    name: "Faces",
    items: [
      ["😀", "grinning"],
      ["😄", "big smile"],
      ["🥹", "touched"],
      ["😊", "smiling"],
      ["😍", "heart eyes"],
      ["🤩", "star struck"],
      ["🤔", "thinking"],
      ["🫡", "salute"],
      ["😅", "sweat smile"],
      ["🤯", "mind blown"],
      ["😬", "grimace"],
      ["🥲", "smiling tear"],
      ["😢", "crying"],
      ["😴", "sleepy"],
      ["🙃", "upside down"],
      ["😎", "cool"],
    ],
  },
  {
    name: "Hands",
    items: [
      ["🙌", "raised hands"],
      ["🙏", "thank you"],
      ["👌", "OK"],
      ["✌️", "peace"],
      ["🤞", "fingers crossed"],
      ["💪", "strong"],
      ["👀", "eyes"],
      ["👋", "wave"],
    ],
  },
  {
    name: "Things",
    items: [
      ["🎉", "party popper"],
      ["✨", "sparkles"],
      ["⭐", "star"],
      ["💯", "hundred"],
      ["✅", "tick"],
      ["❌", "cross"],
      ["❓", "question"],
      ["💡", "idea"],
      ["🚀", "rocket"],
      ["🎯", "bullseye"],
      ["📌", "pin"],
      ["⚠️", "warning"],
      ["💜", "purple heart"],
      ["💙", "blue heart"],
      ["💚", "green heart"],
      ["🍿", "popcorn"],
    ],
  },
];

export function emojiName(emoji: string): string {
  if (QUICK_EMOJI_NAMES[emoji]) return QUICK_EMOJI_NAMES[emoji];
  for (const g of EMOJI_GROUPS) for (const [e, n] of g.items) if (e === emoji) return n;
  return "reaction";
}
