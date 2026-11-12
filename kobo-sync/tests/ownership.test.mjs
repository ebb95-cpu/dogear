import assert from "node:assert/strict";
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
const migration = fs.readFileSync(
  path.join(repo, "supabase/migrations/20261111_device_ingest.sql"),
  "utf8",
);

const USER_A = "11111111-1111-1111-1111-111111111111";
const USER_B = "22222222-2222-2222-2222-222222222222";
const TOKEN_A = "dogear_abcdefghijklmnopqrstuvwxyz0123456789ABCD";
const TOKEN_A_HASH = "e157e599a3cfe8efc251f6d9d8f3326c208c7833524115bc29f1eb4079787794";
const TOKEN_B = "dogear_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";

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
create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('dogear.role', true), ''), 'anon')
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

async function apply(db, sql) {
  await db.exec(sql);
}

function books(title, contentId = "file:///mnt/onboard/Book.epub") {
  return [
    {
      kobo_content_id: contentId,
      title,
      author: "Ada Author",
      user_id: USER_B,
    },
  ];
}

function highlight(text, extra = {}) {
  return [
    {
      kobo_bookmark_id: "bm-1",
      kobo_content_id: "file:///mnt/onboard/Book.epub",
      text,
      annotation: "a note",
      chapter: "Chapter 1",
      highlighted_at: "2024-06-01T15:04:05Z",
      source_type: "highlight",
      kobo_progress: 0.25,
      user_id: USER_B,
      ...extra,
    },
  ];
}

async function ingest(db, token, bookRows, highlightRows) {
  await db.exec("reset role");
  await db.exec("set role anon");
  try {
    const res = await db.query(
      "select public.ingest_highlights($1, $2::jsonb, $3::jsonb) as result",
      [token, JSON.stringify(bookRows), JSON.stringify(highlightRows)],
    );
    return res.rows[0].result;
  } finally {
    await db.exec("reset role");
  }
}

async function ingestFails(db, token, bookRows, highlightRows) {
  try {
    await ingest(db, token, bookRows, highlightRows);
  } catch (error) {
    const message = String(error?.message ?? error);
    assert.match(message, /invalid token|42501|permission denied/i);
    return;
  }
  throw new Error("ingest unexpectedly succeeded");
}

async function seedTokens(db) {
  const hashB = await db.query("select public.dogear_token_hash($1) as hash", [TOKEN_B]);
  await db.exec("reset role");
  await db.query(
    `insert into public.device_credentials (user_id, token_hash, token_prefix, label)
     values ($1, $2, 'dogear_abcde', 'A'), ($3, $4, 'dogear_BBBBB', 'B')`,
    [USER_A, TOKEN_A_HASH, USER_B, hashB.rows[0].hash],
  );
}

