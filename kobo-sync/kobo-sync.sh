#!/bin/sh
# Dogear on-device sync for the stock Kobo reader.
# POSIX sh. Reads highlight rows from KoboReader.sqlite and POSTs them to
# the ingest_highlights RPC. A per-account token chooses the user. The
# service-role key is refused if it is present in config.env.
#
#   sh kobo-sync.sh manual   force one sync (NickelMenu)
#   sh kobo-sync.sh wifi     one sync after Wi-Fi comes up (udev)
#   sh kobo-sync.sh status   redacted status for the on-device menu
#   sh kobo-sync.sh self-test
#
# State, logs, and config live under /mnt/onboard/.adds/dogear.
# A short-lived database copy is made in /tmp and removed before any HTTP
# request. The full database is never uploaded.

umask 077

VERSION=2

redact() {
  awk '
    {
      gsub(/dogear_[A-Za-z0-9_-]+/, "dogear_[redacted]")
      gsub(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, "[redacted-jwt]")
      gsub(/sb_secret_[A-Za-z0-9_-]+/, "[redacted-secret]")
      gsub(/sb_publishable_[A-Za-z0-9_-]+/, "[redacted-publishable]")
      print
    }
  '
}

clip() {
  awk '
    BEGIN { left = 300 }
    {
      if (left <= 0) exit
      s = $0
      if (length(s) > left) s = substr(s, 1, left)
      print s
      left = left - length(s) - 1
    }
  '
}

log() {
  [ -n "${LOG:-}" ] || return 0
  printf '%s\n' "$*" | redact >> "$LOG"
}

