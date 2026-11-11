# 1. Set up Supabase (free)

Supabase is the backend — Postgres database, auth, auto-generated API. Free tier is plenty for personal use (500 MB DB, 50,000 monthly active users). No credit card required.

## Step by step

1. Go to https://supabase.com and sign up (use GitHub for fastest signup).
2. Click **New project**. Name it `dogear`. Pick a strong database password (you won't need to remember it — Supabase manages it). Pick a region close to you.
3. Wait ~2 min for the project to provision.
4. In the left sidebar, open **SQL Editor** → **New query**. Paste the entire contents of `supabase/schema.sql` from this repo. Click **Run**. You should see "Success. No rows returned."
5. Go to **Settings → API**. Copy two values:
   - **Project URL** (e.g. `https://abcxyz.supabase.co`)
   - **anon / public key** — used by the web app and, later, by the Kobo as the public API key
   The **service role / secret key** is not used. Do not copy it onto the Kobo. If an older install already put that key on the device, regenerate it in this screen after you switch the Kobo to a device token.
6. Go to **Authentication → Providers**. Make sure **Email** is enabled. Disable "Confirm email" if you want the magic link flow to skip email confirmation (optional).
7. If this project already ran an older `schema.sql`, also run `supabase/migrations/20261111_device_ingest.sql`. It adds device tokens and does not delete books or highlights. A brand-new paste of the current `schema.sql` already includes those statements.
8. Done. Next: deploy the web app.
