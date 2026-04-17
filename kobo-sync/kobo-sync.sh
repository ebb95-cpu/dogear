#!/bin/sh
# kobo-sync.sh
# Reads highlights from .kobo/KoboReader.sqlite and POSTs new ones to Supabase.
# Runs on the Kobo itself (BusyBox ash shell).
#
# Config file expected at /mnt/onboard/.adds/dogear/config.env with:
#   SUPABASE_URL=https://YOUR-PROJECT.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY=eyJ...           (use the SERVICE ROLE key; stays on-device)
#   USER_ID=your-uuid-from-the-web-app-account-page
#
# State (already-synced BookmarkIDs) lives in $STATE so re-syncs are idempotent.

ROOT="/mnt/onboard/.adds/dogear"
CFG="$ROOT/config.env"
STATE="$ROOT/state.synced"
LOG="$ROOT/sync.log"
DB="/mnt/onboard/.kobo/KoboReader.sqlite"
TMP="$ROOT/.sync.tmp"

log() { echo "[$(date -u +%FT%TZ)] $*" >> "$LOG"; }

if [ ! -f "$CFG" ]; then echo "missing $CFG" >&2; exit 1; fi
. "$CFG"

mkdir -p "$TMP"
touch "$STATE"

# Wait briefly for wifi
i=0; while [ $i -lt 10 ]; do
  if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then break; fi
  sleep 2; i=$((i+1))
done

# Export all highlights as JSON directly from sqlite3.
# We use json_object() (available in sqlite >= 3.9, which Kobo ships with).
BOOKS_JSON=$(sqlite3 "$DB" <<'SQL'
SELECT '[' || group_concat(json_object(
  'kobo_content_id', VolumeID,
  'title',           COALESCE(Title,''),
  'author',          COALESCE(Attribution,'')
)) || ']'
FROM (
  SELECT DISTINCT b.VolumeID, c.Title, c.Attribution
  FROM Bookmark b LEFT JOIN content c ON c.ContentID = b.VolumeID
  WHERE (b.Type = 'highlight' OR b.Type IS NULL)
);
SQL
)

ALL_HIGHS_JSON=$(sqlite3 "$DB" <<'SQL'
SELECT '[' || group_concat(json_object(
  'kobo_bookmark_id', BookmarkID,
  'kobo_content_id',  VolumeID,
  'text',             COALESCE(Text,''),
  'annotation',       COALESCE(Annotation,''),
  'chapter',          COALESCE(CAST(ChapterProgress AS TEXT),''),
  'highlighted_at',   COALESCE(DateCreated,'')
)) || ']'
FROM Bookmark
WHERE (Type = 'highlight' OR Type IS NULL);
SQL
)

if [ -z "$ALL_HIGHS_JSON" ] || [ "$ALL_HIGHS_JSON" = "[]" ]; then
  log "no highlights in DB"; exit 0
fi

# Filter out already-synced bookmarks using a tiny python/awk.
# Kobo ships BusyBox awk; no python. Use awk.
NEW_HIGHS_JSON=$(
  printf '%s' "$ALL_HIGHS_JSON" | awk -v state="$STATE" '
  BEGIN {
    # Read state file (one BookmarkID per line)
    while ((getline line < state) > 0) seen[line] = 1
    close(state)
  }
  {
    # Split the JSON array at "},{" boundaries (safe because individual JSON objects
    # from json_object() never contain unescaped "},{" — values are JSON-escaped).
    raw = $0
    sub(/^\[/, "", raw); sub(/\]$/, "", raw)
    n = split(raw, objs, /\},\{/)
    out = ""
    for (i = 1; i <= n; i++) {
      obj = objs[i]
      if (i == 1) obj = obj "}"
      else if (i == n) obj = "{" obj
      else obj = "{" obj "}"
      # Extract kobo_bookmark_id
      if (match(obj, /"kobo_bookmark_id":"[^"]*"/)) {
        id = substr(obj, RSTART + 20, RLENGTH - 21)  # strip "kobo_bookmark_id":" and trailing "
        if (!(id in seen)) {
          out = out (out == "" ? "" : ",") obj
          new_ids[++nn] = id
        }
      }
    }
    printf "%s", "[" out "]"
    # Append newly-synced IDs to state (printed on stderr so caller can capture)
    for (i = 1; i <= nn; i++) print new_ids[i] > "/dev/stderr"
  }' 2> "$TMP/new_ids.txt"
)

if [ "$NEW_HIGHS_JSON" = "[]" ]; then
  log "no new highlights"
  exit 0
fi

# Build the RPC payload.
PAYLOAD=$(printf '{"p_user_id":"%s","p_books":%s,"p_highlights":%s}' \
  "$USER_ID" "$BOOKS_JSON" "$NEW_HIGHS_JSON")

printf '%s' "$PAYLOAD" > "$TMP/payload.json"

HTTP=$(curl -sS -o "$TMP/response.json" -w "%{http_code}" \
  -X POST "$SUPABASE_URL/rest/v1/rpc/sync_highlights" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "content-type: application/json" \
  --data-binary "@$TMP/payload.json")

if [ "$HTTP" = "200" ] || [ "$HTTP" = "204" ]; then
  # Commit state: append the new bookmark IDs
  cat "$TMP/new_ids.txt" >> "$STATE"
  log "synced OK (http $HTTP); $(wc -l < "$TMP/new_ids.txt" | tr -d ' ') new highlights"
else
  log "FAILED http $HTTP: $(cat "$TMP/response.json" 2>/dev/null)"
  exit 1
fi
