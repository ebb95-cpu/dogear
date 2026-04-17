import { NextResponse } from "next/server";
import { sbRoute } from "@/lib/supabase";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  if (code) {
    const sb = sbRoute();
    await sb.auth.exchangeCodeForSession(code);
  }
  return NextResponse.redirect(url.origin);
}
