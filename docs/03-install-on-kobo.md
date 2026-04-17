# 3. Install the sync script on your Kobo

This is the only part that touches the Kobo itself. It's fully reversible — delete two folders and you're back to stock.

## What you'll install

- **NickelMenu** — tiny utility that adds custom menu items to the Kobo. No jailbreak. Huge community. Safe.
- Your `kobo-sync.sh` script — reads the highlights database and POSTs new ones to Supabase.
- Optional: `auto-sync-on-wifi.sh` — runs the sync every 5 minutes while connected to WiFi, so highlights upload automatically as you make them.

## Steps

1. **Plug your Kobo into your Mac with a USB cable.** A volume called `KOBOeReader` will mount.
2. **Install NickelMenu.** Go to https://pgaskin.net/NickelMenu/ and download `KoboRoot.tgz`. Drop it into the `.kobo/` folder on the Kobo (you may need to show hidden files: Cmd+Shift+. in Finder). Eject the Kobo — it will reboot and install it automatically.
3. **Create the sync folder on the Kobo.** Plug the Kobo back in. Create this folder:
   ```
   /KOBOeReader/.adds/dogear/
   ```
4. **Copy these files into it:**
   - `kobo-sync.sh` (from this repo's `kobo-sync/` folder)
   - `config.env` — copy `config.env.example`, rename to `config.env`, fill in:
     - `SUPABASE_URL` — from Supabase Settings → API
     - `SUPABASE_SERVICE_ROLE_KEY` — the **service_role** key (NOT the anon key). This bypasses RLS so the script can write to your account.
     - `USER_ID` — the UUID shown on the web app's `/account` page
   - `auto-sync-on-wifi.sh` (optional, for full auto-sync)
5. **Install the NickelMenu entry.** Copy `kobo-sync/nm_kobosync` into `/KOBOeReader/.adds/nm/` on the Kobo. (Create the `nm` folder if it doesn't exist.)
6. **Eject the Kobo.** On the device, tap the home icon — you'll now have a **Sync highlights** item in the menu. Tap it. Within 5 seconds, highlights should appear in your web app.

## Making it fully automatic (WiFi-triggered)

The simplest reliable auto-sync: install **KSM** (Kobo Start Menu) or use NickelDBus to launch `auto-sync-on-wifi.sh` at boot. The loop pings every 5 minutes and syncs when WiFi is up. See the NickelMenu wiki for examples.

## Troubleshooting

- **Nothing appears in the web app.** Open `/mnt/onboard/.adds/dogear/sync.log` on the Kobo via USB — it logs every run and any HTTP errors.
- **HTTP 401.** You used the anon key instead of the service_role key in `config.env`.
- **HTTP 404 `sync_highlights`.** The schema.sql wasn't run in Supabase. Re-run it.
- **Highlights sync but the book has no title.** Kobo builds its `content` table lazily. Tap the book to open it once on the Kobo — the title will populate on the next sync.

## Uninstalling

Delete these two folders from the Kobo and reboot:
- `/KOBOeReader/.adds/dogear/`
- `/KOBOeReader/.adds/nm/nm_kobosync`

To remove NickelMenu itself, see the NickelMenu uninstall instructions.
