#!/bin/sh
# Compatibility entry point. Older instructions said to loop forever and ping
# every five minutes. That loop is not installed by anything in this repo, and
# it would keep the radio working while the device is asleep on a charger.
# This file now performs one wifi-triggered attempt and exits.
# Prefer the udev hook in KoboRoot.tgz, which runs this only when Wi-Fi comes up.

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
exec /bin/sh "$here/kobo-sync.sh" wifi
