import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";
import { env } from "./env";

export type Db = SupabaseClient<Database>;

let admin: Db | null = null;

// The server's Supabase client. It uses the secret key (service_role), so it bypasses RLS: every caller must do
// its own ownership and access checks first. Never import this from client components.
export function db(): Db {
  if (!admin) {
    admin = createClient<Database>(env.supabaseUrl, env.secretKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { "x-client-info": "snapreel-web-server" } },
    });
  }
  return admin;
}

export const BUCKET = "videos";
