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
  -- user-added in the web app:
  web_note        text,
  is_favorite     boolean not null default false,
  unique (user_id, kobo_bookmark_id)
);

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
-- Every row is scoped to the authenticated user. The Kobo sync
-- script uses a service-role key which bypasses RLS (that's fine,
-- it's only running on YOUR device).
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
-- UPSERT RPC used by the Kobo sync script
-- Accepts a batch of highlights + books in one call, idempotent.
-- ─────────────────────────────────────────────────────────────
create or replace function public.sync_highlights(
  p_user_id    uuid,
  p_books      jsonb,       -- [{kobo_content_id,title,author}, ...]
  p_highlights jsonb        -- [{kobo_bookmark_id,kobo_content_id,text,annotation,chapter,highlighted_at}, ...]
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_inserted_highlights int := 0;
  v_inserted_books      int := 0;
  r record;
begin
  -- Upsert books first
  for r in select * from jsonb_to_recordset(p_books) as x(
      kobo_content_id text, title text, author text
  ) loop
    insert into public.books (user_id, kobo_content_id, title, author, updated_at)
    values (p_user_id, r.kobo_content_id, r.title, r.author, now())
    on conflict (user_id, kobo_content_id)
      do update set title = excluded.title,
                    author = excluded.author,
                    updated_at = now();
    v_inserted_books := v_inserted_books + 1;
  end loop;

  -- Upsert highlights, joining to the book row we just wrote
  for r in select * from jsonb_to_recordset(p_highlights) as x(
      kobo_bookmark_id text,
      kobo_content_id  text,
      text             text,
      annotation       text,
      chapter          text,
      highlighted_at   timestamptz
  ) loop
    insert into public.highlights (
      user_id, book_id, kobo_bookmark_id, text, annotation, chapter, highlighted_at
    )
    select p_user_id, b.id, r.kobo_bookmark_id, r.text, r.annotation, r.chapter, r.highlighted_at
    from public.books b
    where b.user_id = p_user_id and b.kobo_content_id = r.kobo_content_id
    on conflict (user_id, kobo_bookmark_id)
      do update set text = excluded.text,
                    annotation = excluded.annotation,
                    chapter = excluded.chapter,
                    highlighted_at = excluded.highlighted_at,
                    synced_at = now();
    v_inserted_highlights := v_inserted_highlights + 1;
  end loop;

  return jsonb_build_object(
    'books', v_inserted_books,
    'highlights', v_inserted_highlights
  );
end $$;

-- ─────────────────────────────────────────────────────────────
-- HELPER VIEW: highlights with book metadata (used by the app)
-- ─────────────────────────────────────────────────────────────
create or replace view public.v_highlights as
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

-- ─────────────────────────────────────────────────────────────
-- DAILY REVIEW: pick 5 random highlights not reviewed in the last 30 days
-- ─────────────────────────────────────────────────────────────
create or replace function public.get_daily_review(p_user_id uuid, p_count int default 5)
returns setof public.v_highlights
language sql
stable
as $$
  select v.*
  from public.v_highlights v
  where v.user_id = p_user_id
    and not exists (
      select 1 from public.daily_reviews d
      where d.user_id = p_user_id
        and d.highlight_id = v.id
        and d.reviewed_at > now() - interval '30 days'
    )
  order by random()
  limit p_count;
$$;
