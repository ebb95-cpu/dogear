import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { sbRoute } from "@/lib/supabase-server";
import { sbAdmin } from "@/lib/supabase-admin";
import {
  clientIp,
  isLoginCode,
  loginCodeHash,
  normalizeLoginCode,
  sha256Hex,
} from "@/lib/login-code";
import { SESSION_MAX_AGE } from "@/lib/session-cookie";

export const dynamic = "force-dynamic";

function redirectTo(origin: string, path: string) {
  return NextResponse.redirect(new URL(path, origin), 303);
}

function extendSessionCookies(secure: boolean) {
  const jar = cookies();
  for (const c of jar.getAll()) {
    if (!c.name.startsWith("sb-")) continue;
    jar.set(c.name, c.value, {
      path: "/",
      sameSite: "lax",
      httpOnly: false,
      secure,
      maxAge: SESSION_MAX_AGE,
    });
  }
}

export async function POST(req: Request) {
  const origin = new URL(req.url).origin;
  const secure = origin.startsWith("https:");
  const admin = sbAdmin();
  if (!admin) return redirectTo(origin, "/login?error=unavailable");

  const form = await req.formData();
  const raw = String(form.get("code") ?? "").slice(0, 40);
  const code = normalizeLoginCode(raw);
  const ipHash = await sha256Hex(clientIp(req));
  const { data: allowed, error: attemptError } = await admin.rpc("login_code_attempt_allowed", {
    p_ip_hash: ipHash,
  });
  if (attemptError) return redirectTo(origin, "/login?error=unavailable");
  if (allowed !== true) return redirectTo(origin, "/login?error=rate");
  if (!isLoginCode(code)) return redirectTo(origin, "/login?error=invalid");

  const codeHash = await loginCodeHash(code);
  const { data: userId, error: consumeError } = await admin.rpc("consume_login_code", {
    p_code_hash: codeHash,
  });
  if (consumeError) return redirectTo(origin, "/login?error=unavailable");
  if (!userId || typeof userId !== "string") return redirectTo(origin, "/login?error=invalid");

  const { data: got, error: getError } = await admin.auth.admin.getUserById(userId);
  if (getError || !got.user?.email) return redirectTo(origin, "/login?error=again");

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: got.user.email,
  });
  const tokenHash = link?.properties?.hashed_token;
  const verification = link?.properties?.verification_type;
  if (linkError || !tokenHash) return redirectTo(origin, "/login?error=again");

  const otpType =
    verification === "signup" ? "signup"
    : verification === "invite" ? "invite"
    : verification === "recovery" ? "recovery"
    : "magiclink";
  const sb = sbRoute();
  const { error: verifyError } = await sb.auth.verifyOtp({
    token_hash: tokenHash,
    type: otpType,
  });
  if (verifyError) return redirectTo(origin, "/login?error=again");

  extendSessionCookies(secure);
  return redirectTo(origin, "/library");
}
