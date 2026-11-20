import type { HelpBlock } from "./content-types";
import { inline } from "./markdown";

/** Renders one help article's blocks, the same block types the app's help centre uses. */
export function HelpBody({ blocks }: { blocks: HelpBlock[] }) {
  return (
    <div className="mk-prose">
      {blocks.map((b, i) => {
        const k = `h${i}`;
        switch (b.type) {
          case "paragraph":
            return <p key={k}>{inline(b.text, k)}</p>;
          case "heading":
            return <h2 key={k}>{inline(b.text, k)}</h2>;
          case "bullets":
            return (
              <ul key={k}>
                {b.items.map((it, j) => (
                  <li key={j}>{inline(it, `${k}-${j}`)}</li>
                ))}
              </ul>
            );
          case "steps":
            return (
              <ol key={k} className="!list-none !pl-0 space-y-3">
                {b.items.map((it, j) => (
                  <li key={j} className="flex items-start gap-3">
                    <span className="grid grid-cols-1 size-7 shrink-0 place-items-center rounded-full bg-red-soft text-sm font-semibold text-red-text">
                      {j + 1}
                    </span>
                    <span className="pt-0.5">{inline(it, `${k}-${j}`)}</span>
                  </li>
                ))}
              </ol>
            );
          case "tip":
            return (
              <div key={k} className="flex gap-3 rounded-2xl bg-red-soft px-4 py-3.5 text-[0.98rem] text-text">
                <svg aria-hidden="true" viewBox="0 0 24 24" width="20" height="20" className="mt-0.5 shrink-0 text-red-text" fill="currentColor">
                  <path d="M12 2a7 7 0 0 0-4 12.74V17a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1v-2.26A7 7 0 0 0 12 2Zm-2 18h4a1 1 0 0 1 0 2h-4a1 1 0 0 1 0-2Z" />
                </svg>
                <p className="!mt-0">
                  <span className="sr-only">Tip: </span>
                  {inline(b.text, k)}
                </p>
              </div>
            );
          default:
            return null;
        }
      })}
    </div>
  );
}
