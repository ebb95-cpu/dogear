import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";
import { pg_trgm } from "@electric-sql/pglite/contrib/pg_trgm";
import { uuid_ossp } from "@electric-sql/pglite/contrib/uuid_ossp";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const schemaV1 = fs.readFileSync(path.join(here, "fixtures/schema_v1.sql"), "utf8");
const schemaNow = fs.readFileSync(path.join(repo, "supabase/schema.sql"), "utf8");
const oldMigration = fs.readFileSync(
  path.join(repo, "supabase/migrations/20261111_device_ingest.sql"),
  "utf8",
);
const migration = fs.readFileSync(
  path.join(repo, "supabase/migrations/20261113_login_codes.sql"),
  "utf8",
);

const USER_A = "11111111-1111-1111-1111-111111111111";
const TOKEN_A = "dogear_abcdefghijklmnopqrstuvwxyz0123456789ABCD";
const TOKEN_A_HASH = "e157e599a3cfe8efc251f6d9d8f3326c208c7833524115bc29f1eb4079787794";
const CODE = "ABCDEFGH";
const CODE_HASH = createHash("sha256").update(CODE).digest("hex");
const IP_HASH = "ab".repeat(32);

const preamble = `
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  email text
);
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('dogear.uid', true), '')::uuid
$$;
do $$ begin create role anon nologin noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
do $$ begin create role dogear_user nosuperuser login nobypassrls; exception when duplicate_object then null; end $$;
grant authenticated to dogear_user;
grant usage on schema public to anon, authenticated, dogear_user, service_role;
grant usage on schema auth to anon, authenticated, dogear_user, service_role;
grant execute on function auth.uid() to anon, authenticated, dogear_user, service_role;
`;

async function newDb() {
  return new PGlite({ extensions: { pg_trgm, uuid_ossp } });
}

function otherHash(n) {
  return createHash("sha256").update(`code-${n}`).digest("hex");
}

async function expectDenied(db, sql, params = []) {
  await db.exec("set role anon");
  try {
    await db.query(sql, params);
  } catch (error) {
    assert.match(String(error?.message ?? error), /permission denied/i);
    return;
  } finally {
    await db.exec("reset role");
  }
  throw new Error(`anon was allowed to run ${sql}`);
}

async function loginCodeFlow(db) {
  await db.query(
    `insert into public.login_codes (user_id, code_hash, expires_at)
     values ($1, $2, now() + interval '10 minutes')`,
    [USER_A, CODE_HASH],
  );
  const stored = await db.query("select code_hash from public.login_codes");
  assert.equal(stored.rows.length, 1);
  assert.equal(stored.rows[0].code_hash, CODE_HASH);
  assert.equal(stored.rows[0].code_hash === CODE, false);

  let tooLong = false;
  try {
    await db.query(
      `insert into public.login_codes (user_id, code_hash, expires_at)
       values ($1, $2, now() + interval '30 minutes')`,
      [USER_A, otherHash("long")],
    );
  } catch (error) {
    assert.match(String(error?.message ?? error), /expiry too long/i);
    tooLong = true;
  }
  assert.equal(tooLong, true);

  const consumed = await db.query("select public.consume_login_code($1) as user_id", [CODE_HASH]);
  assert.equal(consumed.rows[0].user_id, USER_A);
  const again = await db.query("select public.consume_login_code($1) as user_id", [CODE_HASH]);
  assert.equal(again.rows[0].user_id, null);

  await db.query(
    `insert into public.login_codes (user_id, code_hash, expires_at)
     values ($1, $2, now() + interval '10 minutes')`,
    [USER_A, otherHash("expire")],
  );
  await db.query(
    "update public.login_codes set expires_at = now() - interval '1 minute' where code_hash = $1",
    [otherHash("expire")],
  );
  const expired = await db.query("select public.consume_login_code($1) as user_id", [otherHash("expire")]);
  assert.equal(expired.rows[0].user_id, null);

  for (let i = 0; i < 3; i++) {
    await db.query(
      `insert into public.login_codes (user_id, code_hash, expires_at)
       values ($1, $2, now() + interval '9 minutes')`,
      [USER_A, otherHash(`extra-${i}`)],
    );
  }
  let limited = false;
  try {
    await db.query(
      `insert into public.login_codes (user_id, code_hash, expires_at)
       values ($1, $2, now() + interval '9 minutes')`,
      [USER_A, otherHash("sixth")],
    );
  } catch (error) {
    assert.match(String(error?.message ?? error), /rate limited/i);
    limited = true;
  }
  assert.equal(limited, true);

  for (let i = 0; i < 8; i++) {
    const ok = await db.query("select public.login_code_attempt_allowed($1) as ok", [IP_HASH]);
    assert.equal(ok.rows[0].ok, true);
  }
  const blocked = await db.query("select public.login_code_attempt_allowed($1) as ok", [IP_HASH]);
  assert.equal(blocked.rows[0].ok, false);
  const badIp = await db.query("select public.login_code_attempt_allowed($1) as ok", ["nope"]);
  assert.equal(badIp.rows[0].ok, false);

  await expectDenied(db, "select public.consume_login_code($1)", [CODE_HASH]);
  await expectDenied(db, "select code_hash from public.login_codes");

  await db.query("select set_config('dogear.uid', $1, false)", [USER_A]);
  await db.exec("set role dogear_user");
  try {
    let saw = false;
    try {
      const rows = await db.query("select code_hash from public.login_codes");
      saw = rows.rows.length > 0;
    } catch (error) {
      assert.match(String(error?.message ?? error), /permission denied/i);
      saw = false;
    }
    assert.equal(saw, false);
  } finally {
    await db.exec("reset role");
  }
}

