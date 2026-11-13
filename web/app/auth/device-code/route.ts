import { NextResponse } from "next/server";
import { sbRoute } from "@/lib/supabase-server";
import { sbAdmin } from "@/lib/supabase-admin";
import { formatLoginCode, generateLoginCode, loginCodeHash } from "@/lib/login-code";

export const dynamic = "force-dynamic";

function page(title: string, body: string, status = 200) {
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <style>
    body { margin: 0; background: #fafaf7; color: #1a1a1a; font-family: Georgia, serif; }
    main { max-width: 32rem; margin: 0 auto; padding: 2rem 1.25rem; }
    h1 { font-size: 1.6rem; font-weight: 600; }
    p { font-size: 1.05rem; line-height: 1.4; }
    input { box-sizing: border-box; width: 100%; font-size: 2rem; letter-spacing: 0.25rem;
      text-align: center; padding: 0.8rem; border: 2px solid #1a1a1a; background: #fff; }
    a { display: inline-block; margin-right: 1.5rem; margin-top: 0.5rem; color: #1a1a1a; font-size: 1.15rem; }
  </style>
</head>
<body><main>
  <h1>${title}</h1>
  ${body}
</main></body>
</html>`;
  return new NextResponse(html, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
      "x-robots-tag": "noindex",
    },
  });
}

function esc(value: string) {
  return value.replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] ?? c
  ));
}

export async function POST(req: Request) {
  const origin = new URL(req.url).origin;
  const sb = sbRoute();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return NextResponse.redirect(new URL("/login", origin), 303);

  const admin = sbAdmin();
  if (!admin) {
    return page(
      "Sign in another device",
      "<p>Sign-in codes are not available on this server yet.</p>",
      503,
    );
  }

  const code = generateLoginCode();
  const codeHash = await loginCodeHash(code);
  const expires = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const { error } = await admin.from("login_codes").insert({
    user_id: user.id,
    code_hash: codeHash,
    expires_at: expires,
  });
  if (error) {
    const rate = /rate limited/i.test(error.message ?? "");
    return page(
      "Sign in another device",
      rate
        ? "<p>Too many codes. Wait an hour and try again.</p>"
        : "<p>Could not create a code. If this project is new, run the login-code migration in Supabase.</p>",
      rate ? 429 : 500,
    );
  }

  const shown = esc(formatLoginCode(code));
  return page(
    "Sign in another device",
    `<p>On the Kobo, open Log in and tap Have a code? Type this code. It works once and expires in 10 minutes.</p>
     <input readonly value="${shown}" aria-label="Sign-in code">
     <p><a href="/account">Account</a><a href="/library">Library</a></p>`,
  );
}
