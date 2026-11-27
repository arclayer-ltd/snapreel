"use client";

// Comments and reactions on one video: reply, delete, block and unblock (App Review 1.2: user-generated content).
// Comments the word filter held are listed first, marked "Held", and stay hidden from viewers until approved here.
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import type { Activity, Comment, Reaction } from "@/lib/contract";
import { errorMessage, ownerApi, publicApi } from "@/lib/client/api";
import { formatTime, plural, spokenTime } from "@/lib/client/format";
import { emojiName } from "@/components/player/emoji";
import { BlockIcon, CheckIcon, CommentIcon, ReplyIcon, TrashIcon } from "@/components/player/icons";
import { usePlaybackStore } from "@/components/player/playback";
import { Avatar, Dialog, RelativeTime, Spinner, btn } from "@/components/player/ui";
import { Card } from "./kit";

type BlockTarget = { kind: "comment"; item: Comment } | { kind: "reaction"; item: Reaction };

export function ActivityPanel({
  initial,
  allowComments,
  videoId,
  slug,
  ownerName,
}: {
  initial: Activity;
  allowComments: boolean;
  videoId: string;
  slug: string;
  ownerName: string | null;
}) {
  const store = usePlaybackStore();
  const [comments, setComments] = useState(initial.comments);
  const [reactions] = useState(initial.reactions);
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [blockTarget, setBlockTarget] = useState<BlockTarget | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showAllReactions, setShowAllReactions] = useState(false);
  const [replyTo, setReplyTo] = useState<string | null>(null);
  const [blocked, setBlocked] = useState<{ comments: Set<string>; reactions: Set<string> }>({
    comments: new Set(),
    reactions: new Set(),
  });

  // Who is blocked is asked for, not remembered here, so it's right after a reload and on another device.
  const loadBlocked = useCallback(async () => {
    try {
      const b = await ownerApi.blockedIn(videoId);
      setBlocked({ comments: new Set(b.commentIds), reactions: new Set(b.reactionIds) });
    } catch {
      // Without it the list still works; it just can't say who is blocked.
    }
  }, [videoId]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- first load
    void loadBlocked();
  }, [loadBlocked]);

  const { roots, replies } = useMemo(() => {
    const roots = comments
      .filter((c) => !c.parentId)
      .sort((a, b) => Number(b.held) - Number(a.held) || b.createdAt.localeCompare(a.createdAt));
    const replies = new Map<string, Comment[]>();
    for (const c of comments) {
      if (!c.parentId) continue;
      replies.set(c.parentId, [...(replies.get(c.parentId) ?? []), c].sort((a, b) => a.createdAt.localeCompare(b.createdAt)));
    }
    return { roots, replies };
  }, [comments]);
  const heldCount = comments.filter((c) => c.held).length;

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

  async function approve(id: string) {
    setBusy(`approve:${id}`);
    setError(null);
    try {
      const approved = await ownerApi.approveComment(id);
      setComments((all) => all.map((c) => (c.id === id ? approved : c)));
      setNotice("Comment approved. Viewers can see it now.");
    } catch (err) {
      setError(errorMessage(err, "That comment wasn't approved. Try again."));
    } finally {
      setBusy(null);
    }
  }

  async function block(target: BlockTarget) {
    setBusy("block");
    setError(null);
    try {
      await ownerApi.block(target.kind === "comment" ? { commentId: target.item.id } : { reactionId: target.item.id });
      const who = target.item.authorName ?? "That viewer";
      setNotice(`${who} is blocked. They can’t comment or react on any of your videos. You can unblock them here.`);
      setBlockTarget(null);
      await loadBlocked();
    } catch (err) {
      setError(errorMessage(err, "Blocking didn't work. Try again."));
    } finally {
      setBusy(null);
    }
  }

  async function unblock(target: { commentId: string } | { reactionId: string }, name: string | null) {
    setBusy("block");
    setError(null);
    try {
      await ownerApi.unblock(target);
      setNotice(`${name ?? "That viewer"} is unblocked. They can comment and react again.`);
      await loadBlocked();
    } catch (err) {
      setError(errorMessage(err, "Unblocking didn’t work. Try again."));
    } finally {
      setBusy(null);
    }
  }

  function replied(c: Comment) {
    setComments((all) => [...all, c]);
    setReplyTo(null);
    setNotice("Your reply is on the watch page.");
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
          <button type="button" onClick={() => setNotice(null)} className="-my-3 min-h-11 px-2 text-text-2 underline-offset-2 hover:underline">
            OK
          </button>
        </p>
      )}
      {error && (
        <p role="alert" className="mb-4 rounded-2xl bg-red-soft px-3.5 py-3 text-sm text-red-text">
          {error}
        </p>
      )}

      {heldCount > 0 && (
        <p className="mb-4 rounded-2xl border border-line bg-fill/70 px-3.5 py-3 text-sm">
          <span className="font-semibold">
            {heldCount === 1 ? "1 comment is waiting for you." : `${heldCount} comments are waiting for you.`}
          </span>{" "}
          <span className="text-text-2">
            {heldCount === 1 ? "It contains" : "They contain"} words on Snapreel&rsquo;s filter list, so viewers can&rsquo;t
            see {heldCount === 1 ? "it" : "them"} until you approve {heldCount === 1 ? "it" : "them"}.
          </span>
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
            className="mt-1 min-h-11 rounded text-[13px] font-semibold text-text-2 underline-offset-2 hover:text-text hover:underline focus-visible:outline-2 focus-visible:outline-sr-red"
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
                  {blocked.reactions.has(r.id) ? (
                    <button
                      type="button"
                      onClick={() => void unblock({ reactionId: r.id }, r.authorName)}
                      disabled={busy === "block"}
                      className={btn("quiet", "sm", "h-8 text-[13px] pointer-coarse:h-11")}
                      aria-label={`Unblock ${r.authorName ?? "this viewer"}`}
                    >
                      Blocked · Unblock
                    </button>
                  ) : (
                  <button
                    type="button"
                    onClick={() => setBlockTarget({ kind: "reaction", item: r })}
                    className={btn("quiet", "sm", "h-8 text-[13px] pointer-coarse:h-11")}
                    aria-label={`Block ${r.authorName ?? "this viewer"}`}
                  >
                    <BlockIcon size={15} /> Block
                  </button>
                  )}
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
                  approving={busy === `approve:${c.id}`}
                  onSeek={(t) => store.seek(t, true)}
                  onApprove={() => approve(c.id)}
                  onAskDelete={() => setConfirmDelete(c.id)}
                  onCancelDelete={() => setConfirmDelete(null)}
                  onDelete={() => remove(c.id)}
                  onBlock={() => setBlockTarget({ kind: "comment", item: c })}
                  blocked={blocked.comments.has(c.id)}
                  onUnblock={() => void unblock({ commentId: c.id }, c.authorName)}
                  onReply={allowComments && !c.held ? () => setReplyTo(c.id) : undefined}
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
                          approving={busy === `approve:${r.id}`}
                          onSeek={(t) => store.seek(t, true)}
                          onApprove={() => approve(r.id)}
                          onAskDelete={() => setConfirmDelete(r.id)}
                          onCancelDelete={() => setConfirmDelete(null)}
                          onDelete={() => remove(r.id)}
                          onBlock={() => setBlockTarget({ kind: "comment", item: r })}
                  blocked={blocked.comments.has(r.id)}
                  onUnblock={() => void unblock({ commentId: r.id }, r.authorName)}
                  onReply={allowComments && !r.held ? () => setReplyTo(c.id) : undefined}
                        />
                      </li>
                    ))}
                  </ol>
                )}
                {replyTo === c.id && (
                  <div className="ml-4 mt-3 sm:ml-11">
                    <OwnerReply slug={slug} parent={c} ownerName={ownerName} onDone={replied} onCancel={() => setReplyTo(null)} />
                  </div>
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
  approving,
  onSeek,
  onApprove,
  onAskDelete,
  onCancelDelete,
  onDelete,
  onBlock,
  blocked,
  onUnblock,
  onReply,
}: {
  c: Comment;
  reply?: boolean;
  hasReplies?: boolean;
  confirming: boolean;
  deleting: boolean;
  approving: boolean;
  onSeek: (t: number) => void;
  onApprove: () => void;
  onAskDelete: () => void;
  onCancelDelete: () => void;
  onDelete: () => void;
  onBlock: () => void;
  blocked: boolean;
  onUnblock: () => void;
  onReply?: () => void;
}) {
  return (
    <article className={`flex gap-3 ${c.held ? "-mx-2 rounded-2xl bg-fill/70 p-2" : ""}`}>
      <Avatar name={c.authorName} size={reply ? 26 : 32} owner={c.isOwner} />
      <div className="min-w-0 flex-1">
        <header className="flex flex-wrap items-baseline gap-x-2">
          <span className="font-semibold">{c.authorName}</span>
          {c.isOwner && <span className="rounded-full bg-red-soft px-1.5 py-px text-[11px] font-semibold text-red-text">You</span>}
          {c.held && (
            <span className="rounded-full border border-line bg-surface px-1.5 py-px text-[11px] font-semibold text-text-2">
              Held
            </span>
          )}
          {blocked && (
            <span className="rounded-full border border-line bg-surface px-1.5 py-px text-[11px] font-semibold text-text-2">
              Blocked
            </span>
          )}
          <RelativeTime iso={c.createdAt} className="text-xs text-text-3" />
        </header>
        {c.held && <p className="mt-0.5 text-[13px] text-text-2">Only you can see this until you approve it.</p>}
        <p className="mt-1 whitespace-pre-wrap break-words text-[15px] leading-relaxed">
          {c.atS !== null && (
            <button
              type="button"
              onClick={() => onSeek(c.atS!)}
              className="mr-1.5 inline-flex rounded-md bg-red-soft px-1.5 py-px align-middle pointer-coarse:px-2.5 pointer-coarse:py-1.5 text-[13px] font-semibold tabular-nums text-red-text hover:brightness-95 focus-visible:outline-2 focus-visible:outline-sr-red"
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
              <button type="button" onClick={onDelete} disabled={deleting} className={btn("danger", "sm", "h-8 pointer-coarse:h-11")}>
                {deleting ? <Spinner size={14} /> : "Delete"}
              </button>
              <button type="button" onClick={onCancelDelete} className={btn("quiet", "sm", "h-8 pointer-coarse:h-11")}>
                Cancel
              </button>
            </>
          ) : (
            <>
              {c.held && (
                <button type="button" onClick={onApprove} disabled={approving} className={btn("secondary", "sm", "h-8 text-[13px] pointer-coarse:h-11")}>
                  {approving ? <Spinner size={14} /> : <CheckIcon size={15} />} Approve
                </button>
              )}
              <button type="button" onClick={onAskDelete} className={btn("quiet", "sm", "h-8 text-[13px] pointer-coarse:h-11")}>
                <TrashIcon size={15} /> Delete
              </button>
              {onReply && (
                <button type="button" onClick={onReply} className={btn("quiet", "sm", "h-8 text-[13px] pointer-coarse:h-11")}>
                  <ReplyIcon size={15} /> Reply
                </button>
              )}
              {!c.isOwner &&
                (blocked ? (
                  <button type="button" onClick={onUnblock} className={btn("quiet", "sm", "h-8 text-[13px] pointer-coarse:h-11")}>
                    Unblock
                  </button>
                ) : (
                  <button type="button" onClick={onBlock} className={btn("quiet", "sm", "h-8 text-[13px] pointer-coarse:h-11")}>
                    <BlockIcon size={15} /> Block
                  </button>
                ))}
            </>
          )}
        </div>
      </div>
    </article>
  );
}

