# 3. Install sync on the Kobo

The stock reader stays in place. Nothing on your computer keeps running after the files are copied. The Kobo itself uploads highlights when Wi-Fi connects, and the menu can start a sync by hand.

These steps were checked with simulated Wi-Fi, a fake HTTP client, and an embedded Postgres. They were **not** run on a physical Kobo. Firmware **4.46.23852** was not executed here. The Wi-Fi rule matches `wlan*`, which is the interface name current 4.x stock firmware uses. The exact model is unknown; do not guess it from a serial number. If a later read-only look shows the Wi-Fi interface is not `wlan*`, the only line to change is the `KERNEL==` match in `kobo-sync/rootfs/etc/udev/rules.d/99-dogear-wifi.rules`, then rebuild `KoboRoot.tgz`.

## What was wrong with the previous install

- A read-only look on 12 Nov 2026 confirmed the menu line on the device: `menu_item :main :DogEars :cmd_spawn :quiet :sh /mnt/onboard/.adds/dogear/kobo-sync.sh`. The space after `quiet` makes NickelMenu run a program named `quiet`. The corrected prefix is `quiet:sh` with no space before `sh`.
- The same look found `sync.log` with only `sqlite3: not found` (17 Apr 2026). `state.synced` was empty, so nothing was uploaded. A `sqlite3` binary was already at `.adds/dogear/sqlite3`, and the script never called it. The repair copies that bundled file into `/tmp` and runs the copy, because the user partition is often mounted noexec. It still falls back to `sqlite3` on `PATH` when the bundle is absent.
- `auto-sync-on-wifi.sh` was an endless five-minute loop, and nothing in the install started it when Wi-Fi connected.
- The script required `curl`, `ping`, and SQLite `json_object()`. A SQLite error was treated as "no highlights". It also corrupted a batch that contained one highlight.
- `config.env` asked for the Supabase **service role** key. That key bypasses every account. The old `sync_highlights` function also trusted a user id sent by the device. The replacement uses a revocable per-account token. The anon key on the device is only the public API key.

## What you copy

From `kobo-sync/dist/` after `sh kobo-sync/build-installer.sh` (the repo already contains a built copy):

| On the computer | On the Kobo volume |
| --- | --- |
| `user/kobo-sync.sh` | `.adds/dogear/kobo-sync.sh` |
| `user/extract.awk` | `.adds/dogear/extract.awk` |
| `user/auto-sync-on-wifi.sh` | `.adds/dogear/auto-sync-on-wifi.sh` |
| `user/config.env.example` | `.adds/dogear/config.env.example` |
| your new `config.env` | `.adds/dogear/config.env` (replace the old file) |
| leave the existing file | `.adds/dogear/sqlite3` (do not delete or overwrite this) |
| `user/nm_kobosync` | `.adds/nm/nm_kobosync` (overwrite the old file) |
| `KoboRoot.tgz` | `.kobo/KoboRoot.tgz` |

`KoboRoot.tgz` contains only `/usr/local/dogear/wifi-hook.sh` and `/etc/udev/rules.d/99-dogear-wifi.rules`. It has no token, no service key, and no database. NickelMenu is not inside it. Install NickelMenu separately from <https://pgaskin.net/NickelMenu/> if the Kobo does not already have it (firmware 4.6+; 4.46 is in that range). NickelMenu's own page says it persists across firmware updates. This Wi-Fi package does not. After a firmware update, copy `KoboRoot.tgz` into `.kobo` again. The `.adds` files remain, and the menu still works without the package.

## Before the USB copy

1. In the Supabase SQL editor, run `supabase/migrations/20261111_device_ingest.sql` if this project was created from an older `schema.sql`. A new project that already ran the current `schema.sql` can skip this. The migration does not delete highlights, notes, tags, or books.
2. Deploy or refresh the web app so `/account` includes **Create Kobo token**.
3. Create a token. Copy the three-line config. Paste the anon / public key over the placeholder. Do not add a service role key.
4. The config already on the Kobo includes a service-role key. Treat that key as exposed. Regenerate it in Supabase → Settings → API. Do not copy the old `config.env` onto another machine or into git. The new file has the anon public key and `DOGEAR_INGEST_TOKEN` only.
5. Set the library address before copying the menu file. From the repo: `sh kobo-sync/stamp-library-url.sh https://your-deployed-app.vercel.app` then `sh kobo-sync/build-installer.sh`. That rewrites the Dogears browser item to `https://your-deployed-app.vercel.app/library`. The script does not read `config.env`.

`config.env` looks like:

```
SUPABASE_URL="https://YOUR-PROJECT.supabase.co"
SUPABASE_ANON_KEY="the-anon-public-key"
DOGEAR_INGEST_TOKEN="dogear_..."
```

## USB install on the Mac

The Kobo volume, when connected, is `/Volumes/KOBOeReader`. Copy these files by hand. Do not leave a helper running. Do not copy `KoboReader.sqlite` off the device. NickelMenu is already installed, so do not install it again. There is no real `KoboRoot.tgz` on the device right now (only an AppleDouble `._KoboRoot.tgz` leftover); copying Dogears' package into `.kobo/KoboRoot.tgz` is the right next file.

