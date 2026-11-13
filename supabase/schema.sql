-- Dogear — Supabase schema
-- Paste this whole file into Supabase → SQL Editor → Run.
-- Safe to re-run; all objects use IF NOT EXISTS / CREATE OR REPLACE.

-- ─────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────
create extension if not exists "uuid-ossp";
create extension if not exists "pg_trgm";  -- for fuzzy search

-- ─────────────────────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────────────────────

-- Books the user has highlighted in.
create table if not exists public.books (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  kobo_content_id text not null,                  -- Kobo's ContentID (stable per book)
  title           text,
  author          text,
  cover_url       text,
  -- "What this book was about" — AI auto-drafts, you edit.
  summary         text,
  summary_is_ai_draft boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, kobo_content_id)
);

-- Pre-defined themes (life areas) — you create these once in the web app.
-- Tags reuse the same table; tags flagged is_theme=true show up in the tag picker
-- as your core themes. Other tags still work but are secondary.

-- One row per highlight.
create table if not exists public.highlights (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  book_id         uuid not null references public.books(id) on delete cascade,
  kobo_bookmark_id text not null,                 -- Kobo's BookmarkID, so re-syncs are idempotent
  text            text not null,
  annotation      text,                           -- user-typed note on the Kobo
  chapter         text,
  highlighted_at  timestamptz,                    -- DateCreated from Kobo
  synced_at       timestamptz not null default now(),
  source_type     text,                           -- highlight or note
  kobo_progress   double precision,               -- Bookmark.ChapterProgress
  -- user-added in the web app:
  web_note        text,
  is_favorite     boolean not null default false,
  unique (user_id, kobo_bookmark_id)
);

-- Re-running this file on an existing database does not rewrite CREATE TABLE.
alter table public.highlights add column if not exists source_type text;
alter table public.highlights add column if not exists kobo_progress double precision;

