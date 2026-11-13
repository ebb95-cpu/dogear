-- Kobo browser sign-in codes, and the last-ingest stamp on device tokens.
-- Safe to re-run. Does not delete or rewrite books, highlights, notes, tags,
-- reviews, or existing device tokens.
-- Existing projects: run this file in the Supabase SQL editor.
-- New projects: supabase/schema.sql already includes the same objects.
-- This does not deploy anything and does not change production until you run it.

create extension if not exists "uuid-ossp";

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
