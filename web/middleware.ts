import { createMiddlewareClient } from "@supabase/auth-helpers-nextjs";
import { NextResponse, type NextRequest } from "next/server";
import { clampSessionCookie } from "@/lib/session-cookie";

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  const supabase = createMiddlewareClient({ req, res });
  try {
    // Refreshes an expired access token and writes the new session onto res.
    // The Kobo browser does not run the client refresh loop.
    await supabase.auth.getSession();
  } catch {
    return res;
  }
  const listed = res.headers.getSetCookie();
  if (listed.length === 0) return res;
  const secure = req.nextUrl.protocol === "https:";
  res.headers.delete("set-cookie");
  for (const cookie of listed) {
    res.headers.append("set-cookie", clampSessionCookie(cookie, Date.now(), secure));
  }
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
