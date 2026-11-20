export type HelpBlock =
  | { type: "paragraph"; text: string }
  | { type: "heading"; text: string }
  | { type: "tip"; text: string }
  | { type: "bullets"; items: string[] }
  | { type: "steps"; items: string[] };

export type HelpArticle = {
  id: string;
  category: string;
  title: string;
  summary: string;
  body: HelpBlock[];
  related?: string[];
  useCases?: string[];
};

export type HelpCategory = { id: string; title: string; systemImage?: string };

export type HelpData = { categories: HelpCategory[]; articles: HelpArticle[] };