async function ingestStamp(db) {
  await db.query(
    `insert into public.device_credentials (user_id, token_hash, token_prefix, label)
     values ($1, $2, 'dogear_abcde', 'Kobo')`,
    [USER_A, TOKEN_A_HASH],
  );
  await db.query(
    "select public.ingest_highlights($1, $2::jsonb, $3::jsonb)",
    [
      TOKEN_A,
      JSON.stringify([{ kobo_content_id: "file:///mnt/onboard/New.epub", title: "New", author: "Ada" }]),
      JSON.stringify([{
        kobo_bookmark_id: "bm-new",
        kobo_content_id: "file:///mnt/onboard/New.epub",
        text: "a new passage",
        annotation: "",
        highlighted_at: "2024-06-01T15:04:05Z",
      }]),
    ],
  );
  const stamp = await db.query(
    `select last_ingest_at::text as at, last_ingest_count
       from public.device_credentials where user_id = $1`,
    [USER_A],
  );
  assert.equal(stamp.rows.length, 1);
  assert.ok(stamp.rows[0].at);
  assert.equal(Number(stamp.rows[0].last_ingest_count), 2);
  await db.query(
    "update public.device_credentials set revoked_at = now() where user_id = $1",
    [USER_A],
  );
  const after = await db.query(
    "select last_ingest_at::text as at, last_ingest_count from public.device_credentials where user_id = $1",
    [USER_A],
  );
  assert.equal(after.rows[0].at, stamp.rows[0].at);
  assert.equal(Number(after.rows[0].last_ingest_count), 2);
}

test("upgrading keeps highlights and adds single-use login codes", async () => {
  const db = await newDb();
  await db.exec(preamble);
  await db.exec(schemaV1);
  await db.query("insert into auth.users (id, email) values ($1, 'a@example.com')", [USER_A]);
  await db.query(
    `insert into public.books (id, user_id, kobo_content_id, title)
     values ('33333333-3333-3333-3333-333333333333', $1, 'file:///mnt/onboard/Old.epub', 'Kept Title')`,
    [USER_A],
  );
  await db.query(
    `insert into public.highlights (id, user_id, book_id, kobo_bookmark_id, text, web_note)
     values (
       '44444444-4444-4444-4444-444444444444',
       $1,
       '33333333-3333-3333-3333-333333333333',
       'bm-existing',
       'original passage',
       'typed on the website'
     )`,
    [USER_A],
  );
  await db.exec(oldMigration);
  await db.exec(migration);
  await db.exec(migration);
  const kept = await db.query(
    "select text, web_note from public.highlights where kobo_bookmark_id = 'bm-existing'",
  );
  assert.equal(kept.rows.length, 1);
  assert.equal(kept.rows[0].text, "original passage");
  assert.equal(kept.rows[0].web_note, "typed on the website");
  await loginCodeFlow(db);
  await ingestStamp(db);
  const still = await db.query(
    "select count(*)::int as n from public.highlights where kobo_bookmark_id = 'bm-existing'",
  );
  assert.equal(still.rows[0].n, 1);
  await db.close();
});

test("a fresh schema has the same login-code rules", async () => {
  const db = await newDb();
  await db.exec(preamble);
  await db.exec(schemaNow);
  await db.query("insert into auth.users (id, email) values ($1, 'a@example.com')", [USER_A]);
  await db.query(
    `insert into public.books (id, user_id, kobo_content_id, title)
     values ('33333333-3333-3333-3333-333333333333', $1, 'file:///mnt/onboard/Old.epub', 'Kept Title')`,
    [USER_A],
  );
  await db.query(
    `insert into public.highlights (id, user_id, book_id, kobo_bookmark_id, text)
     values (
       '44444444-4444-4444-4444-444444444444',
       $1,
       '33333333-3333-3333-3333-333333333333',
       'bm-existing',
       'original passage'
     )`,
    [USER_A],
  );
  await loginCodeFlow(db);
  await ingestStamp(db);
  await db.close();
});
