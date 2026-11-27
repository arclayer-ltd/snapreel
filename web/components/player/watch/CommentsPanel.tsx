"use client";

// Comments pinned to moments in the video, with replies. A viewer's name is asked once and remembered
// on this device. `website` is the contract's honeypot and stays empty for people. A comment the server's word
// filter holds isn't shown; its writer is told it waits for the owner.
import { useEffect, useId, useMemo, useRef, useState, type FormEvent } from "react";
import type { Comment } from "@/lib/contract";
import { errorMessage, publicApi } from "@/lib/client/api";
import { formatTime, spokenTime } from "@/lib/client/format";
import { ClockIcon, CommentIcon, ReplyIcon, TrashIcon } from "../icons";
import { usePlaybackSecond, usePlaybackStore } from "../playback";
import { Avatar, RelativeTime, Spinner, btn } from "../ui";
import { forgetMine, isMine, readViewerName, rememberMine, saveViewerName } from "./viewerName";

export function CommentsPanel({
  slug,
  comments,
  loading,
  allowComments,
  ownerName = null,
  viewerIsOwner = false,
  closedMessage = "Comments are turned off for this video.",
  onPosted,
  onDeleted,
  onSeek,
}: {
  slug: string;
  comments: Comment[];
  loading: boolean;
  allowComments: boolean;
  ownerName?: string | null;
  /** The signed-in owner is watching their own link: they post under their own name. */
  viewerIsOwner?: boolean;
  closedMessage?: string;
  onPosted: (c: Comment) => void;
  onDeleted: (id: string) => void;
  onSeek: (t: number) => void;
}) {
  const [replyTo, setReplyTo] = useState<string | null>(null);
  // Comments written in this browser (kept on the device), plus the owner's own when they are the one watching.
  const [mineIds, setMineIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage is only readable after mount
    setMineIds(new Set(comments.filter((c) => isMine(c.id)).map((c) => c.id)));
  }, [comments]);
  const mine = (c: Comment) => mineIds.has(c.id) || (viewerIsOwner && c.isOwner);
  const posted = (c: Comment) => {
    rememberMine(c.id);
    onPosted(c);
  };
  const deleted = (id: string) => {
    forgetMine(id);
    onDeleted(id);
  };

  const { roots, replies } = useMemo(() => {
    const roots = comments
      .filter((c) => !c.parentId)
      .sort((a, b) => (a.atS ?? Infinity) - (b.atS ?? Infinity) || a.createdAt.localeCompare(b.createdAt));
    const replies = new Map<string, Comment[]>();
    for (const c of comments) {
      if (!c.parentId) continue;
      const list = replies.get(c.parentId) ?? [];
      list.push(c);
      replies.set(c.parentId, list);
    }
    for (const list of replies.values()) list.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    return { roots, replies };
  }, [comments]);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {allowComments ? (
        <div className="order-first border-b border-line p-4 lg:order-last lg:border-b-0 lg:border-t">
          <Composer slug={slug} ownerName={ownerName} viewerIsOwner={viewerIsOwner} onPosted={posted} />
        </div>
      ) : (
        <p className="order-first border-b border-line px-4 py-3 text-sm text-text-2 lg:order-last lg:border-b-0 lg:border-t">
          {closedMessage}
        </p>
      )}

      <div className="min-h-0 flex-1 lg:overflow-y-auto">
        {loading ? (
          <div className="flex items-center gap-2 p-5 text-sm text-text-2">
            <Spinner size={16} /> Loading comments…
          </div>
        ) : roots.length === 0 ? (
          // Comments off and none there: the line above says it all.
          !allowComments ? null : <div className="flex flex-col items-center gap-2 px-6 py-10 text-center">
            <span className="flex h-11 w-11 items-center justify-center rounded-full bg-fill text-text-2">
              <CommentIcon size={20} />
            </span>
            <p className="font-medium">No comments yet</p>
            <p className="max-w-[16rem] text-sm text-text-2">Yours gets pinned to the moment you&rsquo;re watching.</p>
          </div>
        ) : (
          <ol className="divide-y divide-line">
            {roots.map((c) => (
              <li key={c.id} className="px-4 py-4">
                <CommentItem
                  comment={c}
                  slug={slug}
                  onSeek={onSeek}
                  onReply={allowComments ? () => setReplyTo(c.id) : undefined}
                  onDeleted={mine(c) ? deleted : undefined}
                />
                {(replies.get(c.id)?.length ?? 0) > 0 && (
                  <ol className="mt-3 space-y-3 border-l-2 border-line pl-4 sm:ml-11">
                    {replies.get(c.id)!.map((r) => (
                      <li key={r.id}>
                        <CommentItem comment={r} slug={slug} onSeek={onSeek} small onDeleted={mine(r) ? deleted : undefined} />
                      </li>
                    ))}
                  </ol>
                )}
                {replyTo === c.id && (
                  <div className="mt-3 sm:ml-11">
                    <Composer
                      slug={slug}
                      ownerName={ownerName}
                      viewerIsOwner={viewerIsOwner}
                      parent={c}
                      onPosted={(c) => {
                        posted(c);
                        setReplyTo(null);
                      }}
                      onCancel={() => setReplyTo(null)}
                    />
                  </div>
                )}
              </li>
            ))}
          </ol>
        )}
      </div>
    </div>
  );
}