jwt_payload() {
  # Decode the middle segment of a JWT without sending it anywhere.
  printf '%s\n' "$1" | awk -F. 'NR == 1 { print $2 }' | awk '
    BEGIN { B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" }
    function b64dec(s,    i, n, out, c1, c2, c3, c4, b3, b4, v1, v2, v3, pad) {
      gsub(/-/, "+", s)
      gsub(/_/, "/", s)
      pad = length(s) % 4
      if (pad == 2) s = s "=="
      else if (pad == 3) s = s "="
      else if (pad == 1) return ""
      n = length(s)
      out = ""
      for (i = 1; i <= n; i += 4) {
        c1 = index(B64, substr(s, i, 1)) - 1
        c2 = index(B64, substr(s, i + 1, 1)) - 1
        if (substr(s, i + 2, 1) == "=") { b3 = -1; c3 = 0 }
        else { c3 = index(B64, substr(s, i + 2, 1)) - 1; b3 = c3 }
        if (substr(s, i + 3, 1) == "=") { b4 = -1; c4 = 0 }
        else { c4 = index(B64, substr(s, i + 3, 1)) - 1; b4 = c4 }
        if (c1 < 0 || c2 < 0) return ""
        v1 = int(c1 * 4 + int(c2 / 16))
        out = out sprintf("%c", v1)
        if (b3 >= 0) {
          v2 = int((c2 % 16) * 16 + int(c3 / 4))
          out = out sprintf("%c", v2)
        }
        if (b4 >= 0) {
          v3 = int((c3 % 4) * 64 + c4)
          out = out sprintf("%c", v3)
        }
      }
      return out
    }
    { printf "%s", b64dec($0) }
  '
}

trim_ends() {
  printf '%s' "$1" | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'
}

load_config() {
  cfg=$1
  SUPABASE_URL=
  SUPABASE_ANON_KEY=
  DOGEAR_INGEST_TOKEN=
  config_error=
  service_role_found=0
  ignored_user_id=0
  if [ ! -f "$cfg" ]; then
    config_error="missing config.env"
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in
      ''|'#'*) continue ;;
    esac
    case "$line" in
      *';'*|*'|'*|*'&'*|*'<'*|*'>'*|*'`'*|*'$(*)'*|*'$('*|*'${'*)
        config_error="config contains unsupported characters and was not loaded"
        return 1
        ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    key=$(printf '%s' "$key" | tr -d ' \t')
    val=$(trim_ends "$val")
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    if printf '%s' "$val" | awk 'BEGIN { bad = 0 } { if (index($0, "\047") || index($0, "\"")) bad = 1 } END { exit bad }'; then
      :
    else
      config_error="config values cannot contain quotes"
      return 1
    fi
    case "$key" in
      SUPABASE_URL) SUPABASE_URL=$val ;;
      SUPABASE_ANON_KEY) SUPABASE_ANON_KEY=$val ;;
      DOGEAR_INGEST_TOKEN) DOGEAR_INGEST_TOKEN=$val ;;
      USER_ID) ignored_user_id=1 ;;
      SUPABASE_SERVICE_ROLE_KEY)
        if [ -n "$val" ]; then service_role_found=1; fi
        ;;
      *)
        config_error="unknown config key"
        return 1
        ;;
    esac
  done < "$cfg"

  if [ "$service_role_found" -eq 1 ]; then
    config_error="SUPABASE_SERVICE_ROLE_KEY is set. Remove it, regenerate that key in Supabase, and use a device ingest token."
    return 1
  fi

  case "$SUPABASE_URL" in
    https://*) ;;
    *) config_error="SUPABASE_URL must start with https://"; return 1 ;;
  esac
  while :; do
    case "$SUPABASE_URL" in
      */) SUPABASE_URL=${SUPABASE_URL%/} ;;
      *) break ;;
    esac
  done
  slashes=$(printf '%s' "$SUPABASE_URL" | awk -F/ '{ print NF - 1 }')
  if [ "$slashes" -ne 2 ]; then
    config_error="SUPABASE_URL must be https://host with no path"
    return 1
  fi
  host=${SUPABASE_URL#https://}
  case "$host" in
    *.*) ;;
    *) config_error="SUPABASE_URL host is not valid"; return 1 ;;
  esac
  case "$host" in
    *[!A-Za-z0-9.-]*) config_error="SUPABASE_URL host is not valid"; return 1 ;;
  esac

  case "$SUPABASE_ANON_KEY" in
    sb_secret_*|sb_service_*)
      config_error="SUPABASE_ANON_KEY is a secret key. Use the anon / public key."
      return 1
      ;;
    sb_publishable_*) ;;
    eyJ*)
      claims=$(jwt_payload "$SUPABASE_ANON_KEY")
      case "$claims" in
        *service_role*)
          config_error="SUPABASE_ANON_KEY is a service role key. Use the anon / public key and regenerate the service role key."
          return 1
          ;;
        *'"role":"anon"'*) ;;
        *)
          config_error="SUPABASE_ANON_KEY is not an anon public key"
          return 1
          ;;
      esac
      ;;
    *)
      config_error="SUPABASE_ANON_KEY is missing or not a public key"
      return 1
      ;;
  esac

  case "$DOGEAR_INGEST_TOKEN" in
    dogear_*) ;;
    eyJ*)
      config_error="DOGEAR_INGEST_TOKEN looks like a JWT. Create a device token on the account page."
      return 1
      ;;
    *)
      config_error="DOGEAR_INGEST_TOKEN must be a dogear_ token from the account page"
      return 1
      ;;
  esac
  rest=${DOGEAR_INGEST_TOKEN#dogear_}
  case "$rest" in
    *[!A-Za-z0-9_-]*)
      config_error="DOGEAR_INGEST_TOKEN has unsupported characters"
      return 1
      ;;
  esac
  if [ "${#DOGEAR_INGEST_TOKEN}" -lt 40 ] || [ "${#DOGEAR_INGEST_TOKEN}" -gt 200 ]; then
    config_error="DOGEAR_INGEST_TOKEN length is not valid"
    return 1
  fi
  if [ "$ignored_user_id" -eq 1 ] && [ "${mode:-}" != "status" ]; then
    log "ignoring USER_ID; the ingest token selects the account"
  fi
  return 0
}

wifi_is_up() {
  if [ -n "${DOG_WIFI_FILE:-}" ]; then
    [ "$(tr -d ' \t\r\n' < "$DOG_WIFI_FILE")" = "up" ]
    return $?
  fi
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show 2>/dev/null | awk '
      $1 == "inet" {
        split($2, a, "/")
        if (a[1] != "" && a[1] != "127.0.0.1" && a[1] !~ /^169\.254\./) ok = 1
      }
      END { exit !ok }
    '
    return $?
  fi
  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '
      /inet addr:/ {
        split($2, a, ":")
        if (a[2] != "" && a[2] != "127.0.0.1" && a[2] !~ /^169\.254\./) ok = 1
      }
      $1 == "inet" && $2 ~ /^[0-9]/ {
        split($2, a, "/")
        if (a[1] != "127.0.0.1" && a[1] !~ /^169\.254\./) ok = 1
      }
      END { exit !ok }
    '
    return $?
  fi
  return 1
}

