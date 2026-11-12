#!/bin/sh
# Build the Kobo Wi-Fi trigger package and, only when explicitly confirmed,
# copy the user-partition files onto a mounted Kobo volume.
# This script never reads or writes KoboReader.sqlite.

if [ -n "${KOBO_MOUNT:-}" ] && [ "${DOG_INSTALL_CONFIRM:-}" != "yes" ]; then
  echo "Refusing to write to KOBO_MOUNT without DOG_INSTALL_CONFIRM=yes" >&2
  exit 2
fi

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
dist="$here/dist"
rm -rf "$dist"
mkdir -p "$dist/user"
chmod 755 "$here/rootfs/usr/local/dogear/wifi-hook.sh"
chmod 644 "$here/rootfs/etc/udev/rules.d/99-dogear-wifi.rules"
tar --format=ustar -czf "$dist/KoboRoot.tgz" -C "$here/rootfs" etc usr
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$dist/KoboRoot.tgz" > "$dist/KoboRoot.tgz.sha256"
fi
cp "$here/kobo-sync.sh" "$here/extract.awk" "$here/auto-sync-on-wifi.sh" \
  "$here/config.env.example" "$dist/user/"
cp "$here/nm_kobosync" "$dist/user/nm_kobosync"
cat > "$dist/INSTALL.txt" <<'EOF'
Dogear Kobo installer

KoboRoot.tgz only adds a Wi-Fi trigger under /usr/local/dogear and
/etc/udev/rules.d. It contains no config, no database, and no API key.
The user/ folder is what goes on the visible Kobo volume.

Follow docs/03-install-on-kobo.md for the full install, the on-device
checks, and rollback. Short version:

1. Run supabase/migrations/20261111_device_ingest.sql in the Supabase SQL editor.
2. On the website account page, create a Kobo token. Put SUPABASE_URL, the
   anon public key, and DOGEAR_INGEST_TOKEN in config.env. Do not put a
   service role key on the Kobo. If one was stored there before, regenerate it.
3. Copy user/kobo-sync.sh, extract.awk, auto-sync-on-wifi.sh, and config.env
   to KOBOeReader/.adds/dogear/ (create the folder). Do not copy a filled
   config over USB from a shared machine without checking who can read it.
4. Overwrite KOBOeReader/.adds/nm/nm_kobosync with user/nm_kobosync.
5. If NickelMenu is not already installed, install it from
   https://pgaskin.net/NickelMenu/ and reboot before this package.
6. Copy KoboRoot.tgz to KOBOeReader/.kobo/KoboRoot.tgz and eject. The Kobo
   reboots and installs the trigger. This is the same install channel
   NickelMenu uses. It does not replace the stock reader.
7. On the Kobo, open Dogear sync status. It must not show the token or any
   key. Then Dogear sync highlights, then status again.
8. After a firmware update, copy KoboRoot.tgz into .kobo again. The files in
   .adds stay. The menu still works if the trigger was wiped.

Rollback without another reboot package: delete .adds/nm/nm_kobosync and
.adds/dogear/kobo-sync.sh. The Wi-Fi hook then does nothing. Cloud highlights
are not deleted. To drop tokens on the server, run the rollback SQL, which
also does not delete highlights.

Do not copy KoboReader.sqlite off the device into chat, email, or git.
EOF

if [ -z "${KOBO_MOUNT:-}" ]; then
  echo "built $dist"
  exit 0
fi

case "$KOBO_MOUNT" in
  /|"")
    echo "Refusing KOBO_MOUNT=$KOBO_MOUNT" >&2
    exit 2
    ;;
esac
if [ ! -d "$KOBO_MOUNT/.kobo" ]; then
  echo "Refusing: $KOBO_MOUNT has no .kobo folder, so it does not look like a Kobo volume" >&2
  exit 2
fi

mkdir -p "$KOBO_MOUNT/.adds/dogear" "$KOBO_MOUNT/.adds/nm"
cp "$dist/user/kobo-sync.sh" "$dist/user/extract.awk" \
  "$dist/user/auto-sync-on-wifi.sh" "$dist/user/config.env.example" \
  "$KOBO_MOUNT/.adds/dogear/"
cp "$dist/user/nm_kobosync" "$KOBO_MOUNT/.adds/nm/nm_kobosync"
cp "$dist/KoboRoot.tgz" "$KOBO_MOUNT/.kobo/KoboRoot.tgz"
echo "copied scripts and KoboRoot.tgz onto $KOBO_MOUNT"
echo "config.env was not modified. KoboReader.sqlite was not read or written."
