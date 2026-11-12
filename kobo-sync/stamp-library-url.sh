#!/bin/sh
# Replace the library placeholder in the NickelMenu file.
# Usage: sh kobo-sync/stamp-library-url.sh https://your-app.vercel.app
# Does not read config.env and does not touch a Kobo volume.

url=${1:-}
case "$url" in
  https://*.*) ;;
  *)
    echo "usage: sh stamp-library-url.sh https://your-app.vercel.app" >&2
    exit 1
    ;;
esac
case "$url" in
  *[\ \'\"\;\|\&\<\>]*)
    echo "library URL has unsupported characters" >&2
    exit 1
    ;;
esac
while :; do
  case "$url" in
    */) url=${url%/} ;;
    *) break ;;
  esac
done

here=$(CDPATH= cd "$(dirname "$0")" && pwd)
placeholder='https://YOUR-DOGEARS-APP.example'
changed=0
for f in "$here/nm_kobosync" "$here/dist/user/nm_kobosync"; do
  if [ ! -f "$f" ]; then
    continue
  fi
  tmp="$f.tmp"
  awk -v old="$placeholder" -v new="$url" '
    function swap(s,    i, out) {
      out = ""
      while ((i = index(s, old)) > 0) {
        out = out substr(s, 1, i - 1) new
        s = substr(s, i + length(old))
      }
      return out s
    }
    { print swap($0) }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  changed=1
done

if [ "$changed" -ne 1 ]; then
  echo "nm_kobosync not found" >&2
  exit 1
fi
echo "library URL set to $url/library"
