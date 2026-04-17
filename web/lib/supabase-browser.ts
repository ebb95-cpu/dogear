import { createClientComponentClient } from "@supabase/auth-helpers-nextjs";

/** Browser-side Supabase client (session stored in cookies, shared with server). */
export function sbBrowser() {
  return createClientComponentClient();
}
