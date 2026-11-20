import "server-only";
import { LEGAL_ADDRESS, LEGAL_ENTITY } from "../legal-entity";
import { EMAIL_FROM, SITE_URL, SUPPORT_EMAIL, env } from "./env";

// Email goes out through Resend's HTTP API from Snapreel <hello@snapreel.video> (domain snapreel.video, verified
// in Resend; key "snapreel-prod" is sending-only for that domain). Replies go to support@snapreel.video.

export interface Email {
  to: string;
  subject: string;
  html: string;
  text: string;
  replyTo?: string;
  headers?: Record<string, string>;
  idempotencyKey?: string;
  tags?: { name: string; value: string }[];
}

export async function sendEmail(email: Email): Promise<{ ok: boolean; id?: string; error?: string }> {
  const key = env.resendApiKey;
  if (!key) {
    console.warn("[email] RESEND_API_KEY is not set; skipped", email.subject);
    return { ok: false, error: "not_configured" };
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "content-type": "application/json",
      ...(email.idempotencyKey ? { "Idempotency-Key": email.idempotencyKey.slice(0, 256) } : {}),
    },
    body: JSON.stringify({
      from: EMAIL_FROM,
      to: [email.to],
      reply_to: email.replyTo ?? SUPPORT_EMAIL,
      subject: email.subject,
      html: email.html,
      text: email.text,
      headers: email.headers,
      tags: email.tags,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  const body = (await res.json().catch(() => ({}))) as { id?: string; message?: string };
  if (!res.ok) {
    console.error("[email] resend", res.status, body.message);
    return { ok: false, error: body.message || String(res.status) };
  }
  return { ok: true, id: body.id };
}

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

// One plain, branded layout: the red record mark, a heading, body paragraphs, an optional button and a footer.
function layout(opts: {
  preheader: string;
  heading: string;
  bodyHtml: string;
  button?: { label: string; url: string };
  footerHtml?: string;
}): string {
  const button = opts.button
    ? `<tr><td style="padding:8px 0 24px"><a href="${escapeHtml(opts.button.url)}" style="display:inline-block;background:#F04850;color:#ffffff;text-decoration:none;font-weight:600;font-size:16px;line-height:1;padding:14px 22px;border-radius:12px">${escapeHtml(opts.button.label)}</a></td></tr>`
    : "";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>${escapeHtml(opts.heading)}</title></head>
<body style="margin:0;padding:0;background:#F4F4F6;color:#13141B;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Roboto,Helvetica,Arial,sans-serif">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${escapeHtml(opts.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F4F6"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:20px">
<tr><td style="padding:32px 32px 8px">
<table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="width:40px;height:40px;border-radius:12px;background:#F04850;text-align:center;vertical-align:middle"><div style="width:16px;height:16px;margin:12px auto;border-radius:8px;background:#ffffff"></div></td><td style="padding-left:12px;font-weight:700;font-size:18px;color:#13141B">Snapreel</td></tr></table>
</td></tr>
<tr><td style="padding:16px 32px 0"><h1 style="margin:0 0 12px;font-size:24px;line-height:1.25;color:#13141B">${escapeHtml(opts.heading)}</h1></td></tr>
<tr><td style="padding:0 32px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="font-size:16px;line-height:1.5;color:#3D404C">${opts.bodyHtml}</td></tr>${button}</table></td></tr>
<tr><td style="padding:8px 32px 32px;font-size:13px;line-height:1.5;color:#6B6F7D;border-top:1px solid #ECEDF1">${opts.footerHtml ?? ""}<p style="margin:12px 0 0">Snapreel · ${escapeHtml(LEGAL_ENTITY.name)}, ${escapeHtml(LEGAL_ADDRESS)} · <a href="${SITE_URL}" style="color:#6B6F7D">snapreel.video</a></p></td></tr>
</table></td></tr></table></body></html>`;
}

export function codeEmail(code: string, kind: "sign_in" | "email_change" | "reauthentication"): Pick<Email, "subject" | "html" | "text"> {
  const what =
    kind === "email_change" ? "confirm your new email address" : kind === "reauthentication" ? "confirm it's you" : "sign in to Snapreel";
  const digits = escapeHtml(code);
  return {
    subject: `${code} is your Snapreel code`,
    html: layout({
      preheader: `Your code is ${code}. It works for 10 minutes.`,
      heading: "Your Snapreel code",
      bodyHtml: `<p style="margin:0 0 16px">Enter this code to ${what}:</p>
<p style="margin:0 0 16px;font-size:34px;line-height:1;font-weight:700;letter-spacing:6px;color:#13141B;font-family:'SF Mono',Menlo,Consolas,monospace">${digits}</p>
<p style="margin:0 0 24px">It works for 10 minutes. If you didn't ask for it, you can ignore this email.</p>`,
      footerHtml: `<p style="margin:0">Questions? Write to <a href="mailto:${SUPPORT_EMAIL}" style="color:#6B6F7D">${SUPPORT_EMAIL}</a>.</p>`,
    }),
    text: `Your Snapreel code is ${code}\n\nEnter it to ${what}. It works for 10 minutes. If you didn't ask for it, you can ignore this email.\n\nSnapreel · ${SITE_URL}`,
  };
}

function alertFooter(unsubscribeUrl: string) {
  return `<p style="margin:0">You get these because someone used one of your Snapreel links. <a href="${escapeHtml(unsubscribeUrl)}" style="color:#6B6F7D">Turn off email alerts</a>.</p>`;
}

export function viewEmail(opts: {
  viewerName: string | null;
  title: string;
  percent: number;
  dashboardUrl: string;
  posterUrl: string | null;
  unsubscribeUrl: string;
}): Pick<Email, "subject" | "html" | "text"> {
  const who = opts.viewerName || "Someone";
  const title = opts.title || "your video";
  const poster = opts.posterUrl
    ? `<p style="margin:0 0 16px"><img src="${escapeHtml(opts.posterUrl)}" alt="" width="456" style="display:block;width:100%;max-width:456px;border-radius:12px"></p>`
    : "";
  return {
    subject: `${who} watched “${title}”`,
    html: layout({
      preheader: `Watched ${opts.percent}% so far.`,
      heading: `${who} watched “${title}”`,
      bodyHtml: `${poster}<p style="margin:0 0 16px">They've watched ${opts.percent}% so far. See who watched and how far in your dashboard.</p>`,
      button: { label: "See insights", url: opts.dashboardUrl },
      footerHtml: alertFooter(opts.unsubscribeUrl),
    }),
    text: `${who} watched “${title}” (${opts.percent}% so far).\n\nSee insights: ${opts.dashboardUrl}\n\nTurn off email alerts: ${opts.unsubscribeUrl}`,
  };
}

export function commentEmail(opts: {
  authorName: string;
  body: string;
  title: string;
  atLabel: string | null;
  dashboardUrl: string;
  unsubscribeUrl: string;
}): Pick<Email, "subject" | "html" | "text"> {
  const title = opts.title || "your video";
  const at = opts.atLabel ? ` at ${opts.atLabel}` : "";
  return {
    subject: `${opts.authorName} commented on “${title}”`,
    html: layout({
      preheader: opts.body.slice(0, 120),
      heading: `${opts.authorName} commented on “${title}”`,
      bodyHtml: `<p style="margin:0 0 8px;color:#6B6F7D;font-size:14px">${escapeHtml(opts.authorName)}${escapeHtml(at)}</p>
<p style="margin:0 0 20px;padding:14px 16px;background:#F4F4F6;border-radius:12px;white-space:pre-wrap">${escapeHtml(opts.body)}</p>`,
      button: { label: "Reply or manage comments", url: opts.dashboardUrl },
      footerHtml: alertFooter(opts.unsubscribeUrl),
    }),
    text: `${opts.authorName} commented on “${title}”${at}:\n\n${opts.body}\n\nReply or manage comments: ${opts.dashboardUrl}\n\nTurn off email alerts: ${opts.unsubscribeUrl}`,
  };
}

// A comment the word filter held: no name or text in the email, only where to approve or delete it.
export function heldCommentEmail(opts: {
  title: string;
  dashboardUrl: string;
  unsubscribeUrl: string;
}): Pick<Email, "subject" | "html" | "text"> {
  const title = opts.title || "your video";
  return {
    subject: `A comment on “${title}” is waiting for you`,
    html: layout({
      preheader: "Viewers can't see it until you approve it.",
      heading: `A comment on “${title}” is waiting for you`,
      bodyHtml: `<p style="margin:0 0 16px">It contains words on Snapreel's filter list, so viewers can't see it. Read it in your dashboard, then approve it or delete it.</p>`,
      button: { label: "Review the comment", url: `${opts.dashboardUrl}#activity` },
      footerHtml: alertFooter(opts.unsubscribeUrl),
    }),
    text: `A comment on “${title}” is waiting for you. It contains words on Snapreel's filter list, so viewers can't see it until you approve it.\n\nReview it: ${opts.dashboardUrl}#activity\n\nTurn off email alerts: ${opts.unsubscribeUrl}`,
  };
}

export function reactionEmail(opts: {
  count: number;
  emojis: string;
  title: string;
  dashboardUrl: string;
  unsubscribeUrl: string;
}): Pick<Email, "subject" | "html" | "text"> {
  const title = opts.title || "your video";
  const what = opts.count === 1 ? "a reaction" : `${opts.count} reactions`;
  return {
    subject: `New reactions on “${title}” ${opts.emojis}`,
    html: layout({
      preheader: `People reacted to “${title}”.`,
      heading: `${opts.emojis} on “${title}”`,
      bodyHtml: `<p style="margin:0 0 16px">Viewers left ${what} in the last few minutes.</p>`,
      button: { label: "See activity", url: opts.dashboardUrl },
      footerHtml: alertFooter(opts.unsubscribeUrl),
    }),
    text: `Viewers left ${what} on “${title}” ${opts.emojis}\n\nSee activity: ${opts.dashboardUrl}\n\nTurn off email alerts: ${opts.unsubscribeUrl}`,
  };
}

export function reportEmail(opts: {
  slug: string;
  videoId: string;
  ownerId: string;
  reason: string;
  details: string;
  reporterEmail: string | null;
}): Pick<Email, "subject" | "html" | "text"> {
  const url = `${SITE_URL}/v/${opts.slug}`;
  const rows = [
    ["Link", url],
    ["Video ID", opts.videoId],
    ["Owner ID", opts.ownerId],
    ["Reason", opts.reason],
    ["Reporter", opts.reporterEmail || "(no email given)"],
  ];
  return {
    subject: `Report (${opts.reason}): ${url}`,
    html: layout({
      preheader: `A viewer reported ${url}.`,
      heading: "A viewer reported a video",
      bodyHtml: `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 16px;font-size:14px">${rows
        .map(([k, v]) => `<tr><td style="padding:2px 12px 2px 0;color:#6B6F7D">${k}</td><td style="padding:2px 0">${escapeHtml(v)}</td></tr>`)
        .join("")}</table><p style="margin:0 0 20px;padding:14px 16px;background:#F4F4F6;border-radius:12px;white-space:pre-wrap">${escapeHtml(opts.details || "(no details)")}</p>`,
      footerHtml: `<p style="margin:0">To take it down or close the report, follow "Takedowns" in docs/pro/BACKEND.md.</p>`,
    }),
    text: `A viewer reported a video.\n\n${rows.map(([k, v]) => `${k}: ${v}`).join("\n")}\n\n${opts.details || "(no details)"}`,
  };
}
