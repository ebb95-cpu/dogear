#!/bin/sh
# Installed on the Kobo rootfs by KoboRoot.tgz.
# udev starts this when wlan* appears. udev kills a slow child unless the
# process detaches, so the first invocation only re-execs under setsid.
# The user partition is often mounted noexec; the sync script is run with sh.
# If the script has not been copied to the user partition, this exits without
# doing anything, which is also how uninstall works.

if [ "${DOG_UDEV_DETACHED:-}" != "1" ]; then
  DOG_UDEV_DETACHED=1 setsid /bin/sh "$0" "$@" </dev/null >>"${DOG_UDEV_LOG:-/tmp/dogear-udev.log}" 2>&1 &
  exit 0
fi

SYNC_SCRIPT="${DOG_SYNC_SCRIPT:-/mnt/onboard/.adds/dogear/kobo-sync.sh}"
i=0
limit=${DOG_MOUNT_WAIT:-15}
poll=${DOG_MOUNT_POLL:-2}
while [ "$i" -lt "$limit" ]; do
  if [ -f "$SYNC_SCRIPT" ]; then
    break
  fi
  i=$((i + 1))
  sleep "$poll"
done

if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "dogear: no sync script at $SYNC_SCRIPT; wifi hook is idle"
  exit 0
fi

exec /bin/sh "$SYNC_SCRIPT" wifi
