import "server-only";
import { BUCKET, db } from "./supabase";

export const SIGNED_URL_TTL_S = 2 * 60 * 60;

export function videoPaths(ownerId: string, videoId: string) {
  const base = `${ownerId}/${videoId}`;
  return {
    base,
    video: `${base}/video.mp4`,
    poster: `${base}/poster.jpg`,
    preview: `${base}/preview.mp4`,
  };
}

// Signed URLs (2 hours) for objects in the private bucket. Missing objects come back as null.
export async function signUrls(paths: string[], ttl = SIGNED_URL_TTL_S): Promise<Map<string, string | null>> {
  const out = new Map<string, string | null>(paths.map((p) => [p, null]));
  if (!paths.length) return out;
  const { data, error } = await db().storage.from(BUCKET).createSignedUrls(paths, ttl);
  if (error) {
    console.error("[storage] sign", error.message);
    return out;
  }
  for (const item of data ?? []) {
    if (item.path && item.signedUrl && !item.error) out.set(item.path, item.signedUrl);
  }
  return out;
}

export async function signDownloadUrl(path: string, filename: string, ttl = SIGNED_URL_TTL_S): Promise<string | null> {
  const { data, error } = await db().storage.from(BUCKET).createSignedUrl(path, ttl, { download: filename });
  return error ? null : data.signedUrl;
}

// name -> size in bytes, for the files directly inside a folder.
export async function listFolder(prefix: string): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  const { data, error } = await db().storage.from(BUCKET).list(prefix, { limit: 1000 });
  if (error) throw error;
  for (const item of data ?? []) {
    if (item.id) out.set(item.name, Number((item.metadata as { size?: number } | null)?.size ?? 0));
  }
  return out;
}

// Deletes every object under {userId}/ or {userId}/{videoId}/. Returns how many were removed.
export async function removePrefix(prefix: string): Promise<number> {
  const bucket = db().storage.from(BUCKET);
  const files: string[] = [];
  const walk = async (folder: string, depth: number) => {
    const { data, error } = await bucket.list(folder, { limit: 1000 });
    if (error) throw error;
    for (const item of data ?? []) {
      const path = `${folder}/${item.name}`;
      if (item.id) files.push(path);
      else if (depth < 2) await walk(path, depth + 1);
    }
  };
  await walk(prefix.replace(/\/+$/, ""), 0);
  for (let i = 0; i < files.length; i += 100) {
    const { error } = await bucket.remove(files.slice(i, i + 100));
    if (error) throw error;
  }
  return files.length;
}