-- Tags the user creates in the web app. is_theme=true marks a top-level theme.
create table if not exists public.tags (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  color      text,
  is_theme   boolean not null default false,
  sort_order int     not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

-- Join table: which tags are on which highlights.
create table if not exists public.highlight_tags (
  highlight_id uuid not null references public.highlights(id) on delete cascade,
  tag_id       uuid not null references public.tags(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (highlight_id, tag_id)
);

-- Daily review tracking — so we don't show the same highlight twice in a row.
create table if not exists public.daily_reviews (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  highlight_id uuid not null references public.highlights(id) on delete cascade,
  reviewed_at  timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────────────
create index if not exists highlights_user_date_idx    on public.highlights (user_id, highlighted_at desc);
create index if not exists highlights_user_book_idx    on public.highlights (user_id, book_id);
create index if not exists highlights_text_trgm_idx    on public.highlights using gin (text gin_trgm_ops);
create index if not exists books_user_idx              on public.books (user_id);
create index if not exists daily_reviews_user_date_idx on public.daily_reviews (user_id, reviewed_at desc);

-- ─────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- Every row is scoped to the authenticated user. The Kobo script calls
-- ingest_highlights with a per-account token. It does not use the
-- service-role key, and that key must not be stored on the device.
-- ─────────────────────────────────────────────────────────────
alter table public.books           enable row level security;
alter table public.highlights      enable row level security;
alter table public.tags            enable row level security;
alter table public.highlight_tags  enable row level security;
alter table public.daily_reviews   enable row level security;

-- Books
drop policy if exists "books_own" on public.books;
create policy "books_own" on public.books
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Highlights
drop policy if exists "highlights_own" on public.highlights;
create policy "highlights_own" on public.highlights
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Tags
drop policy if exists "tags_own" on public.tags;
create policy "tags_own" on public.tags
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Highlight_tags (inherit from highlight ownership)
drop policy if exists "ht_own" on public.highlight_tags;
create policy "ht_own" on public.highlight_tags
  for all using (
    exists (
      select 1 from public.highlights h
      where h.id = highlight_tags.highlight_id and h.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.highlights h
      where h.id = highlight_tags.highlight_id and h.user_id = auth.uid()
    )
  );

-- Daily reviews
drop policy if exists "dr_own" on public.daily_reviews;
create policy "dr_own" on public.daily_reviews
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- DEVICE INGEST
-- The Kobo calls ingest_highlights. It never sends a service-role key.
-- Same statements as supabase/migrations/20261111_device_ingest.sql.
-- ─────────────────────────────────────────────────────────────

-- Dogear device ingest.
-- Safe to re-run. Does not delete books, highlights, notes, tags, or reviews.
-- Existing projects: run this file in the Supabase SQL editor.
-- New projects: supabase/schema.sql already includes the same objects.
-- This does not deploy anything and does not change production until you run it.

create schema if not exists extensions;

do $$
begin
  begin
    create extension if not exists pgcrypto with schema extensions;
  exception when others then
    begin
      create extension if not exists pgcrypto;
    exception when others then
      null;
    end;
  end;
end $$;

alter table public.highlights add column if not exists source_type text;
alter table public.highlights add column if not exists kobo_progress double precision;

create table if not exists public.device_credentials (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  token_hash   text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  token_prefix text not null check (char_length(token_prefix) between 8 and 16),
  label        text check (label is null or char_length(label) <= 80),
  created_at   timestamptz not null default now(),
  revoked_at   timestamptz,
  last_used_at timestamptz,
  -- Set when ingest_highlights touches this token. The library page reads them.
  last_ingest_at timestamptz,
  last_ingest_count integer
);

create index if not exists device_credentials_user_idx
  on public.device_credentials (user_id, created_at desc);

alter table public.device_credentials enable row level security;

drop policy if exists "device_credentials_own" on public.device_credentials;
create policy "device_credentials_own" on public.device_credentials
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke all on public.device_credentials from public, anon;
grant select, insert, update, delete on public.device_credentials to authenticated;
grant select, insert, update, delete on public.device_credentials to service_role;

-- SHA-256 used when pgcrypto is not installed (local tests, unusual hosts).
-- Supabase has pgcrypto and dogear_token_hash prefers that.
create or replace function public.dogear_u32(x bigint)
returns bigint
language sql
immutable
as $$ select x & 4294967295 $$;

create or replace function public.dogear_rotr(x bigint, n int)
returns bigint
language sql
immutable
as $$
  select public.dogear_u32(
    (public.dogear_u32(x) >> n)
    | public.dogear_u32(public.dogear_u32(x) << (32 - n))
  )
$$;

create or replace function public.dogear_sha256_hex(p_text text)
returns text
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
declare
  msg bytea;
  padded bytea;
  bit_len bigint;
  nchunks int;
  chunk int;
  off int;
  j int;
  w bigint[];
  k bigint[] := array[
    1116352408::bigint, 1899447441::bigint, 3049323471::bigint, 3921009573::bigint,
    961987163::bigint, 1508970993::bigint, 2453635748::bigint, 2870763221::bigint,
    3624381080::bigint, 310598401::bigint, 607225278::bigint, 1426881987::bigint,
    1925078388::bigint, 2162078206::bigint, 2614888103::bigint, 3248222580::bigint,
    3835390401::bigint, 4022224774::bigint, 264347078::bigint, 604807628::bigint,
    770255983::bigint, 1249150122::bigint, 1555081692::bigint, 1996064986::bigint,
    2554220882::bigint, 2821834349::bigint, 2952996808::bigint, 3210313671::bigint,
    3336571891::bigint, 3584528711::bigint, 113926993::bigint, 338241895::bigint,
    666307205::bigint, 773529912::bigint, 1294757372::bigint, 1396182291::bigint,
    1695183700::bigint, 1986661051::bigint, 2177026350::bigint, 2456956037::bigint,
    2730485921::bigint, 2820302411::bigint, 3259730800::bigint, 3345764771::bigint,
    3516065817::bigint, 3600352804::bigint, 4094571909::bigint, 275423344::bigint,
    430227734::bigint, 506948616::bigint, 659060556::bigint, 883997877::bigint,
    958139571::bigint, 1322822218::bigint, 1537002063::bigint, 1747873779::bigint,
    1955562222::bigint, 2024104815::bigint, 2227730452::bigint, 2361852424::bigint,
    2428436474::bigint, 2756734187::bigint, 3204031479::bigint, 3329325298::bigint
  ];
  h0 bigint := 1779033703;
  h1 bigint := 3144134277;
  h2 bigint := 1013904242;
  h3 bigint := 2773480762;
  h4 bigint := 1359893119;
  h5 bigint := 2600822924;
  h6 bigint := 528734635;
  h7 bigint := 1541459225;
  a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; g bigint; h bigint;
  t1 bigint; t2 bigint; s0 bigint; s1 bigint;
begin
  if p_text is null then
    return null;
  end if;
  msg := convert_to(p_text, 'UTF8');
  bit_len := octet_length(msg)::bigint * 8;
  padded := msg || '\x80'::bytea;
  while octet_length(padded) % 64 <> 56 loop
    padded := padded || '\x00'::bytea;
  end loop;
  padded := padded || int8send(bit_len);
  nchunks := octet_length(padded) / 64;
  for chunk in 0..(nchunks - 1) loop
    w := array[]::bigint[];
    for j in 1..16 loop
      off := chunk * 64 + (j - 1) * 4;
      w[j] := (get_byte(padded, off)::bigint << 24)
           | (get_byte(padded, off + 1)::bigint << 16)
           | (get_byte(padded, off + 2)::bigint << 8)
           | get_byte(padded, off + 3)::bigint;
    end loop;
    for j in 17..64 loop
      s0 := public.dogear_u32(
        public.dogear_rotr(w[j - 15], 7) # public.dogear_rotr(w[j - 15], 18) # (public.dogear_u32(w[j - 15]) >> 3)
      );
      s1 := public.dogear_u32(
        public.dogear_rotr(w[j - 2], 17) # public.dogear_rotr(w[j - 2], 19) # (public.dogear_u32(w[j - 2]) >> 10)
      );
      w[j] := public.dogear_u32(w[j - 16] + s0 + w[j - 7] + s1);
    end loop;
    a := h0; b := h1; c := h2; d := h3; e := h4; f := h5; g := h6; h := h7;
    for j in 1..64 loop
      t1 := public.dogear_u32(
        h
        + public.dogear_u32(public.dogear_rotr(e, 6) # public.dogear_rotr(e, 11) # public.dogear_rotr(e, 25))
        + public.dogear_u32((e & f) # (public.dogear_u32(~ e) & g))
        + k[j]
        + w[j]
      );
      t2 := public.dogear_u32(
        public.dogear_u32(public.dogear_rotr(a, 2) # public.dogear_rotr(a, 13) # public.dogear_rotr(a, 22))
        + public.dogear_u32((a & b) # (a & c) # (b & c))
      );
      h := g; g := f; f := e;
      e := public.dogear_u32(d + t1);
      d := c; c := b; b := a;
      a := public.dogear_u32(t1 + t2);
    end loop;
    h0 := public.dogear_u32(h0 + a);
    h1 := public.dogear_u32(h1 + b);
    h2 := public.dogear_u32(h2 + c);
    h3 := public.dogear_u32(h3 + d);
    h4 := public.dogear_u32(h4 + e);
    h5 := public.dogear_u32(h5 + f);
    h6 := public.dogear_u32(h6 + g);
    h7 := public.dogear_u32(h7 + h);
  end loop;
  return lpad(to_hex(h0), 8, '0')
      || lpad(to_hex(h1), 8, '0')
      || lpad(to_hex(h2), 8, '0')
      || lpad(to_hex(h3), 8, '0')
      || lpad(to_hex(h4), 8, '0')
      || lpad(to_hex(h5), 8, '0')
      || lpad(to_hex(h6), 8, '0')
      || lpad(to_hex(h7), 8, '0');
end $$;

revoke all on function public.dogear_u32(bigint) from public, anon, authenticated;
revoke all on function public.dogear_rotr(bigint, int) from public, anon, authenticated;
revoke all on function public.dogear_sha256_hex(text) from public, anon, authenticated;

-- Hash helper. Not granted to API roles; ingest_highlights calls it as owner.
-- pgcrypto is preferred. The plpgsql SHA-256 above is the fallback.
create or replace function public.dogear_token_hash(p_token text)
returns text
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
declare
  v text;
begin
  if p_token is null then
    return null;
  end if;
  begin
    execute 'select encode(extensions.digest($1, ''sha256''), ''hex'')'
      into v using p_token;
    if v is not null then
      return v;
    end if;
  exception when others then
    null;
  end;
  begin
    execute 'select encode(public.digest($1, ''sha256''), ''hex'')'
      into v using p_token;
    if v is not null then
      return v;
    end if;
  exception when others then
    null;
  end;
  return public.dogear_sha256_hex(p_token);
end $$;

revoke all on function public.dogear_token_hash(text) from public, anon, authenticated;

-- The account is the token's owner. A user id in the JSON is ignored.
create or replace function public.ingest_highlights(
  p_token text,
  p_books jsonb,
  p_highlights jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_user uuid;
  v_hash text;
  v_books int := 0;
  v_high int := 0;
  r record;
  v_at timestamptz;
  v_text text;
  v_note text;
  v_chapter text;
  v_progress double precision;
  v_type text;
  v_book uuid;
begin
  if p_token is null
     or length(p_token) < 40
     or length(p_token) > 200
     or p_token !~ '^dogear_[A-Za-z0-9_-]+$' then
    raise exception 'invalid token' using errcode = '28000';
  end if;

  v_hash := public.dogear_token_hash(p_token);
  select c.user_id into v_user
  from public.device_credentials c
  where c.token_hash = v_hash
    and c.revoked_at is null;

  if v_user is null then
    raise exception 'invalid token' using errcode = '28000';
  end if;

  if p_books is null or jsonb_typeof(p_books) <> 'array' then
    raise exception 'books must be a json array';
  end if;
  if p_highlights is null or jsonb_typeof(p_highlights) <> 'array' then
    raise exception 'highlights must be a json array';
  end if;
  if jsonb_array_length(p_books) > 100 or jsonb_array_length(p_highlights) > 100 then
    raise exception 'batch too large';
  end if;

  for r in
    select * from jsonb_to_recordset(p_books) as x(
      kobo_content_id text,
      title text,
      author text
    )
  loop
    if r.kobo_content_id is null or length(btrim(r.kobo_content_id)) = 0 then
      continue;
    end if;
    if length(r.kobo_content_id) > 2048 then
      raise exception 'kobo_content_id too long';
    end if;
    insert into public.books (user_id, kobo_content_id, title, author, updated_at)
    values (
      v_user,
      r.kobo_content_id,
      nullif(left(coalesce(r.title, ''), 1000), ''),
      nullif(left(coalesce(r.author, ''), 1000), ''),
      now()
    )
    on conflict (user_id, kobo_content_id) do update
      set title = case
            when nullif(excluded.title, '') is not null then excluded.title
            else public.books.title
          end,
          author = case
            when nullif(excluded.author, '') is not null then excluded.author
            else public.books.author
          end,
          updated_at = case
            when public.books.title is distinct from (
              case when nullif(excluded.title, '') is not null then excluded.title else public.books.title end
            )
            or public.books.author is distinct from (
              case when nullif(excluded.author, '') is not null then excluded.author else public.books.author end
            )
            then now()
            else public.books.updated_at
          end;
    v_books := v_books + 1;
  end loop;

  for r in
    select * from jsonb_to_recordset(p_highlights) as x(
      kobo_bookmark_id text,
      kobo_content_id text,
      text text,
      annotation text,
      chapter text,
      highlighted_at text,
      source_type text,
      kobo_progress double precision
    )
  loop
    if r.kobo_bookmark_id is null or length(btrim(r.kobo_bookmark_id)) = 0 then
      continue;
    end if;
    if r.kobo_content_id is null or length(btrim(r.kobo_content_id)) = 0 then
      continue;
    end if;
    if length(r.kobo_bookmark_id) > 2048 or length(r.kobo_content_id) > 2048 then
      raise exception 'id too long';
    end if;

    v_text := left(coalesce(r.text, ''), 20000);
    v_note := nullif(left(coalesce(r.annotation, ''), 20000), '');
    if length(btrim(v_text)) = 0 then
      if v_note is null then
        continue;
      end if;
      v_text := v_note;
      v_note := null;
    end if;

    v_chapter := nullif(left(coalesce(r.chapter, ''), 1000), '');
    v_type := case when lower(coalesce(r.source_type, '')) = 'note' then 'note' else 'highlight' end;
    v_progress := r.kobo_progress;

    v_at := null;
    if r.highlighted_at is not null and length(btrim(r.highlighted_at)) > 0 then
      begin
        v_at := btrim(r.highlighted_at)::timestamptz;
      exception when others then
        v_at := null;
      end;
    end if;

    insert into public.books (user_id, kobo_content_id, updated_at)
    values (v_user, r.kobo_content_id, now())
    on conflict (user_id, kobo_content_id) do nothing;

    select b.id into v_book
    from public.books b
    where b.user_id = v_user and b.kobo_content_id = r.kobo_content_id;

    if v_book is null then
      raise exception 'book missing after upsert';
    end if;

    insert into public.highlights (
      user_id, book_id, kobo_bookmark_id, text, annotation, chapter,
      highlighted_at, source_type, kobo_progress
    )
    values (
      v_user, v_book, r.kobo_bookmark_id, v_text, v_note, v_chapter,
      v_at, v_type, v_progress
    )
    on conflict (user_id, kobo_bookmark_id) do update
      set text = excluded.text,
          annotation = excluded.annotation,
          chapter = excluded.chapter,
          highlighted_at = excluded.highlighted_at,
          source_type = excluded.source_type,
          kobo_progress = excluded.kobo_progress,
          synced_at = now(),
          book_id = excluded.book_id;

    update public.books
      set updated_at = now()
      where id = v_book;

    v_high := v_high + 1;
  end loop;

  update public.device_credentials
    set last_used_at = now()
    where token_hash = v_hash
      and user_id = v_user;

  return jsonb_build_object('ok', true, 'books', v_books, 'highlights', v_high);
end $$;

revoke all on function public.ingest_highlights(text, jsonb, jsonb) from public;
grant execute on function public.ingest_highlights(text, jsonb, jsonb) to anon, authenticated, service_role;

-- The old RPC trusted a client-supplied user id and was callable with the
-- anon key. Keep a stub so an old script gets a clear error, and do not
-- grant it to API roles.
create or replace function public.sync_highlights(
  p_user_id uuid,
  p_books jsonb,
  p_highlights jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  raise exception 'sync_highlights is disabled. It trusted a client-supplied user id. Use ingest_highlights with a device token.'
    using errcode = '42501';
end $$;

revoke all on function public.sync_highlights(uuid, jsonb, jsonb) from public, anon, authenticated, service_role;

create or replace view public.v_highlights
with (security_invoker = true) as
select
  h.id,
  h.user_id,
  h.text,
  h.annotation,
  h.web_note,
  h.chapter,
  h.is_favorite,
  h.highlighted_at,
  h.synced_at,
  b.id        as book_id,
  b.title     as book_title,
  b.author    as book_author,
  b.cover_url as book_cover_url,
  b.summary   as book_summary
from public.highlights h
join public.books b on b.id = h.book_id;

alter view public.v_highlights set (security_invoker = true);

revoke all on public.v_highlights from public, anon;
grant select on public.v_highlights to authenticated, service_role;

create or replace function public.get_daily_review(p_user_id uuid, p_count integer default 5)
returns setof public.v_highlights
language sql
stable
security invoker
set search_path = public, pg_catalog
as $$
  select v.*
  from public.v_highlights v
  where v.user_id = p_user_id
    and p_user_id = auth.uid()
    and not exists (
      select 1 from public.daily_reviews d
      where d.user_id = p_user_id
        and d.highlight_id = v.id
        and d.reviewed_at > now() - interval '30 days'
    )
  order by random()
  limit p_count;
$$;

revoke all on function public.get_daily_review(uuid, integer) from public, anon;
grant execute on function public.get_daily_review(uuid, integer) to authenticated, service_role;

grant select, insert, update, delete on public.books to authenticated;
grant select, insert, update, delete on public.highlights to authenticated;
grant select, insert, update, delete on public.tags to authenticated;
grant select, insert, update, delete on public.highlight_tags to authenticated;
grant select, insert, update, delete on public.daily_reviews to authenticated;

-- ─────────────────────────────────────────────────────────────
-- LAST INGEST + KOBO SIGN-IN CODES
-- Same statements as supabase/migrations/20261113_login_codes.sql.
-- Safe to re-run. Does not delete books, highlights, notes, or tokens.
-- ─────────────────────────────────────────────────────────────

alter table public.device_credentials
  add column if not exists last_ingest_at timestamptz;
alter table public.device_credentials
  add column if not exists last_ingest_count integer;

create index if not exists device_credentials_last_ingest_idx
  on public.device_credentials (user_id, last_ingest_at desc);

-- ingest_highlights sets last_used_at after a batch. Record the library
-- size at that moment without changing the ingest function body.
create or replace function public.device_credentials_note_ingest()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.last_used_at is not distinct from old.last_used_at or new.last_used_at is null then
    return new;
  end if;
  new.last_ingest_at := new.last_used_at;
  new.last_ingest_count := (
    select count(*)::integer
    from public.highlights h
    where h.user_id = new.user_id
  );
  return new;
end $$;

drop trigger if exists device_credentials_note_ingest on public.device_credentials;
create trigger device_credentials_note_ingest
  before update on public.device_credentials
  for each row
  execute function public.device_credentials_note_ingest();

revoke all on function public.device_credentials_note_ingest() from public, anon, authenticated;
grant execute on function public.device_credentials_note_ingest() to service_role;

-- Short sign-in codes for the Kobo browser. Only the hash is stored.
-- No policies: anon and authenticated cannot read hashes (the code is short).
-- The service role bypasses RLS and is the only writer. It stays on the server.
create table if not exists public.login_codes (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  code_hash  text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);

create index if not exists login_codes_user_created_idx
  on public.login_codes (user_id, created_at desc);

alter table public.login_codes enable row level security;
alter table public.login_codes force row level security;

revoke all on public.login_codes from public, anon, authenticated;
grant select, insert, update, delete on public.login_codes to service_role;

create table if not exists public.login_code_attempts (
  id         uuid primary key default uuid_generate_v4(),
  ip_hash    text not null check (ip_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create index if not exists login_code_attempts_ip_idx
  on public.login_code_attempts (ip_hash, created_at desc);

alter table public.login_code_attempts enable row level security;
alter table public.login_code_attempts force row level security;

revoke all on public.login_code_attempts from public, anon, authenticated;
grant select, insert, update, delete on public.login_code_attempts to service_role;

-- Five new codes per account per hour, and none may live longer than 10 minutes.
create or replace function public.login_codes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  n int;
begin
  if new.expires_at is null or new.expires_at > now() + interval '11 minutes' then
    raise exception 'login code expiry too long';
  end if;
  if new.expires_at <= now() then
    raise exception 'login code expiry too soon';
  end if;
  select count(*)::int into n
  from public.login_codes
  where user_id = new.user_id
    and created_at > now() - interval '1 hour';
  if n >= 5 then
    raise exception 'rate limited';
  end if;
  return new;
end $$;

drop trigger if exists login_codes_before_insert on public.login_codes;
create trigger login_codes_before_insert
  before insert on public.login_codes
  for each row
  execute function public.login_codes_before_insert();

revoke all on function public.login_codes_before_insert() from public, anon, authenticated;
grant execute on function public.login_codes_before_insert() to service_role;

-- Single use. A second call with the same hash returns null.
create or replace function public.consume_login_code(p_code_hash text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_user uuid;
begin
  v_user := null;
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  update public.login_codes
     set used_at = now()
   where code_hash = p_code_hash
     and used_at is null
     and expires_at > now()
  returning user_id into v_user;
  return v_user;
end $$;

revoke all on function public.consume_login_code(text) from public, anon, authenticated;
grant execute on function public.consume_login_code(text) to service_role;

-- Eight guesses per IP hash per 10 minutes. The hash is not an address.
create or replace function public.login_code_attempt_allowed(p_ip_hash text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  n int;
begin
  if p_ip_hash is null or p_ip_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  delete from public.login_code_attempts
  where created_at < now() - interval '1 day';
  select count(*)::int into n
  from public.login_code_attempts
  where ip_hash = p_ip_hash
    and created_at > now() - interval '10 minutes';
  if n >= 8 then
    return false;
  end if;
  insert into public.login_code_attempts (ip_hash) values (p_ip_hash);
  return true;
end $$;

revoke all on function public.login_code_attempt_allowed(text) from public, anon, authenticated;
grant execute on function public.login_code_attempt_allowed(text) to service_role;

do $$
begin
  perform pg_notify('pgrst', 'reload schema');
exception when others then
  null;
end $$;
