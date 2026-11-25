"use client";

// Comments pinned to moments in the video, with replies. A viewer's name is asked once and remembered
// on this device. `website` is the contract's honeypot and stays empty for people. A comment the server's word
// filter holds isn't shown; its writer is told it waits for the owner.
import { useEffect, useId, useMemo, useRef, useState, type FormEvent } from "react";
import type { Comment } from "@/lib/contract";
import { errorMessage, publicApi } from "@/lib/client/api";
import { formatTime, spokenTime } from "@/lib/client/format";
import { ClockIcon, CommentIcon, ReplyIcon } from "../icons";
import { usePlaybackSecond, usePlaybackStore } from "../playback";
import { Avatar, RelativeTime, Spinner, btn } from "../ui";
import { readViewerName, saveViewerName } from "./viewerName";

export function CommentsPanel({
  slug,
  comments,
  loading,
  allowComments,
  ownerName = null,
  closedMessage = "Comments are turned off for this video.",
  onPosted,
  onSeek,
}: {
  slug: string;
  comments: Comment[];
  loading: boolean;
  allowComments: boolean;
  ownerName?: string | null;
  closedMessage?: string;
  onPosted: (c: Comment) => void;
  onSeek: (t: number) => void;
}) {
  const [replyTo, setReplyTo] = useState<string | null>(null);

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
          <Composer slug={slug} ownerName={ownerName} onPosted={onPosted} />
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
          <div className="flex flex-col items-center gap-2 px-6 py-10 text-center">
            <span className="flex h-11 w-11 items-center justify-center rounded-full bg-fill text-text-2">
              <CommentIcon size={20} />
            </span>
            <p className="font-medium">No comments yet</p>
            {allowComments && (
              <p className="max-w-[16rem] text-sm text-text-2">Yours gets pinned to the moment you&rsquo;re watching.</p>
            )}
          </div>
        ) : (
          <ol className="divide-y divide-line">
            {roots.map((c) => (
              <li key={c.id} className="px-4 py-4">
                <CommentItem comment={c} onSeek={onSeek} onReply={allowComments ? () => setReplyTo(c.id) : undefined} />
                {(replies.get(c.id)?.length ?? 0) > 0 && (
                  <ol className="mt-3 space-y-3 border-l-2 border-line pl-4 sm:ml-11">
                    {replies.get(c.id)!.map((r) => (
                      <li key={r.id}>
                        <CommentItem comment={r} onSeek={onSeek} small />
                      </li>
                    ))}
                  </ol>
                )}
                {replyTo === c.id && (
                  <div className="mt-3 sm:ml-11">
                    <Composer
                      slug={slug}
                      ownerName={ownerName}
                      parent={c}
                      onPosted={(posted) => {
                        onPosted(posted);
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
  onSeek,
  onReply,
  small = false,
}: {
  comment: Comment;
  onSeek: (t: number) => void;
  onReply?: () => void;
  small?: boolean;
}) {
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
              className="mr-1.5 inline-flex translate-y-[-1px] items-center rounded-md bg-red-soft px-1.5 py-px align-middle text-[13px] font-semibold tabular-nums text-red-text hover:brightness-95 focus-visible:outline-2 focus-visible:outline-sr-red"
              aria-label={`Play from ${spokenTime(comment.atS)}`}
            >
              {formatTime(comment.atS)}
            </button>
          )}
          {comment.body}
        </p>
        {onReply && (
          <button
            type="button"
            onClick={onReply}
            className="-ml-2 mt-1 inline-flex h-8 items-center pointer-coarse:h-10 gap-1.5 rounded-full px-2 text-[13px] font-semibold text-text-2 hover:bg-fill hover:text-text focus-visible:outline-2 focus-visible:outline-sr-red"
          >
            <ReplyIcon size={15} /> Reply
          </button>
        )}
      </div>
    </article>
  );
}

function Composer({
  slug,
  ownerName,
  parent,
  onPosted,
  onCancel,
}: {
  slug: string;
  ownerName: string | null;
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
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [heldNotice, setHeldNotice] = useState(false);
  const [website, setWebsite] = useState("");

  useEffect(() => {
    const stored = readViewerName();
    /* eslint-disable react-hooks/set-state-in-effect -- localStorage is only readable after mount */
    setName(stored);
    setKnownName(!!stored);
    /* eslint-enable react-hooks/set-state-in-effect */
    if (parent) textRef.current?.focus();
  }, [parent]);

  const showName = askName || (!knownName && body.trim().length > 0);

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
      const atS = parent ? null : pinTime ? Math.round(store.getSnapshot().time * 10) / 10 : null;
      const posted = await publicApi.comment(slug, { name: who, body: text, atS, parentId: parent?.id ?? null, website });
      saveViewerName(who);
      setKnownName(true);
      setAskName(false);
      setBody("");
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
          onChange={(e) => setBody(e.target.value)}
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
              onClick={() => setPinTime((p) => !p)}
              aria-pressed={pinTime}
              className={`inline-flex h-8 items-center gap-1.5 rounded-full px-2.5 text-[13px] font-semibold tabular-nums pointer-coarse:h-11 transition-colors focus-visible:outline-2 focus-visible:outline-sr-red motion-reduce:transition-none ${
                pinTime ? "bg-red-soft text-red-text" : "text-text-2 hover:bg-fill"
              }`}
              title={pinTime ? "Pinned to this moment. Tap to post without a time." : "Tap to pin it to this moment"}
            >
              <ClockIcon size={14} />
              {pinTime ? `At ${formatTime(second)}` : "No time"}
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
