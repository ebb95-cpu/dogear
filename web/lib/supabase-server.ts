import { createServerComponentClient, createRouteHandlerClient } from "@supabase/auth-helpers-nextjs";
import { cookies } from "next/headers";

/** Server component Supabase client with the logged-in user's session. */
export function sbServer() {
  return createServerComponentClient({ cookies });
}

/** Route handler Supabase client. */
export function sbRoute() {
  return createRouteHandlerClient({ cookies });
}
