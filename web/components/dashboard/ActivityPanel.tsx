"use client";

// Comments and reactions on one video, with delete and block (App Review 1.2: user-generated content).
import { useMemo, useState } from "react";
import type { Activity, Comment, Reaction } from "@/lib/contract";
import { errorMessage, ownerApi } from "@/lib/client/api";
import { formatTime, plural, spokenTime } from "@/lib/client/format";
import { emojiName } from "@/components/player/emoji";
import { BlockIcon, CheckIcon, CommentIcon, TrashIcon } from "@/components/player/icons";
import { usePlaybackStore } from "@/components/player/playback";
import { Avatar, Dialog, RelativeTime, Spinner, btn } from "@/components/player/ui";
import { Card } from "./kit";

type BlockTarget = { kind: "comment"; item: Comment } | { kind: "reaction"; item: Reaction };

export function ActivityPanel({ initial, allowComments }: { initial: Activity; allowComments: boolean }) {
  const store = usePlaybackStore();
  const [comments, setComments] = useState(initial.comments);
  const [reactions] = useState(initial.reactions);
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [blockTarget, setBlockTarget] = useState<BlockTarget | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showAllReactions, setShowAllReactions] = useState(false);

  const { roots, replies } = useMemo(() => {
    const roots = comments.filter((c) => !c.parentId).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    const replies = new Map<string, Comment[]>();
    for (const c of comments) {
      if (!c.parentId) continue;
      replies.set(c.parentId, [...(replies.get(c.parentId) ?? []), c].sort((a, b) => a.createdAt.localeCompare(b.createdAt)));
    }
    return { roots, replies };
  }, [comments]);

  const tally = useMemo(() => {
    const m = new Map<string, number>();
    for (const r of reactions) m.set(r.emoji, (m.get(r.emoji) ?? 0) + 1);
    return [...m.entries()].sort((a, b) => b[1] - a[1]);
  }, [reactions]);

  async function remove(id: string) {
    setBusy(id);
    setError(null);
    try {
      await ownerApi.deleteComment(id);
      setComments((all) => all.filter((c) => c.id !== id && c.parentId !== id));
      setNotice("Comment deleted.");
    } catch (err) {
      setError(errorMessage(err, "That comment wasn't deleted. Try again."));
    } finally {
      setBusy(null);
      setConfirmDelete(null);
    }
  }

  async function block(target: BlockTarget) {
    setBusy("block");
    setError(null);
    try {
      await ownerApi.block(target.kind === "comment" ? { commentId: target.item.id } : { reactionId: target.item.id });
      const who = target.item.authorName ?? "That viewer";
      setNotice(`${who} is blocked. They can't comment or react on any of your videos.`);
      setBlockTarget(null);
    } catch (err) {
      setError(errorMessage(err, "Blocking didn't work. Try again."));
    } finally {
      setBusy(null);
    }
  }

  const reactionList = [...reactions].sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  return (
    <Card
      title="Comments and reactions"
      id="activity"
      description={allowComments ? undefined : "Comments are turned off, so viewers can't add new ones."}
    >
      {notice && (
        <p role="status" className="mb-4 flex items-start gap-2 rounded-2xl bg-fill px-3.5 py-3 text-sm">
          <CheckIcon size={16} className="mt-0.5 shrink-0 text-red-text" />
          <span className="flex-1">{notice}</span>
          <button type="button" onClick={() => setNotice(null)} className="text-text-2 underline-offset-2 hover:underline">
            OK
          </button>
        </p>
      )}
      {error && (
        <p role="alert" className="mb-4 rounded-2xl bg-red-soft px-3.5 py-3 text-sm text-red-text">
          {error}
        </p>
      )}

      {tally.length > 0 && (
        <div className="mb-5">
          <ul className="flex flex-wrap gap-2" aria-label="Reactions">
            {tally.map(([emoji, n]) => (
              <li
                key={emoji}
                className="inline-flex items-center gap-1.5 rounded-full bg-fill px-3 py-1.5 text-sm"
                aria-label={`${n} ${emojiName(emoji)}`}
              >
                <span className="text-base leading-none" aria-hidden="true">
                  {emoji}
                </span>
                <span className="font-semibold tabular-nums" aria-hidden="true">
                  {n}
                </span>
              </li>
            ))}
          </ul>
          <button
            type="button"
            onClick={() => setShowAllReactions((s) => !s)}
            aria-expanded={showAllReactions}
            className="mt-2 rounded text-[13px] font-semibold text-text-2 underline-offset-2 hover:text-text hover:underline focus-visible:outline-2 focus-visible:outline-sr-red"
          >
            {showAllReactions ? "Hide who reacted" : `See who reacted (${reactions.length})`}
          </button>
          {showAllReactions && (
            <ul className="mt-2 divide-y divide-line rounded-2xl border border-line">
              {reactionList.map((r) => (
                <li key={r.id} className="flex items-center gap-3 px-3 py-2 text-sm">
                  <span className="text-lg leading-none" aria-label={emojiName(r.emoji)}>
                    {r.emoji}
                  </span>
                  <span className="min-w-0 flex-1 truncate">
                    {r.authorName ?? "Anonymous"}
                    <span className="text-text-3"> at {formatTime(r.atS)}</span>
                  </span>
                  <button
                    type="button"
                    onClick={() => setBlockTarget({ kind: "reaction", item: r })}
                    className={btn("quiet", "sm", "h-8 text-[13px]")}
                    aria-label={`Block ${r.authorName ?? "this viewer"}`}
                  >
                    <BlockIcon size={15} /> Block
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {roots.length === 0 ? (
        <div className="flex items-center gap-3 rounded-2xl bg-fill/70 px-4 py-5 text-sm text-text-2">
          <CommentIcon size={18} />
          No comments yet. You&rsquo;ll get a notification on your iPhone when someone comments.
        </div>
      ) : (
        <>
          <p className="mb-2 text-sm text-text-2">{plural(comments.length, "comment")}, newest first</p>
          <ol className="divide-y divide-line">
            {roots.map((c) => (
              <li key={c.id} className="py-4 first:pt-1">
                <CommentRow
                  c={c}
                  hasReplies={(replies.get(c.id)?.length ?? 0) > 0}
                  confirming={confirmDelete === c.id}
                  deleting={busy === c.id}
                  onSeek={(t) => store.seek(t, true)}
                  onAskDelete={() => setConfirmDelete(c.id)}
                  onCancelDelete={() => setConfirmDelete(null)}
                  onDelete={() => remove(c.id)}
                  onBlock={() => setBlockTarget({ kind: "comment", item: c })}
                />
                {(replies.get(c.id)?.length ?? 0) > 0 && (
                  <ol className="ml-4 mt-3 space-y-3 border-l-2 border-line pl-4 sm:ml-11">
                    {replies.get(c.id)!.map((r) => (
                      <li key={r.id}>
                        <CommentRow
                  c={r}
                  reply
                  hasReplies={(replies.get(r.id)?.length ?? 0) > 0}
                  confirming={confirmDelete === r.id}
                  deleting={busy === r.id}
                  onSeek={(t) => store.seek(t, true)}
                  onAskDelete={() => setConfirmDelete(r.id)}
                  onCancelDelete={() => setConfirmDelete(null)}
                  onDelete={() => remove(r.id)}
                  onBlock={() => setBlockTarget({ kind: "comment", item: r })}
                />
                      </li>
                    ))}
                  </ol>
                )}
              </li>
            ))}
          </ol>
        </>
      )}

      <Dialog open={blockTarget !== null} onClose={() => setBlockTarget(null)} title={`Block ${blockTarget?.item.authorName ?? "this viewer"}?`}>
        <p className="text-[15px] leading-relaxed text-text-2">
          They won&rsquo;t be able to comment or react on any of your videos. What they already posted stays until you delete
          it. They aren&rsquo;t told.
        </p>
        <div className="mt-6 flex justify-end gap-2">
          <button type="button" className={btn("ghost")} onClick={() => setBlockTarget(null)}>
            Cancel
          </button>
          <button
            type="button"
            className={btn("primary", "md", "min-w-[6rem]")}
            disabled={busy === "block"}
            onClick={() => blockTarget && block(blockTarget)}
          >
            {busy === "block" ? <Spinner size={16} /> : "Block"}
          </button>
        </div>
      </Dialog>
    </Card>
  );
}

function CommentRow({
c,
reply = false,
hasReplies = false,
confirming,
deleting,
onSeek,
onAskDelete,
onCancelDelete,
onDelete,
onBlock,
}: {
c: Comment;
reply?: boolean;
hasReplies?: boolean;
confirming: boolean;
deleting: boolean;
onSeek: (t: number) => void;
onAskDelete: () => void;
onCancelDelete: () => void;
onDelete: () => void;
onBlock: () => void;
}) {
  return (
    <article className="flex gap-3">
      <Avatar name={c.authorName} size={reply ? 26 : 32} owner={c.isOwner} />
      <div className="min-w-0 flex-1">
        <header className="flex flex-wrap items-baseline gap-x-2">
          <span className="font-semibold">{c.authorName}</span>
          {c.isOwner && <span className="rounded-full bg-red-soft px-1.5 py-px text-[11px] font-semibold text-red-text">You</span>}
          <RelativeTime iso={c.createdAt} className="text-xs text-text-3" />
        </header>
        <p className="mt-1 whitespace-pre-wrap break-words text-[15px] leading-relaxed">
          {c.atS !== null && (
            <button
              type="button"
              onClick={() => onSeek(c.atS!)}
              className="mr-1.5 inline-flex rounded-md bg-red-soft px-1.5 py-px align-middle text-[13px] font-semibold tabular-nums text-red-text hover:brightness-95 focus-visible:outline-2 focus-visible:outline-sr-red"
              aria-label={`Play from ${spokenTime(c.atS)}`}
            >
              {formatTime(c.atS)}
            </button>
          )}
          {c.body}
        </p>
        <div className="-ml-2 mt-1 flex flex-wrap items-center gap-1">
          {confirming ? (
            <>
              <span className="px-2 text-[13px] text-text-2">Delete this comment{hasReplies ? " and its replies" : ""}?</span>
              <button type="button" onClick={onDelete} disabled={deleting} className={btn("danger", "sm", "h-8")}>
                {deleting ? <Spinner size={14} /> : "Delete"}
              </button>
              <button type="button" onClick={onCancelDelete} className={btn("quiet", "sm", "h-8")}>
                Cancel
              </button>
            </>
          ) : (
            <>
              <button type="button" onClick={onAskDelete} className={btn("quiet", "sm", "h-8 text-[13px]")}>
                <TrashIcon size={15} /> Delete
              </button>
              {!c.isOwner && (
                <button
                  type="button"
                  onClick={onBlock}
                  className={btn("quiet", "sm", "h-8 text-[13px]")}
                >
                  <BlockIcon size={15} /> Block
                </button>
              )}
            </>
          )}
        </div>
      </div>
    </article>
  );
}
