# 2. Deploy the web app to Vercel (free)

Vercel hosts Next.js apps for free on personal accounts.

## Easy path (no local setup)

1. Push the `web/` folder to a new GitHub repo (private is fine).
2. Go to https://vercel.com and sign in with GitHub.
3. Click **Add new → Project**. Pick the repo, point the root directory at `/web` if you kept it in a subfolder.
4. On the env vars screen, paste:
   - `NEXT_PUBLIC_SUPABASE_URL` = your Supabase Project URL
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` = your Supabase anon key
   - `ANTHROPIC_API_KEY` (optional) — enables AI book summaries
5. Click **Deploy**. In ~90 seconds you'll get a URL like `https://dogear-xxx.vercel.app`.
6. Open it, click **Log in**, enter your email, click the magic link in your inbox. You should see an empty "Today's review" page.
7. Go to `/account`. Copy the **USER_ID** shown — you'll paste it into the Kobo config next.

## Local dev (optional)

```bash
cd web
cp .env.example .env.local   # fill in the two SUPABASE_* vars
npm install
npm run dev                   # http://localhost:3000
```

## Post-deploy: add your Vercel URL to Supabase

In Supabase → **Authentication → URL Configuration**, add your Vercel URL (e.g. `https://dogear-xxx.vercel.app`) to the **Site URL** and **Redirect URLs** lists. Magic links won't work otherwise.