1. Finish the Supabase migration, the web deploy, the token, and `stamp-library-url.sh` before this copy. The library button opens whatever URL is in the menu file.
2. In Finder, show hidden files. Open `/Volumes/KOBOeReader/.adds/dogear/`.
3. Confirm `sqlite3` is still there. Leave it. Do not replace it with anything from this repo.
4. Copy `kobo-sync/dist/user/kobo-sync.sh`, `extract.awk`, and `auto-sync-on-wifi.sh` into that folder, replacing the old scripts. Copy the new `config.env` in as well, replacing the file that contains the service-role key.
5. Copy `kobo-sync/dist/user/nm_kobosync` over `/Volumes/KOBOeReader/.adds/nm/nm_kobosync`. If another file in `.adds/nm/` also contains `menu_main_15505_label`, remove that line. NickelMenu keeps the first label it reads.
6. Copy `kobo-sync/dist/KoboRoot.tgz` to `/Volumes/KOBOeReader/.kobo/KoboRoot.tgz`.
7. Eject and wait for the reboot. The reboot installs the Wi-Fi hook. The `.adds` files stay.

`sh kobo-sync/build-installer.sh` only writes the `dist/` folder on the Mac. It refuses to write to a mounted Kobo unless `DOG_INSTALL_CONFIRM=yes` and `KOBO_MOUNT` is set. Do not use that flag for this copy. It never reads or writes `KoboReader.sqlite`.

## On-device check

Do this on the Kobo after it has rebooted. It does not require the computer to stay connected.

1. The bottom-right tab should say **Dogears**, not NickelMenu. NickelMenu's own doc names this `experimental :menu_main_15505_label :Dogears`. The tab still opens a menu; that menu has one item, also **Dogears**. Tap it. With Wi-Fi up, the stock browser opens `/library` (All, Books, Today, Categories). Offline, that page cannot load. The reader does not keep a local copy of the library.
2. Sync and status are not on that tab. While reading, the overflow menu has **Sync** and **Status**. My Books has the same two items in its filter menu.
3. Tap **Status**. It should show `version=2` and either `config=ok` or a config error. It must not show the token, the anon key, or a service role key. The log should say `using bundled sqlite3`, not `sqlite3: not found`.
4. Tap **Sync** once, then **Status** again. `result=ok` means the upload was accepted or there was nothing new. `result=auth` means the token was rejected. `result=offline` means no address or the server did not answer after three tries. `result=config` means `config.env` was refused.
5. On the phone, open the same site, log in, and check Today, All, Books, and Categories. The highlight should belong to the account that owns the token.

The script copies `KoboReader.sqlite` into RAM, reads highlight rows, deletes the copy, then uploads. It does not upload the database file. Do not copy `KoboReader.sqlite` off the device into chat, email, or git. It can contain the store login.

Over USB, `KOBOeReader/.adds/dogear/sync.log` and `last-status` are safe to read. They should not contain `eyJ` or `dogear_` followed by the secret. A redacted log is the useful diagnostic. A full database is not.

Highlights made while Wi-Fi is already connected wait until the next Wi-Fi connect or a manual sync. The trigger does not poll every few minutes. Below about 8% battery, automatic sync is skipped; the menu item still runs. A failed upload is retried at most three times in that attempt, then the script exits. The next Wi-Fi connect tries again. The same highlight is not inserted twice: the device skips unchanged rows, and the database keeps one row per account and Kobo bookmark id. A note edited on the Kobo is sent again. Website notes and favorites are left alone. An empty title from the device does not erase a title already stored.

## Rollback

Cloud highlights are not deleted by any of these steps.

1. On the Kobo, delete `.adds/nm/nm_kobosync` to remove the menu items.
2. Delete `.adds/dogear/kobo-sync.sh`. The Wi-Fi hook then exits without syncing. You can delete the whole `.adds/dogear` folder if you also want the local log and config gone. That does not remove anything in Supabase. The `sqlite3` binary in that folder is only needed for sync; keep it if you might reinstall.
3. Revoke the token on the website account page.
4. On the server, `supabase/migrations/20261111_device_ingest_rollback.sql` drops the token table and the ingest function. It does not delete books or highlights, and it does not turn the old service-role RPC back on.

The inert udev hook remains until the next firmware update or until you install a firmware image that replaces `/etc`. It does nothing without `kobo-sync.sh`.

## If status is not ok

- `config=invalid` and the message mentions `SUPABASE_SERVICE_ROLE_KEY`: delete that line, regenerate the service role key, create a device token.
- `result=auth`: create a new token. The old one is revoked or the migration was not run.
- HTTP 404 in the log: run `supabase/migrations/20261111_device_ingest.sql` and wait for the API schema to reload.
- `result=offline` with Wi-Fi up: the address was not ready within the wait, or the server timed out. Toggle Wi-Fi or tap **Dogear sync highlights** again.
- The tab still says NickelMenu: the `experimental :menu_main_15505_label :Dogears` line is missing, another config file set the label first, or the Kobo has not rebooted since the file was copied.
- The log still says `sqlite3: not found`: `.adds/dogear/sqlite3` was deleted. Put that bundled binary back next to `kobo-sync.sh`.
- Menu items missing: NickelMenu is not installed, or `nm_kobosync` was not overwritten.
- Highlights with no book title: open the book once on the Kobo so its library row exists, then sync again. A later sync will not blank a title that is already stored.
