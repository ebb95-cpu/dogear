# 1. Set up Supabase (free)

Supabase is the backend — Postgres database, auth, auto-generated API. Free tier is plenty for personal use (500 MB DB, 50,000 monthly active users). No credit card required.

## Step by step

1. Go to https://supabase.com and sign up (use GitHub for fastest signup).
2. Click **New project**. Name it `dogear`. Pick a strong database password (you won't need to remember it — Supabase manages it). Pick a region close to you.
3. Wait ~2 min for the project to provision.
4. In the left sidebar, open **SQL Editor** → **New query**. Paste the entire contents of `supabase/schema.sql` from this repo. Click **Run**. You should see "Success. No rows returned."
5. Go to **Settings → API**. You'll need three things (copy them somewhere safe):
   - **Project URL** (e.g. `https://abcxyz.supabase.co`)
   - **anon / public key** (long string starting with `eyJ…`) — used by the web app
   - **service_role / secret key** (different long string) — used by the Kobo sync script ONLY. Never paste this anywhere public.
6. Go to **Authentication → Providers**. Make sure **Email** is enabled. Disable "Confirm email" if you want the magic link flow to skip email confirmation (optional).
7. Done. Next: deploy the web app.