async function ownershipFlow(db) {
  const hash = await db.query("select public.dogear_token_hash($1) as hash", [TOKEN_A]);
  assert.equal(hash.rows[0].hash, TOKEN_A_HASH);
  await seedTokens(db);

  await ingest(db, TOKEN_A, books(""), highlight("from A"));
  await db.query(
    `update public.highlights
        set web_note = 'keep this note', is_favorite = true
      where user_id = $1 and kobo_bookmark_id = 'bm-1'`,
    [USER_A],
  );
  await ingest(db, TOKEN_A, books("The Orange Book"), highlight("from A revised"));
  await ingest(db, TOKEN_B, books("Other copy"), highlight("from B"));

  const rows = await db.query(
    `select user_id::text, text, annotation, web_note, is_favorite, chapter, kobo_progress
       from public.highlights
      where kobo_bookmark_id = 'bm-1'
      order by user_id`,
  );
  assert.equal(rows.rows.length, 2);
  assert.equal(rows.rows[0].user_id, USER_A);
  assert.equal(rows.rows[0].text, "from A revised");
  assert.equal(rows.rows[0].annotation, "a note");
  assert.equal(rows.rows[0].web_note, "keep this note");
  assert.equal(rows.rows[0].is_favorite, true);
  assert.equal(rows.rows[0].chapter, "Chapter 1");
  assert.equal(Number(rows.rows[0].kobo_progress), 0.25);
  assert.equal(rows.rows[1].user_id, USER_B);
  assert.equal(rows.rows[1].text, "from B");
  assert.equal(rows.rows[1].web_note, null);

  const titles = await db.query(
    `select user_id::text, title from public.books
      where kobo_content_id = 'file:///mnt/onboard/Book.epub'
      order by user_id`,
  );
  assert.deepEqual(
    titles.rows.map((row) => [row.user_id, row.title]),
    [
      [USER_A, "The Orange Book"],
      [USER_B, "Other copy"],
    ],
  );

  await ingest(db, TOKEN_A, books(""), highlight("from A revised"));
  const titleAfterEmpty = await db.query(
    "select title from public.books where user_id = $1 and kobo_content_id = 'file:///mnt/onboard/Book.epub'",
    [USER_A],
  );
  assert.equal(titleAfterEmpty.rows[0].title, "The Orange Book");
  const stillOne = await db.query(
    "select count(*)::int as n from public.highlights where user_id = $1 and kobo_bookmark_id = 'bm-1'",
    [USER_A],
  );
  assert.equal(stillOne.rows[0].n, 1);

  await ingest(
    db,
    TOKEN_A,
    books("The Orange Book"),
    highlight("dated badly", { highlighted_at: "not-a-date", kobo_bookmark_id: "bm-baddate" }),
  );
  const badDate = await db.query(
    "select highlighted_at, text from public.highlights where kobo_bookmark_id = 'bm-baddate'",
  );
  assert.equal(badDate.rows.length, 1);
  assert.equal(badDate.rows[0].highlighted_at, null);
  assert.equal(badDate.rows[0].text, "dated badly");

  await db.query(
    "update public.device_credentials set revoked_at = now() where user_id = $1",
    [USER_A],
  );
  const before = await db.query(
    "select text from public.highlights where user_id = $1 and kobo_bookmark_id = 'bm-1'",
    [USER_A],
  );
  await ingestFails(db, TOKEN_A, books("Hijack"), highlight("should not land"));
  const after = await db.query(
    "select text from public.highlights where user_id = $1 and kobo_bookmark_id = 'bm-1'",
    [USER_A],
  );
  assert.equal(after.rows[0].text, before.rows[0].text);
  await ingestFails(db, "dogear_not-a-real-token-0123456789abcdef", books("X"), highlight("nope"));

  await db.query("select set_config('dogear.uid', $1, false)", [USER_A]);
  await db.exec("set role dogear_user");
  try {
    const visible = await db.query("select user_id::text, text from public.highlights order by text");
    assert.ok(visible.rows.every((row) => row.user_id === USER_A));
    assert.equal(visible.rows.some((row) => row.text === "from B"), false);
    const reviewOther = await db.query(
      "select count(*)::int as n from public.get_daily_review($1, 5)",
      [USER_B],
    );
    assert.equal(reviewOther.rows[0].n, 0);
    const reviewOwn = await db.query(
      "select count(*)::int as n from public.get_daily_review($1, 5)",
      [USER_A],
    );
    assert.ok(reviewOwn.rows[0].n > 0);
    let crossWrite = 0;
    try {
      const upd = await db.query(
        "update public.highlights set text = 'stolen' where user_id = $1",
        [USER_B],
      );
      crossWrite = upd.affectedRows ?? 0;
    } catch {
      crossWrite = 0;
    }
    assert.equal(crossWrite, 0);
    let insertedOther = false;
    try {
      await db.query(
        `insert into public.device_credentials (user_id, token_hash, token_prefix)
         values ($1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'dogear_nope')`,
        [USER_B],
      );
      insertedOther = true;
    } catch {
      insertedOther = false;
    }
    assert.equal(insertedOther, false);
  } finally {
    await db.exec("reset role");
  }

  const bText = await db.query(
    "select text from public.highlights where user_id = $1 and kobo_bookmark_id = 'bm-1'",
    [USER_B],
  );
  assert.equal(bText.rows[0].text, "from B");

  await db.exec("set role anon");
  try {
    let sawB = false;
    try {
      const anonRows = await db.query("select text from public.highlights");
      sawB = anonRows.rows.some((row) => row.text === "from B");
    } catch {
      sawB = false;
    }
    assert.equal(sawB, false);
    let oldRpc = false;
    try {
      await db.query("select public.sync_highlights($1, '[]'::jsonb, '[]'::jsonb)", [USER_B]);
      oldRpc = true;
    } catch (error) {
      const message = String(error?.message ?? error);
      assert.match(message, /permission denied|42501|disabled/i);
      oldRpc = false;
    }
    assert.equal(oldRpc, false);
  } finally {
    await db.exec("reset role");
  }
}

test("upgrading an existing database keeps highlights and enforces token ownership", async () => {
  const db = await newDb();
  await apply(db, preamble);
  await apply(db, schemaV1);
  await db.query(
    `insert into auth.users (id, email) values ($1, 'a@example.com'), ($2, 'b@example.com')`,
    [USER_A, USER_B],
  );
  await db.query(
    `insert into public.books (id, user_id, kobo_content_id, title, author)
     values ('33333333-3333-3333-3333-333333333333', $1, 'file:///mnt/onboard/Old.epub', 'Kept Title', 'Kept Author')`,
    [USER_A],
  );
  await db.query(
    `insert into public.highlights (
       id, user_id, book_id, kobo_bookmark_id, text, web_note, is_favorite
     ) values (
       '44444444-4444-4444-4444-444444444444',
       $1,
       '33333333-3333-3333-3333-333333333333',
       'bm-existing',
       'original passage',
       'typed on the website',
       true
     )`,
    [USER_A],
  );
  await apply(db, migration);
  const kept = await db.query(
    `select b.title, h.text, h.web_note, h.is_favorite
       from public.highlights h
       join public.books b on b.id = h.book_id
      where h.kobo_bookmark_id = 'bm-existing'`,
  );
  assert.equal(kept.rows.length, 1);
  assert.equal(kept.rows[0].title, "Kept Title");
  assert.equal(kept.rows[0].text, "original passage");
  assert.equal(kept.rows[0].web_note, "typed on the website");
  assert.equal(kept.rows[0].is_favorite, true);
  await ownershipFlow(db);
  await db.close();
});

test("a fresh schema rejects cross-account ingest the same way", async () => {
  const db = await newDb();
  await apply(db, preamble);
  await apply(db, schemaNow);
  await db.query(
    `insert into auth.users (id, email) values ($1, 'a@example.com'), ($2, 'b@example.com')`,
    [USER_A, USER_B],
  );
  await ownershipFlow(db);
  await db.close();
});
