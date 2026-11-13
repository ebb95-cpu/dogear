import { createClient } from "@supabase/supabase-js";

/** Service-role client. Server routes only. Never import this from a client component. */
export function sbAdmin() {
  if (typeof window !== "undefined") {
    throw new Error("supabase admin client is server-only");
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