function CommentItem({
  comment,
  slug,
  onSeek,
  onReply,
  onDeleted,
  small = false,
}: {
  comment: Comment;
  slug: string;
  onSeek: (t: number) => void;
  onReply?: () => void;
  /** Set for the viewer's own comments: they can take them back. */
  onDeleted?: (id: string) => void;
  small?: boolean;
}) {
  const [confirming, setConfirming] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove() {
    setDeleting(true);
    setError(null);
    try {
      await publicApi.deleteComment(slug, comment.id);
      onDeleted?.(comment.id);
    } catch (err) {
      setDeleting(false);
      setError(errorMessage(err, "It wasn’t deleted. Try again."));
    }
  }

  return (
    <article className="flex gap-3">
      <Avatar name={comment.authorName} size={small ? 26 : 32} owner={comment.isOwner} />
      <div className="min-w-0 flex-1">
        <header className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
          <span className="font-semibold leading-tight">{comment.authorName}</span>
          {comment.isOwner && (
            <span className="rounded-full bg-red-soft px-1.5 py-px text-[11px] font-semibold text-red-text">Creator</span>
          )}
          <RelativeTime iso={comment.createdAt} className="text-xs text-text-3" />
        </header>
        <p className="mt-1 whitespace-pre-wrap break-words text-[15px] leading-relaxed">
          {comment.atS !== null && (
            <button
              type="button"
              onClick={() => onSeek(comment.atS!)}
              className="mr-1.5 inline-flex translate-y-[-1px] items-center rounded-md bg-red-soft px-1.5 py-px align-middle pointer-coarse:px-2.5 pointer-coarse:py-1.5 text-[13px] font-semibold tabular-nums text-red-text hover:brightness-95 focus-visible:outline-2 focus-visible:outline-sr-red"
              aria-label={`Play from ${spokenTime(comment.atS)}`}
            >
              {formatTime(comment.atS)}
            </button>
          )}
          {comment.body}
        </p>
        {(onReply || onDeleted) && (
          <div className="-ml-2 mt-1 flex flex-wrap items-center gap-1">
            {confirming ? (
              <>
                <span className="px-2 text-[13px] text-text-2">Delete your {small ? "reply" : "comment"}?</span>
                <button type="button" onClick={() => void remove()} disabled={deleting} className={btn("danger", "sm", "h-8 pointer-coarse:h-10")}>
                  {deleting ? <Spinner size={14} /> : "Delete"}
                </button>
                <button type="button" onClick={() => setConfirming(false)} className={btn("quiet", "sm", "h-8 pointer-coarse:h-10")}>
                  Cancel
                </button>
              </>
            ) : (
              <>
                {onReply && (
                  <button type="button" onClick={onReply} className={ACTION}>
                    <ReplyIcon size={15} /> Reply
                  </button>
                )}
                {onDeleted && (
                  <button type="button" onClick={() => setConfirming(true)} className={ACTION}>
                    <TrashIcon size={15} /> Delete
                  </button>
                )}
              </>
            )}
          </div>
        )}
        {error && (
          <p role="alert" className="mt-1 text-sm text-red-text">
            {error}
          </p>
        )}
      </div>
    </article>
  );
}

