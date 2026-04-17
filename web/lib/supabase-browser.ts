import { createClient } from "@supabase/supabase-js";

/** Browser-side Supabase client (RLS enforced). */
export function sbBrowser() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
