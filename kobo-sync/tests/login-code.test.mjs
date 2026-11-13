import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import {
  LOGIN_CODE_ALPHABET,
  clientIp,
  formatLoginCode,
  generateLoginCode,
  isLoginCode,
  loginCodeHash,
  normalizeLoginCode,
} from "../../web/lib/login-code.ts";
import { SESSION_MAX_AGE, clampSessionCookie } from "../../web/lib/session-cookie.ts";
import { formatLastSync } from "../../web/lib/last-sync.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");

test("login codes use an unambiguous 8 character alphabet", () => {
  assert.equal(LOGIN_CODE_ALPHABET.length, 32);
  for (const ch of "0O1I") assert.equal(LOGIN_CODE_ALPHABET.includes(ch), false);
  assert.equal(LOGIN_CODE_ALPHABET.includes("L"), true);
  for (let i = 0; i < 30; i++) {
    const code = generateLoginCode();
    assert.equal(isLoginCode(code), true);
    assert.equal(code.length, 8);
  }
  assert.equal(isLoginCode("ABCD0FGH"), false);
  assert.equal(isLoginCode("ABCDOFGH"), false);
  assert.equal(isLoginCode("ABCDIFGH"), false);
  assert.equal(isLoginCode("AB"), false);
});

test("normalization accepts spaces and dashes and hashes the canonical code", async () => {
  assert.equal(normalizeLoginCode(" ab-cd efgh "), "ABCDEFGH");
  assert.equal(isLoginCode(normalizeLoginCode("ab cd-efgh")), true);
  assert.equal(formatLoginCode("ABCDEFGH"), "ABCD EFGH");
  const hash = await loginCodeHash("ABCDEFGH");
  const node = createHash("sha256").update("ABCDEFGH").digest("hex");
  assert.equal(hash, node);
  assert.equal(hash.includes("ABCDEFGH"), false);
});

test("client ip is the first forwarded address and is bounded", () => {
  const req = new Request("https://example.test/auth/code", {
    headers: { "x-forwarded-for": "203.0.113.5, 10.0.0.1" },
  });
  assert.equal(clientIp(req), "203.0.113.5");
  assert.equal(clientIp(new Request("https://example.test")), "unknown");
});

test("session cookies are capped at 400 days and before 2038", () => {
  assert.equal(SESSION_MAX_AGE, 60 * 60 * 24 * 400);
  const now = Date.parse("2026-11-13T00:00:00Z");
  const fixed = clampSessionCookie(
    "sb-abc-auth-token=value; Path=/; Max-Age=31536000000; Expires=Thu, 01 Jan 3026 00:00:00 GMT",
    now,
    true,
  );
  assert.match(fixed, new RegExp(`Max-Age=${SESSION_MAX_AGE}`));
  assert.match(fixed, /Secure/);
  const expires = /Expires=([^;]+)/.exec(fixed)?.[1];
  assert.ok(expires);
  const when = Date.parse(expires);
  assert.ok(when < Date.parse("2038-01-01T00:00:00Z"));
  assert.ok(when > Date.parse("2027-11-01T00:00:00Z"));
  const deleted = "sb-abc-auth-token=; Max-Age=0";
  assert.equal(clampSessionCookie(deleted, now), deleted);
  assert.equal(
    clampSessionCookie("other=1; Max-Age=10", now),
    "other=1; Max-Age=10",
  );
});

test("library last-sync line names the age and the highlight count", () => {
  const now = new Date("2026-11-13T12:00:00Z");
  const at = new Date("2026-11-13T10:00:00Z");
  assert.equal(formatLastSync(at, 12, now), "Last synced 2 hours ago, 12 highlights");
  assert.equal(formatLastSync(at, 1, now), "Last synced 2 hours ago, 1 highlight");
  assert.equal(formatLastSync(at, 0, now), "Last synced 2 hours ago, 0 highlights");
});

test("kobo sign-in is a plain form and the account page can mint a code", () => {
  const login = fs.readFileSync(path.join(repo, "web/app/login/page.tsx"), "utf8");
  const magic = fs.readFileSync(path.join(repo, "web/app/login/MagicLinkForm.tsx"), "utf8");
  const account = fs.readFileSync(path.join(repo, "web/app/account/page.tsx"), "utf8");
  const library = fs.readFileSync(path.join(repo, "web/app/library/page.tsx"), "utf8");
  assert.match(login, /Have a code\?/);
  assert.match(login, /method="post"/);
  assert.match(login, /action="\/auth\/code"/);
  assert.match(magic, /signInWithOtp/);
  assert.match(account, /Sign in another device/);
  assert.match(account, /action="\/auth\/device-code"/);
  assert.match(library, /formatLastSync/);
  const migration = fs.readFileSync(
    path.join(repo, "supabase/migrations/20261113_login_codes.sql"),
    "utf8",
  );
  assert.match(migration, /create table if not exists public\.login_codes/);
  assert.match(migration, /last_ingest_at/);
  assert.doesNotMatch(migration, /delete from public\.highlights/i);
  assert.doesNotMatch(migration, /drop table if exists public\.(highlights|books|device_credentials)/i);
  assert.doesNotMatch(migration, /truncate/i);
});