wait_for_wifi() {
  max=${DOG_WIFI_WAIT:-40}
  poll=${DOG_WIFI_POLL:-2}
  start=$(date +%s)
  while :; do
    if wifi_is_up; then
      return 0
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge "$max" ]; then
      return 1
    fi
    sleep "$poll"
  done
}

battery_low() {
  f=${DOG_BATTERY_FILE:-}
  if [ -z "$f" ]; then
    for c in /sys/class/power_supply/*/capacity; do
      if [ -f "$c" ]; then
        f=$c
        break
      fi
    done
  fi
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    return 1
  fi
  val=$(tr -cd '0-9' < "$f")
  if [ -z "$val" ]; then
    return 1
  fi
  [ "$val" -lt 8 ]
}

arm_cooldown() {
  secs=$1
  if [ "$secs" -le 0 ]; then
    rm -f "$ROOT/next-allowed.epoch"
    return 0
  fi
  now=$(date +%s)
  printf '%s\n' $((now + secs)) > "$ROOT/next-allowed.epoch"
}

cooldown_active() {
  [ "$mode" = "wifi" ] || return 1
  [ -f "$ROOT/next-allowed.epoch" ] || return 1
  next=$(tr -cd '0-9' < "$ROOT/next-allowed.epoch")
  [ -n "$next" ] || return 1
  now=$(date +%s)
  [ "$now" -lt "$next" ]
}

write_status() {
  result=$1
  http=$2
  uploaded=$3
  message=$4
  message=$(printf '%s' "$message" | redact | tr '\n' ' ' | clip)
  {
    printf 'version=%s\n' "$VERSION"
    printf 'time=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'trigger=%s\n' "$mode"
    printf 'result=%s\n' "$result"
    printf 'http=%s\n' "$http"
    printf 'uploaded=%s\n' "$uploaded"
    printf 'message=%s\n' "$message"
  } > "$ROOT/last-status"
}

rotate_log() {
  if [ ! -f "$LOG" ]; then
    return 0
  fi
  bytes=$(wc -c < "$LOG" | tr -d ' ')
  if [ "$bytes" -gt 65536 ]; then
    tail -c 32768 "$LOG" > "$LOG.rot" && mv "$LOG.rot" "$LOG"
  fi
}

acquire_lock() {
  LOCKDIR=${DOG_LOCK_DIR:-/tmp/dogear-sync.lock}
  if mkdir "$LOCKDIR" 2>/dev/null; then
    date +%s > "$LOCKDIR/started"
    return 0
  fi
  started=$(cat "$LOCKDIR/started" 2>/dev/null || echo 0)
  now=$(date +%s)
  stale=${DOG_LOCK_STALE:-300}
  if [ $((now - started)) -gt "$stale" ]; then
    rm -rf "$LOCKDIR"
    if mkdir "$LOCKDIR" 2>/dev/null; then
      date +%s > "$LOCKDIR/started"
      return 0
    fi
  fi
  LOCKDIR=
  return 1
}

cleanup() {
  if [ -n "${work:-}" ] && [ -d "$work" ]; then
    rm -rf "$work"
  fi
  if [ -n "${LOCKDIR:-}" ] && [ -d "$LOCKDIR" ]; then
    rm -rf "$LOCKDIR"
  fi
}

nth_backoff() {
  n=$1
  rest=${DOG_BACKOFF:-5 15}
  i=1
  oldifs=$IFS
  IFS=' '
  for s in $rest; do
    if [ "$i" -eq "$n" ]; then
      IFS=$oldifs
      printf '%s\n' "$s"
      return 0
    fi
    i=$((i + 1))
  done
  IFS=$oldifs
  printf '%s\n' 5
}

pick_client() {
  choice=${DOG_HTTP_CLIENT:-auto}
  case "$choice" in
    curl|wget) printf '%s' "$choice" ;;
    *)
      if command -v curl >/dev/null 2>&1; then
        printf '%s' curl
      elif command -v wget >/dev/null 2>&1; then
        printf '%s' wget
      else
        printf '%s' none
      fi
      ;;
  esac
}

http_post() {
  body=$1
  dest=$2
  : > "$dest"
  url="$SUPABASE_URL/rest/v1/rpc/ingest_highlights"
  client=$(pick_client)
  if [ "$client" = "curl" ]; then
    if ! command -v curl >/dev/null 2>&1; then
      printf '000'
      return 0
    fi
    code=$(curl -sS --max-time "${DOG_HTTP_TIMEOUT:-25}" \
      -o "$dest" -w "%{http_code}" \
      -X POST "$url" \
      -H "apikey: $SUPABASE_ANON_KEY" \
      -H "authorization: Bearer $SUPABASE_ANON_KEY" \
      -H "content-type: application/json" \
      -H "accept: application/json" \
      --data-binary "@$body" 2>"$work/http.err") || code=000
    printf '%s' "$code"
    return 0
  fi
  if [ "$client" = "wget" ]; then
    if ! command -v wget >/dev/null 2>&1; then
      printf '000'
      return 0
    fi
    if ! wget --help 2>&1 | grep -q post-file; then
      log "wget has no --post-file; refusing to put the token on the command line"
      printf '000'
      return 0
    fi
    wget -S -T "${DOG_HTTP_TIMEOUT:-25}" -O "$dest" \
      --header="apikey: $SUPABASE_ANON_KEY" \
      --header="authorization: Bearer $SUPABASE_ANON_KEY" \
      --header="content-type: application/json" \
      --post-file="$body" \
      "$url" >"$work/wget.out" 2>"$work/wget.err"
    code=$(awk '/HTTP\// { c = $2 } END { gsub(/\r/, "", c); print c }' "$work/wget.err")
    if [ -z "$code" ]; then
      code=000
    fi
    printf '%s' "$code"
    return 0
  fi
  printf '000'
}

post_with_retries() {
  body=$1
  attempt=1
  max=${DOG_RETRIES:-3}
  while [ "$attempt" -le "$max" ]; do
    code=$(http_post "$body" "$work/response.json")
    case "$code" in
      200|204)
        printf '%s' "$code"
        return 0
        ;;
      400|401|403|404|409|422)
        printf '%s' "$code"
        return 2
        ;;
      *)
        if [ "$attempt" -ge "$max" ]; then
          printf '%s' "$code"
          return 1
        fi
        pause=$(nth_backoff "$attempt")
        log "http $code; retry $attempt"
        sleep "$pause"
        attempt=$((attempt + 1))
        ;;
    esac
  done
  printf '000'
  return 1
}

merge_state() {
  old=$1
  add=$2
  tmp="$old.tmp"
  awk -v old="$old" -v add="$add" '
    function load(file,    line, tab) {
      while ((getline line < file) > 0) {
        tab = index(line, "\t")
        if (tab > 0) seen[substr(line, tab + 1)] = substr(line, 1, tab - 1)
      }
      close(file)
    }
    BEGIN {
      load(old)
      load(add)
      for (id in seen) printf "%s\t%s\n", seen[id], id
    }
  ' > "$tmp" && mv "$tmp" "$old"
}

col_present() {
  info=$1
  name=$2
  printf '%s\n' "$info" | awk -F'|' -v n="$name" 'BEGIN { n = tolower(n) } tolower($2) == n { f = 1 } END { exit !f }'
}

build_query() {
  db=$1
  out=$2
  bookmark_info=$(sqlite3 -batch -noheader "$db" "PRAGMA table_info(Bookmark);")
  if ! printf '%s\n' "$bookmark_info" | awk -F'|' 'tolower($2)=="bookmarkid"{f=1} END{exit !f}'; then
    return 1
  fi
  if ! printf '%s\n' "$bookmark_info" | awk -F'|' 'tolower($2)=="volumeid"{f=1} END{exit !f}'; then
    return 1
  fi
  if ! printf '%s\n' "$bookmark_info" | awk -F'|' 'tolower($2)=="text"{f=1} END{exit !f}'; then
    return 1
  fi

  qtext="quote(coalesce(b.Text, ''))"
  if col_present "$bookmark_info" Annotation; then
    qann="quote(coalesce(b.Annotation, ''))"
    ann_where="length(trim(coalesce(b.Annotation, ''))) > 0"
  else
    qann="quote('')"
    ann_where="0"
  fi
  if col_present "$bookmark_info" DateCreated; then
    qdate="quote(coalesce(b.DateCreated, ''))"
  else
    qdate="quote('')"
  fi
  if col_present "$bookmark_info" ChapterProgress; then
    qprog="quote(coalesce(CAST(b.ChapterProgress AS TEXT), ''))"
  else
    qprog="quote('')"
  fi
  if col_present "$bookmark_info" Type; then
    qtype="quote(coalesce(b.Type, ''))"
    type_where="AND (b.Type IS NULL OR lower(b.Type) <> 'dogear')"
  else
    qtype="quote('')"
    type_where=
  fi
  if col_present "$bookmark_info" ContentID; then
    qcontent="quote(coalesce(b.ContentID, ''))"
    has_contentid=1
  else
    qcontent="quote('')"
    has_contentid=0
  fi
  hidden_where=
  if col_present "$bookmark_info" Hidden; then
    hidden_where="AND coalesce(b.Hidden, 0) NOT IN (1, '1', 'true')"
  fi

  content_name=$(sqlite3 -batch -noheader "$db" "SELECT name FROM sqlite_master WHERE type = 'table' AND lower(name) = 'content' LIMIT 1;")
  case "$content_name" in
    content|Content) ;;
    *) content_name= ;;
  esac
  qtitle="quote('')"
  qauthor="quote('')"
  joins=
  qchapter="quote('')"
  if [ -n "$content_name" ]; then
    content_info=$(sqlite3 -batch -noheader "$db" "PRAGMA table_info(content);")
    if col_present "$content_info" Title; then
      qtitle="quote(coalesce(book.Title, ''))"
      if [ "$has_contentid" -eq 1 ]; then
        qchapter="quote(coalesce(ch.Title, ''))"
      fi
    fi
    if col_present "$content_info" Attribution; then
      qauthor="quote(coalesce(book.Attribution, ''))"
    elif col_present "$content_info" Author; then
      qauthor="quote(coalesce(book.Author, ''))"
    fi
    joins="LEFT JOIN content book ON book.ContentID = b.VolumeID"
    if [ "$has_contentid" -eq 1 ] && col_present "$content_info" Title; then
      joins="$joins
LEFT JOIN content ch ON ch.ContentID = b.ContentID AND b.ContentID <> b.VolumeID"
    fi
  fi

  cat > "$out" <<EOF
SELECT
  quote(coalesce(b.BookmarkID, '')),
  quote(coalesce(b.VolumeID, '')),
  $qtext,
  $qann,
  $qdate,
  $qchapter,
  $qprog,
  $qtitle,
  $qauthor,
  $qtype,
  $qcontent
FROM Bookmark b
$joins
WHERE b.BookmarkID IS NOT NULL
  AND b.VolumeID IS NOT NULL
  AND (length(trim(coalesce(b.Text, ''))) > 0 OR $ann_where)
  $hidden_where
  $type_where
ORDER BY b.BookmarkID;
EOF
}

extract_highlights() {
  src=$1
  parent=${DOG_WORK_PARENT:-/tmp}
  if command -v mktemp >/dev/null 2>&1; then
    work=$(mktemp -d "$parent/dogear.XXXXXX")
  else
    work="$parent/dogear.$$"
    mkdir -m 700 "$work" || return 1
  fi
  mkdir -p "$work/out"
  copy="$work/read.sqlite"
  if ! sqlite3 "$src" ".backup $copy" >"$work/backup.err" 2>&1; then
    log "could not copy the highlight database"
    log "$(redact < "$work/backup.err" | clip)"
    rm -f "$copy"
    return 1
  fi
  if ! build_query "$copy" "$work/query.sql"; then
    log "database has no Bookmark table with highlight columns"
    rm -f "$copy"
    return 1
  fi
  sep=$(printf '\034')
  sqlite3 -batch -noheader -separator "$sep" -cmd "PRAGMA query_only = ON;" "$copy" \
    "$(cat "$work/query.sql")" >"$work/rows.txt" 2>"$work/sql.err"
  qrc=$?
  rm -f "$copy" "$copy-wal" "$copy-shm"
  if [ "$qrc" -ne 0 ]; then
    log "highlight query failed"
    log "$(redact < "$work/sql.err" | clip)"
    return 1
  fi
  if [ -n "${DOG_DEBUG_DIR:-}" ]; then
    mkdir -p "$DOG_DEBUG_DIR"
    cp "$work/rows.txt" "$DOG_DEBUG_DIR/rows.txt" 2>/dev/null || true
  fi
  stats=$(awk -f "$AWK" -v statefile="$STATE" -v outdir="$work/out" -v batchsize="${DOG_BATCH:-20}" "$work/rows.txt" 2>"$work/awk.err")
  arc=$?
  if [ "$arc" -ne 0 ]; then
    log "extract formatter failed"
    log "$(redact < "$work/awk.err" | clip)"
    return 1
  fi
  case "$stats" in
    pending\ *) ;;
    *)
      log "extract formatter returned no summary"
      return 1
      ;;
  esac
  if [ -n "${DOG_DEBUG_DIR:-}" ]; then
    cp "$work"/out/batch-*.json "$DOG_DEBUG_DIR/" 2>/dev/null || true
    printf '%s\n' "$stats" > "$DOG_DEBUG_DIR/stats.txt"
  fi
  pending=$(printf '%s\n' "$stats" | awk '/^pending / { print $2 }')
  skipped=$(printf '%s\n' "$stats" | awk '/^pending / { print $4 }')
  batches=$(printf '%s\n' "$stats" | awk '/^pending / { print $6 }')
  errors=$(printf '%s\n' "$stats" | awk '/^pending / { print $8 }')
  log "extract pending=${pending:-0} skipped=${skipped:-0} batches=${batches:-0} errors=${errors:-0}"
  if [ -s "$work/awk.err" ]; then
    log "$(redact < "$work/awk.err" | clip)"
  fi
  if [ "${errors:-0}" -gt 0 ] && [ "${pending:-0}" -eq 0 ]; then
    return 1
  fi
  return 0
}

upload_batches() {
  uploaded=0
  last_http=
  for fp in "$work"/out/batch-*.fp; do
    [ -f "$fp" ] || continue
    json=${fp%.fp}.json
    [ -f "$json" ] || continue
    payload="$work/payload.json"
    printf '{"p_token":"%s",' "$DOGEAR_INGEST_TOKEN" > "$payload"
    awk 'NR == 1 { sub(/^\{/, ""); printf "%s", $0 }' "$json" >> "$payload"
    code=$(post_with_retries "$payload")
    prc=$?
    last_http=$code
    rm -f "$payload"
    resp=$(redact < "$work/response.json" | clip)
    if [ "$prc" -eq 0 ]; then
      merge_state "$STATE" "$fp"
      n=$(wc -l < "$fp" | tr -d ' ')
      uploaded=$((uploaded + n))
      log "batch ok http $code uploaded $n"
    else
      log "batch failed http $code $resp"
      UPLOADED=$uploaded
      LAST_HTTP=$code
      if [ "$prc" -eq 2 ]; then
        return 2
      fi
      return 1
    fi
  done
  UPLOADED=$uploaded
  LAST_HTTP=$last_http
  return 0
}

print_status() {
  echo "Dogear sync status"
  printf 'version=%s\n' "$VERSION"
  if [ ! -d "$ROOT" ]; then
    echo "installed=no"
    echo "result=not-installed"
    return 0
  fi
  echo "installed=yes"
  if [ -f "$CFG" ]; then
    if load_config "$CFG"; then
      echo "config=ok"
      printf 'supabase_host=%s\n' "${SUPABASE_URL#https://}"
      echo "anon_key=present"
      echo "ingest_token=present"
      echo "service_role=absent"
    else
      echo "config=invalid"
      printf 'message=%s\n' "$config_error"
      if [ "$service_role_found" -eq 1 ]; then
        echo "service_role=blocked"
      fi
    fi
  else
    echo "config=missing"
  fi
  if wifi_is_up; then
    echo "wifi=up"
  else
    echo "wifi=down"
  fi
  if [ -n "${DOG_BATTERY_FILE:-}" ] && [ -f "$DOG_BATTERY_FILE" ]; then
    printf 'battery=%s\n' "$(tr -cd '0-9' < "$DOG_BATTERY_FILE")"
  fi
  if [ -f "$ROOT/last-status" ]; then
    echo "--- last run ---"
    redact < "$ROOT/last-status"
  else
    echo "last_run=none"
  fi
  if [ -f "$LOG" ]; then
    echo "--- log ---"
    tail -n 20 "$LOG" | redact
  fi
}

run_self_test() {
  anon=$(jwt_payload "eyJhbGciOiJub25lIn0.eyJyb2xlIjoiYW5vbiJ9.sig")
  svc=$(jwt_payload "eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig")
  need='"role":"anon"'
  case "$anon" in
    *"$need"*) ;;
    *) echo "anon decode failed"; return 1 ;;
  esac
  case "$svc" in
    *service_role*) ;;
    *) echo "service role decode failed"; return 1 ;;
  esac
  echo "self-test ok"
}

mode=${1:-manual}
case "$mode" in
  manual|wifi|status|self-test) ;;
  *)
    echo "usage: kobo-sync.sh [manual|wifi|status]" >&2
    exit 1
    ;;
esac

if [ "$mode" = "self-test" ]; then
  run_self_test
  exit $?
fi

ROOT=${DOG_ROOT:-/mnt/onboard/.adds/dogear}
CFG=${DOG_CONFIG:-$ROOT/config.env}
STATE=$ROOT/state.v2
LOG=$ROOT/sync.log
DB=${DOG_DB:-/mnt/onboard/.kobo/KoboReader.sqlite}
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
AWK=$SCRIPT_DIR/extract.awk
LOCKDIR=
work=

if [ "$mode" = "status" ]; then
  print_status
  exit 0
fi

trap cleanup EXIT INT TERM
mkdir -p "$ROOT"
rotate_log
log "dogear sync $VERSION trigger=$mode"

if [ ! -f "$AWK" ]; then
  log "extract.awk is missing next to kobo-sync.sh"
  write_status error "" 0 "extract.awk missing"
  exit 1
fi

if ! load_config "$CFG"; then
  log "config: $config_error"
  write_status config "" 0 "$config_error"
  exit 1
fi

if [ "$mode" = "wifi" ] && battery_low; then
  log "battery below 8 percent; skipping automatic sync"
  arm_cooldown "${DOG_LOW_BATTERY_COOLDOWN:-900}"
  write_status skipped "" 0 "battery low"
  exit 0
fi

if cooldown_active; then
  log "cooldown active; skipping"
  write_status skipped "" 0 "cooldown"
  exit 0
fi

if ! acquire_lock; then
  log "sync already running"
  write_status skipped "" 0 "already running"
  exit 0
fi

if ! wait_for_wifi; then
  log "no network address"
  write_status offline "" 0 "no network address"
  exit 75
fi

if [ ! -f "$DB" ]; then
  log "highlight database not found"
  write_status error "" 0 "highlight database not found"
  exit 1
fi

if [ -f "$ROOT/state.synced" ] && [ ! -s "$STATE" ]; then
  log "ignoring old state.synced so metadata can be sent again; the server keeps one row per highlight"
fi

if ! extract_highlights "$DB"; then
  write_status error "" 0 "could not read highlights"
  exit 1
fi

if [ "${pending:-0}" -eq 0 ]; then
  log "nothing new"
  arm_cooldown "${DOG_SUCCESS_COOLDOWN:-180}"
  write_status ok "" 0 "nothing new"
  exit 0
fi

client=$(pick_client)
if [ "$client" = "none" ]; then
  log "neither curl nor wget is available"
  write_status error "" 0 "neither curl nor wget is available"
  exit 1
fi

upload_batches
urc=$?
if [ "$urc" -eq 0 ]; then
  arm_cooldown "${DOG_SUCCESS_COOLDOWN:-180}"
  write_status ok "${LAST_HTTP:-200}" "${UPLOADED:-0}" "synced"
  exit 0
fi
if [ "$urc" -eq 2 ]; then
  arm_cooldown "${DOG_FAILURE_COOLDOWN:-45}"
  write_status auth "${LAST_HTTP:-}" "${UPLOADED:-0}" "upload rejected"
  exit 1
fi
arm_cooldown "${DOG_FAILURE_COOLDOWN:-45}"
write_status offline "${LAST_HTTP:-}" "${UPLOADED:-0}" "upload failed"
exit 75