/** The owner answers a viewer: posted like any comment, under the owner's name, marked as the creator. */
function OwnerReply({
  slug,
  parent,
  ownerName,
  onDone,
  onCancel,
}: {
  slug: string;
  parent: Comment;
  ownerName: string | null;
  onDone: (c: Comment) => void;
  onCancel: () => void;
}) {
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send(e: FormEvent) {
    e.preventDefault();
    const text = body.trim();
    if (!text) return;
    setBusy(true);
    setError(null);
    try {
      // An empty name makes the server use the account's name.
      const c = await publicApi.comment(slug, { name: ownerName ?? "", body: text, atS: null, parentId: parent.id, website: "" });
      onDone(c);
    } catch (err) {
      setError(
        errorMessage(err, "Your reply didn’t post. Try again.").replace(
          "Add your name.",
          "Add your name in Account first, so viewers know who replied.",
        ),
      );
      setBusy(false);
    }
  }

  return (
    <form onSubmit={send} className="space-y-2">
      <label className="sr-only" htmlFor={`reply-${parent.id}`}>
        Reply to {parent.authorName}
      </label>
      <textarea
        id={`reply-${parent.id}`}
        autoFocus
        value={body}
        onChange={(e) => setBody(e.target.value)}
        rows={2}
        maxLength={1000}
        placeholder={`Reply to ${parent.authorName}…`}
        className="block w-full resize-none rounded-2xl border border-line bg-canvas px-3 py-2.5 text-base leading-relaxed placeholder:text-text-3 focus:border-sr-red focus:outline-none focus:ring-2 focus:ring-sr-red/25"
      />
      {error && (
        <p role="alert" className="text-sm text-red-text">
          {error}
        </p>
      )}
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onCancel} className={btn("quiet", "sm")}>
          Cancel
        </button>
        <button type="submit" disabled={busy || !body.trim()} className={btn("primary", "sm", "min-w-[4.5rem]")}>
          {busy ? <Spinner size={15} /> : "Reply"}
        </button>
      </div>
    </form>
  );
}
