# 3. Install sync on the Kobo

The stock reader stays in place. Nothing on your computer keeps running after the files are copied. The Kobo itself uploads highlights when Wi-Fi connects, and the menu can start a sync by hand.

These steps were checked with simulated Wi-Fi, a fake HTTP client, and an embedded Postgres. They were **not** run on a physical Kobo. Firmware **4.46.23852** was not executed here. The Wi-Fi rule matches `wlan*`, which is the interface name current 4.x stock firmware uses. The exact model is unknown; do not guess it from a serial number. If a later read-only look shows the Wi-Fi interface is not `wlan*`, the only line to change is the `KERNEL==` match in `kobo-sync/rootfs/etc/udev/rules.d/99-dogear-wifi.rules`, then rebuild `KoboRoot.tgz`.

## What was wrong with the previous install

- `nm_kobosync` put a space in `:quiet :sh ...`. NickelMenu passes the rest of the line to `sh -c`. That line starts a program named `quiet` and never runs `kobo-sync.sh`. The corrected line is `quiet:sh ...` with no space before `sh`.
- `auto-sync-on-wifi.sh` was an endless five-minute loop, and nothing in the install actually started it at boot or when Wi-Fi connected. The manual menu was the only trigger, and the menu entry did not launch the script.
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
| your own `config.env` | `.adds/dogear/config.env` |
| `user/nm_kobosync` | `.adds/nm/nm_kobosync` (overwrite the old file) |
| `KoboRoot.tgz` | `.kobo/KoboRoot.tgz` |

`KoboRoot.tgz` contains only `/usr/local/dogear/wifi-hook.sh` and `/etc/udev/rules.d/99-dogear-wifi.rules`. It has no token, no service key, and no database. NickelMenu is not inside it. Install NickelMenu separately from <https://pgaskin.net/NickelMenu/> if the Kobo does not already have it (firmware 4.6+; 4.46 is in that range). NickelMenu's own page says it persists across firmware updates. This Wi-Fi package does not. After a firmware update, copy `KoboRoot.tgz` into `.kobo` again. The `.adds` files remain, and the menu still works without the package.

## Before the USB copy

1. In the Supabase SQL editor, run `supabase/migrations/20261111_device_ingest.sql` if this project was created from an older `schema.sql`. A new project that already ran the current `schema.sql` can skip this. The migration does not delete highlights, notes, tags, or books.
2. Deploy or refresh the web app so `/account` includes **Create Kobo token**.
3. Create a token. Copy the three-line config. Paste the anon / public key over the placeholder. Do not add a service role key.
4. If a service role key was previously saved on the Kobo, regenerate that key in Supabase → Settings → API after the new config is in place. The old key is no longer needed for Dogear.

`config.env` looks like:

```
SUPABASE_URL="https://YOUR-PROJECT.supabase.co"
SUPABASE_ANON_KEY="the-anon-public-key"
DOGEAR_INGEST_TOKEN="dogear_..."
```

## USB install

1. Plug the Kobo in. The volume is named `KOBOeReader`. This is a copy you do by hand. Do not leave a helper running on the Mac.
2. If NickelMenu is missing, put its `KoboRoot.tgz` in `KOBOeReader/.kobo/` and eject. Wait for the reboot, then plug the Kobo in again. Do this before copying Dogear's `KoboRoot.tgz`, because the Kobo consumes one `KoboRoot.tgz` per reboot.
3. Create `KOBOeReader/.adds/dogear/` and copy the four script files plus `config.env`.
4. Overwrite `KOBOeReader/.adds/nm/nm_kobosync` with the new file. Leaving the old file in place keeps the broken menu command.
5. Copy Dogear's `KoboRoot.tgz` to `KOBOeReader/.kobo/KoboRoot.tgz`.
6. Eject and wait for the reboot.

Optional: `sh kobo-sync/build-installer.sh` refuses to touch a mounted Kobo unless `DOG_INSTALL_CONFIRM=yes` and `KOBO_MOUNT` points at a volume that already has a `.kobo` folder. It never reads or writes `KoboReader.sqlite`. Prefer the manual copy above unless you have looked at that script.

## On-device check

Do this on the Kobo after it has rebooted. It does not require the computer to stay connected.

1. Open the main menu. You should see **Dogear sync status** and **Dogear sync highlights**. The reader menu also has **Dogear sync highlights**.
2. Tap **Dogear sync status**. It should show `version=2` and either `config=ok` or a config error. It must not show the token, the anon key, or a service role key.
3. Turn Wi-Fi on, or tap **Dogear sync highlights** (that item asks Nickel to connect, then the script waits up to about 40 seconds for an address).
4. Tap **Dogear sync status** again. `result=ok` means the upload was accepted or there was nothing new. `result=auth` means the token was rejected. `result=offline` means no address or the server did not answer after three tries. `result=config` means `config.env` was refused.
5. Open the website. The book and highlight should be on the account that owns the token.

The script copies `KoboReader.sqlite` into RAM, reads highlight rows, deletes the copy, then uploads. It does not upload the database file. Do not copy `KoboReader.sqlite` off the device into chat, email, or git. It can contain the store login.

Over USB, `KOBOeReader/.adds/dogear/sync.log` and `last-status` are safe to read. They should not contain `eyJ` or `dogear_` followed by the secret. A redacted log is the useful diagnostic. A full database is not.

Highlights made while Wi-Fi is already connected wait until the next Wi-Fi connect or a manual sync. The trigger does not poll every few minutes. Below about 8% battery, automatic sync is skipped; the menu item still runs. A failed upload is retried at most three times in that attempt, then the script exits. The next Wi-Fi connect tries again. The same highlight is not inserted twice: the device skips unchanged rows, and the database keeps one row per account and Kobo bookmark id. A note edited on the Kobo is sent again. Website notes and favorites are left alone. An empty title from the device does not erase a title already stored.

## Rollback

Cloud highlights are not deleted by any of these steps.

1. On the Kobo, delete `.adds/nm/nm_kobosync` to remove the menu items.
2. Delete `.adds/dogear/kobo-sync.sh`. The Wi-Fi hook then exits without syncing. You can delete the whole `.adds/dogear` folder if you also want the local log and config gone. That does not remove anything in Supabase.
3. Revoke the token on the website account page.
4. On the server, `supabase/migrations/20261111_device_ingest_rollback.sql` drops the token table and the ingest function. It does not delete books or highlights, and it does not turn the old service-role RPC back on.

The inert udev hook remains until the next firmware update or until you install a firmware image that replaces `/etc`. It does nothing without `kobo-sync.sh`.

## If status is not ok

- `config=invalid` and the message mentions `SUPABASE_SERVICE_ROLE_KEY`: delete that line, regenerate the service role key, create a device token.
- `result=auth`: create a new token. The old one is revoked or the migration was not run.
- HTTP 404 in the log: run `supabase/migrations/20261111_device_ingest.sql` and wait for the API schema to reload.
- `result=offline` with Wi-Fi up: the address was not ready within the wait, or the server timed out. Toggle Wi-Fi or tap **Dogear sync highlights** again.
- Menu items missing: NickelMenu is not installed, or `nm_kobosync` was not overwritten.
- Highlights with no book title: open the book once on the Kobo so its library row exists, then sync again. A later sync will not blank a title that is already stored.
