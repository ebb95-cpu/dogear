import { createServerComponentClient, createRouteHandlerClient } from "@supabase/auth-helpers-nextjs";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

/** Browser-side Supabase client (RLS enforced). */
export function sbBrowser() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}

/** Server component Supabase client with the logged-in user's session. */
export function sbServer() {
  return createServerComponentClient({ cookies });
}

/** Route handler Supabase client. */
export function sbRoute() {
  return createRouteHandlerClient({ cookies });
}
