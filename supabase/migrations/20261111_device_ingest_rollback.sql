-- Roll back the device-ingest API without deleting books or highlights.
-- Device tokens in device_credentials are removed. web notes, favorites,
-- tags, summaries, and highlight text stay.
-- The extra highlight columns are left in place so no metadata is dropped.
-- sync_highlights is NOT restored. Restoring it would again accept a
-- client-supplied user id. Keep using ingest_highlights, or revoke the
-- Kobo token from the account page and stop syncing.

drop function if exists public.ingest_highlights(text, jsonb, jsonb);
drop function if exists public.dogear_token_hash(text);
drop table if exists public.device_credentials;

-- Daily review stays limited to auth.uid(). The view stays security invoker.
-- Re-run supabase/migrations/20261111_device_ingest.sql to turn ingest back on.