const ACTION =
  "inline-flex h-8 items-center gap-1.5 rounded-full px-2 text-[13px] font-semibold text-text-2 hover:bg-fill hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red pointer-coarse:h-10";

const draftKey = (slug: string) => `sr_draft_${slug}`;

function Composer({
  slug,
  ownerName,
  viewerIsOwner = false,
  parent,
  onPosted,
  onCancel,
}: {
  slug: string;
  ownerName: string | null;
  viewerIsOwner?: boolean;
  parent?: Comment;
  onPosted: (c: Comment) => void;
  onCancel?: () => void;
}) {
  const store = usePlaybackStore();
  const second = usePlaybackSecond();
  const ids = useId();
  const textRef = useRef<HTMLTextAreaElement>(null);
  const nameRef = useRef<HTMLInputElement>(null);
  const [name, setName] = useState("");
  const [knownName, setKnownName] = useState(false);
  const [askName, setAskName] = useState(false);
  const [body, setBody] = useState("");
  const [pinTime, setPinTime] = useState(true);
  // The moment is taken when typing starts, so it doesn't run on while the comment is written.
  const [pinnedAt, setPinnedAt] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [heldNotice, setHeldNotice] = useState(false);
  const [website, setWebsite] = useState("");

  // The owner posts under their own name; anyone else under the one they gave before on this device.
  const ownName = viewerIsOwner && ownerName ? ownerName : null;
  useEffect(() => {
    const stored = ownName ?? readViewerName();
    /* eslint-disable react-hooks/set-state-in-effect -- localStorage is only readable after mount */
    setName(stored);
    setKnownName(!!stored);
    // A half-written comment survives a reload (replies are short and aren't kept).
    if (!parent) {
      try {
        const draft = localStorage.getItem(draftKey(slug));
        if (draft) setBody(draft);
      } catch {}
    }
    /* eslint-enable react-hooks/set-state-in-effect */
    if (parent) textRef.current?.focus();
  }, [parent, slug, ownName]);

  function changeBody(next: string) {
    setBody(next);
    if (!next.trim()) setPinnedAt(null);
    else if (pinnedAt === null) setPinnedAt(Math.round(store.getSnapshot().time * 10) / 10);
    if (parent) return;
    try {
      if (next.trim()) localStorage.setItem(draftKey(slug), next);
      else localStorage.removeItem(draftKey(slug));
    } catch {}
  }

  const showName = askName || (!knownName && body.trim().length > 0);
  const shownAt = pinnedAt ?? second;

  async function submit(e: FormEvent | { preventDefault(): void }) {
    e.preventDefault();
    const text = body.trim();
    if (!text) {
      textRef.current?.focus();
      return;
    }
    const who = name.trim();
    if (!who) {
      setAskName(true);
      setError("Add your name so people know who commented.");
      requestAnimationFrame(() => nameRef.current?.focus());
      return;
    }
    setBusy(true);
    setError(null);
    setHeldNotice(false);
    try {
      const atS = parent ? null : pinTime ? (pinnedAt ?? Math.round(store.getSnapshot().time * 10) / 10) : null;
      const posted = await publicApi.comment(slug, { name: who, body: text, atS, parentId: parent?.id ?? null, website });
      if (!ownName) saveViewerName(who);
      setKnownName(true);
      setAskName(false);
      changeBody("");
      if (posted.held) setHeldNotice(true);
      else onPosted(posted);
    } catch (err) {
      setError(errorMessage(err, "Your comment didn't post. Try again."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="space-y-2" noValidate>
      <div className="rounded-2xl border border-line bg-canvas focus-within:border-sr-red focus-within:ring-2 focus-within:ring-sr-red/25">
        <label htmlFor={`${ids}-body`} className="sr-only">
          {parent ? `Reply to ${parent.authorName}` : "Add a comment"}
        </label>
        <textarea
          ref={textRef}
          id={`${ids}-body`}
          value={body}
          onChange={(e) => changeBody(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) void submit(e);
          }}
          rows={parent ? 2 : 2}
          maxLength={1000}
          placeholder={parent ? `Reply to ${parent.authorName}…` : "Add a comment…"}
          className="block w-full resize-none bg-transparent px-3 pb-1 pt-2.5 text-base leading-relaxed placeholder:text-text-3 focus:outline-none"
        />
        {/* Under the text, so the line being typed never moves when the name is asked for. */}
        {showName && (
          <div className="mx-3 mb-2 border-t border-line pt-2">
            <label htmlFor={`${ids}-name`} className="block text-[13px] font-medium text-text-2">
              Your name <span className="font-normal text-text-3">(remembered on this device)</span>
            </label>
            <input
              ref={nameRef}
              id={`${ids}-name`}
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") void submit(e);
              }}
              maxLength={60}
              autoComplete="name"
              enterKeyHint="send"
              aria-invalid={!!error && !name.trim()}
              className="h-11 w-full bg-transparent text-base placeholder:text-text-3 focus:outline-none"
              placeholder="Add your name"
            />
          </div>
        )}
        <div className="flex items-center gap-2 px-2 pb-2">
          {!parent && (
            <button
              type="button"
              onClick={() => {
                // Turning it back on takes the moment now.
                if (!pinTime) setPinnedAt(body.trim() ? Math.round(store.getSnapshot().time * 10) / 10 : null);
                setPinTime((p) => !p);
              }}
              aria-pressed={pinTime}
              className={`inline-flex h-8 items-center gap-1.5 rounded-full px-2.5 text-[13px] font-semibold tabular-nums pointer-coarse:h-11 transition-colors focus-visible:outline-2 focus-visible:outline-sr-red motion-reduce:transition-none ${
                pinTime ? "bg-red-soft text-red-text" : "text-text-2 hover:bg-fill"
              }`}
              title={pinTime ? "Pinned to this moment. Tap to post without a time." : "Tap to pin it to this moment"}
            >
              <ClockIcon size={14} />
              {pinTime ? `At ${formatTime(shownAt)}` : "No time"}
            </button>
          )}
          {body.length > 900 && <span className="text-xs tabular-nums text-text-3">{1000 - body.length} left</span>}
          <div className="ml-auto flex items-center gap-1">
            {onCancel && (
              <button type="button" onClick={onCancel} className={btn("quiet", "sm")}>
                Cancel
              </button>
            )}
            <button type="submit" disabled={busy || !body.trim()} className={btn("primary", "sm", "min-w-[4.5rem]")}>
              {busy ? <Spinner size={15} /> : parent ? "Reply" : "Post"}
            </button>
          </div>
        </div>
      </div>
      {/* Honeypot: hidden from people and screen readers. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-px w-px overflow-hidden">
        <label>
          Website
          <input tabIndex={-1} autoComplete="off" value={website} onChange={(e) => setWebsite(e.target.value)} name="website" />
        </label>
      </div>
      {knownName && !showName && (
        <p className="flex flex-wrap items-center gap-x-1 text-[13px] text-text-2">
          {ownName ? (
            <>Posting as {ownName}, the creator</>
          ) : (
            <>
              Posting as <span className="font-medium text-text">{name}</span>
              <span aria-hidden="true">·</span>
              <button
                type="button"
                onClick={() => {
                  setAskName(true);
                  requestAnimationFrame(() => nameRef.current?.focus());
                }}
                className="inline-flex min-h-8 items-center rounded font-semibold text-red-text underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-sr-red pointer-coarse:min-h-10"
              >
                Change name
              </button>
            </>
          )}
        </p>
      )}
      {error && (
        <p role="alert" className="text-sm text-red-text">
          {error}
        </p>
      )}
      {heldNotice && (
        <p role="status" className="rounded-xl bg-fill px-3 py-2 text-sm text-text-2">
          Thanks. Your comment will show here once {ownerName || "the video's owner"} approves it.
        </p>
      )}
    </form>
  );
}
