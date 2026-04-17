#!/bin/sh
# auto-sync-on-wifi.sh
# Optional: run kobo-sync.sh automatically whenever the Kobo connects to WiFi.
# Install by adding this line to /etc/init.d/rcS (via KSM) OR by installing it
# as a udev action. The simplest reliable approach on stock Nickel is to use
# NickelDBus and subscribe to wifi-up events; see docs/03-install-on-kobo.md.
#
# Here we just loop every 5 minutes while on WiFi.
ROOT="/mnt/onboard/.adds/dogear"

while true; do
  if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    sh "$ROOT/kobo-sync.sh" >/dev/null 2>&1 || true
  fi
  sleep 300
done
