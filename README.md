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

1. A tiny shell script on your Kobo watches `KoboReader.sqlite` and pushes new highlights over WiFi to Supabase.
2. Supabase stores them (Postgres) and handles your login (magic link email).
3. The web app on Vercel reads from Supabase and renders the UI.

Everything in this repo runs on free tiers.

---

## Folder layout

```
dogear/
├── README.md                 ← you are here
├── supabase/
│   └── schema.sql            ← paste this into Supabase SQL editor
├── web/                      ← Next.js app, deploy to Vercel
│   ├── app/                  ← pages (timeline, books, daily review)
│   ├── components/
│   ├── lib/
│   ├── package.json
│   └── .env.example
├── kobo-sync/
│   ├── install-on-kobo.md    ← how to put the sync script on your Kobo
│   ├── kobo-sync.sh          ← the sync script itself
│   └── nm_kobosync           ← NickelMenu entry (adds "Sync highlights" menu item)
└── docs/
    ├── 01-setup-supabase.md
    ├── 02-deploy-web-app.md
    └── 03-install-on-kobo.md
```

---

## Quick start (15 min, no coding required)

1. **Create a free Supabase project** → paste `supabase/schema.sql` → copy your project URL + anon key.
   See `docs/01-setup-supabase.md`.

2. **Deploy the web app to Vercel** (free) → plug in the two env vars from step 1.
   See `docs/02-deploy-web-app.md`.

3. **Install the sync script on your Kobo** (via NickelMenu, ~5 min).
   See `docs/03-install-on-kobo.md`.

4. **Highlight something on your Kobo** → it shows up in your web app within a minute.

---

## Why this works on Kobo

Kobo stores every highlight you make in a SQLite database at `.kobo/KoboReader.sqlite`
on the device itself. The `Bookmark` table has:
- `BookmarkID`   — stable unique ID
- `ContentID`    — which book
- `Text`         — the highlighted passage
- `Annotation`   — any note you wrote
- `DateCreated`  — when you highlighted it

Kobo's built-in BusyBox shell means you can `curl` from the device once it's on WiFi.
That's all the sync script needs — no jailbreak, no firmware replacement.

The only device-side add-on is **NickelMenu** (https://pgaskin.net/NickelMenu/), a
tiny, reversible utility that adds a menu item to your Kobo. It's the standard way
to trigger custom scripts and has a large community.
