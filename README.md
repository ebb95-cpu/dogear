# Dogear — Your personal book memory

A free, self-hosted replacement for Readwise, built for Kobo readers.
Every passage you dogear on your Kobo comes back to you a few at a time.

**What you get:**
- Login from anywhere (web app on any browser / phone)
- Automatic wireless sync from your Kobo whenever you highlight
- Browse highlights by book
- Timeline view sorted by date highlighted
- Daily review (random old highlights surfaced each day, Readwise-style)
- Tags & notes you can add to any highlight

**What it costs:** $0. Free tiers of Supabase + Vercel are more than enough for personal use.

---

## Architecture at a glance

```
  ┌────────────────┐        HTTPS        ┌────────────────┐        ┌────────────────┐
  │   Your Kobo    │ ──── POST /sync ──► │    Supabase    │ ◄──── │ Next.js web app│
  │ (sync script)  │                     │ (Postgres+Auth)│        │   on Vercel    │
  └────────────────┘                     └────────────────┘        └────────────────┘
        ▲                                                                 ▲
        │                                                                 │
   you highlight                                                      you log in
   a passage                                                      from any browser
```

1. A shell script on the Kobo reads highlight rows from `KoboReader.sqlite` and, when Wi-Fi connects, POSTs them to your Supabase project with a revocable per-account token.
2. Supabase stores them (Postgres) and handles your login (magic link email, or a one-time code from a phone for the Kobo browser).
3. The web app on Vercel reads from Supabase and renders the UI.

Everything in this repo runs on free tiers.

---

## Folder layout

```
dogear/
├── README.md                 ← you are here
├── supabase/
│   ├── schema.sql            ← paste this into Supabase SQL editor
│   └── migrations/           ← upgrade an existing project; does not delete highlights
├── web/                      ← Next.js app, deploy to Vercel
│   ├── app/                  ← pages (timeline, books, daily review)
│   ├── components/
│   ├── lib/
│   ├── package.json
│   └── .env.example
├── kobo-sync/
│   ├── kobo-sync.sh          ← the sync script itself
│   ├── extract.awk           ← highlight export used by the script
│   ├── nm_kobosync           ← NickelMenu entries (manual sync and status)
│   └── dist/KoboRoot.tgz     ← Wi-Fi trigger only; no keys and no database
└── docs/
    ├── 01-setup-supabase.md
    ├── 02-deploy-web-app.md
    └── 03-install-on-kobo.md
```

---

## Quick start (15 min, no coding required)

1. **Create a free Supabase project** → paste `supabase/schema.sql` → copy your project URL + anon key.
   See `docs/01-setup-supabase.md`.

2. **Deploy the web app to Vercel** (free) → plug in the URL, the anon key, and the service role key from step 1.
   See `docs/02-deploy-web-app.md`.

3. **Install the sync script on your Kobo** (via NickelMenu, ~5 min).
   See `docs/03-install-on-kobo.md`.

4. **Highlight something on your Kobo.** It uploads the next time the Kobo connects to Wi-Fi, or when you tap **Dogear sync highlights**.

---

## Why this works on Kobo

Kobo stores every highlight you make in a SQLite database at `.kobo/KoboReader.sqlite`
on the device itself. The `Bookmark` table has:
- `BookmarkID`   — stable unique ID
- `ContentID`    — which book
- `Text`         — the highlighted passage
- `Annotation`   — any note you wrote
- `DateCreated`  — when you highlighted it

The sync script runs in the Kobo's shell when Wi-Fi comes up, and again from a NickelMenu item if you ask it to. It uses `curl` when the firmware has it, and `wget` otherwise. The stock reader is unchanged.

**NickelMenu** (https://pgaskin.net/NickelMenu/) adds the manual sync and status items. A small `KoboRoot.tgz` adds the Wi-Fi trigger. Neither one is a background program on your computer. See `docs/03-install-on-kobo.md`.
