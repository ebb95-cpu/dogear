#!/bin/sh
# Simulated Dogear sync tests. These do not talk to a Kobo or to Supabase.
failures=0
here=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo=$(CDPATH= cd "$here/../.." && pwd)
sync=$repo/kobo-sync/kobo-sync.sh
FAKEBIN=$here/bin
ORIG_PATH=$PATH
ANON='eyJhbGciOiJub25lIn0.eyJyb2xlIjoiYW5vbiJ9.sig'
SERVICE='eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig'
TOKEN='dogear_abcdefghijklmnopqrstuvwxyz0123456789ABCD'

ok() { echo "ok $*"; }
bad() { echo "FAIL $*"; failures=$((failures + 1)); }

chmod 755 "$FAKEBIN/curl" "$FAKEBIN/wget" "$sync" "$repo/kobo-sync/auto-sync-on-wifi.sh" \
  "$repo/kobo-sync/build-installer.sh" "$repo/kobo-sync/rootfs/usr/local/dogear/wifi-hook.sh"

make_db() {
  sqlite3 "$1" <<'SQL'
CREATE TABLE Bookmark (
  BookmarkID TEXT PRIMARY KEY,
  VolumeID TEXT,
  ContentID TEXT,
  Text TEXT,
  Annotation TEXT,
  DateCreated TEXT,
  ChapterProgress REAL,
  Hidden INTEGER,
  Type TEXT
);
CREATE TABLE content (
  ContentID TEXT PRIMARY KEY,
  Title TEXT,
  Attribution TEXT
);
CREATE TABLE user (
  UserID TEXT,
  UserKey TEXT
);
INSERT INTO user VALUES ('u', 'session-secret-do-not-upload');
INSERT INTO content VALUES ('file:///mnt/onboard/Book.epub', 'The Orange Book', 'Ada Author');
INSERT INTO content VALUES ('file:///mnt/onboard/Book.epub#chap', 'Chapter 1', NULL);
INSERT INTO Bookmark VALUES (
  'bm-1',
  'file:///mnt/onboard/Book.epub',
  'file:///mnt/onboard/Book.epub#chap',
  'UNIQUE-PASSAGE-ORANGE "quoted"' || char(10) || 'next line ' || char(7) || ' bell \ slash',
  'a note with \ backslash',
  '2024-06-01T15:04:05Z',
  0.25,
  0,
  'highlight'
);
INSERT INTO Bookmark VALUES (
  'bm-hidden',
  'file:///mnt/onboard/Book.epub',
  'file:///mnt/onboard/Book.epub',
  'HIDDEN-SHOULD-NOT-UPLOAD',
  '',
  '2024-06-01T15:04:05Z',
  0,
  1,
  'highlight'
);
INSERT INTO Bookmark VALUES (
  'bm-dogear',
  'file:///mnt/onboard/Book.epub',
  'file:///mnt/onboard/Book.epub',
  'DOGEAR-SHOULD-NOT-UPLOAD',
  '',
  '2024-06-01T15:04:05Z',
  0,
  0,
  'dogear'
);
INSERT INTO Bookmark VALUES (
  'bm-note',
  'file:///mnt/onboard/Book.epub',
  'file:///mnt/onboard/Book.epub',
  '',
  'margin note',
  '2024-07-01T00:00:00',
  NULL,
  0,
  'note'
);
INSERT INTO Bookmark VALUES (
  'bm-notitle',
  'file:///mnt/onboard/Missing.epub',
  'file:///mnt/onboard/Missing.epub',
  'orphan passage',
  '',
  '2024-08-01T00:00:00Z',
  0,
  0,
  'highlight'
);
SQL
}

write_config() {
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="https://example.supabase.co"
SUPABASE_ANON_KEY="$ANON"
DOGEAR_INGEST_TOKEN="$TOKEN"
EOF
}

new_case() {
  CASE=$(mktemp -d)
  export DOG_ROOT=$CASE/root
  mkdir -p "$DOG_ROOT"
  export DOG_DB=$CASE/library.sqlite
  export DOG_WORK_PARENT=$CASE/work
  mkdir -p "$DOG_WORK_PARENT"
  export DOG_LOCK_DIR=$CASE/lockdir
  export DOG_CURL_DIR=$CASE/curl
  mkdir -p "$DOG_CURL_DIR"
  export DOG_WIFI_FILE=$CASE/wifi
  echo up > "$DOG_WIFI_FILE"
  export DOG_HTTP_CLIENT=curl
  export DOG_SUCCESS_COOLDOWN=0
  export DOG_FAILURE_COOLDOWN=0
  export DOG_WIFI_WAIT=0
  export DOG_WIFI_POLL=0
  export DOG_RETRIES=3
  export DOG_BACKOFF="0 0"
  export DOG_HTTP_TIMEOUT=2
  export DOG_BATCH=20
  export PATH="$FAKEBIN:$ORIG_PATH"
  unset DOG_BATTERY_FILE DOG_DEBUG_DIR
  write_config
  make_db "$DOG_DB"
}

run_sync() {
  sh "$sync" "$@" > "$CASE/stdout" 2> "$CASE/stderr"
  echo $? > "$CASE/exit"
}

bodies() {
  find "$DOG_CURL_DIR" -name 'body-*.json' 2>/dev/null | wc -l | tr -d ' '
}

assert_clean() {
  if grep -R -q "session-secret-do-not-upload" "$DOG_ROOT" "$CASE/stdout" "$CASE/stderr" "$DOG_CURL_DIR" 2>/dev/null; then
    echo "sqlite secret leaked"
    return 1
  fi
  for f in "$DOG_ROOT/sync.log" "$DOG_ROOT/last-status" "$CASE/stdout" "$CASE/stderr"; do
    [ -f "$f" ] || continue
    if grep -q "$TOKEN" "$f" || grep -q "$ANON" "$f"; then
      echo "credential leaked into $f"
      return 1
    fi
  done
  if [ -f "$DOG_CURL_DIR/sqlite-leak" ]; then
    echo "database copy still present during HTTP"
    return 1
  fi
  if find "$DOG_WORK_PARENT" -name 'read.sqlite' | grep -q .; then
    echo "database copy left behind"
    return 1
  fi
  return 0
}

if sh "$sync" self-test > /dev/null; then ok self-test; else bad self-test; fi

if python3 "$here/nm_config_test.py" > /dev/null; then ok nm-config; else bad nm-config; fi

# Wi-Fi down, then up: nothing is uploaded until an address exists.
(
  new_case
  echo down > "$DOG_WIFI_FILE"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "75" || exit 1
  test "$(bodies)" = "0" || exit 1
  echo up > "$DOG_WIFI_FILE"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "0" || exit 1
  test "$(bodies)" = "1" || exit 1
  python3 - "$DOG_CURL_DIR"/body-1.json "$TOKEN" <<'PY'
import json, pathlib, sys
body = json.loads(pathlib.Path(sys.argv[1]).read_text())
token, path = sys.argv[2], sys.argv[1]
assert body["p_token"] == token
assert "p_user_id" not in body
blob = pathlib.Path(path).read_text()
assert "session-secret-do-not-upload" not in blob
assert "HIDDEN-SHOULD-NOT-UPLOAD" not in blob
assert "DOGEAR-SHOULD-NOT-UPLOAD" not in blob
high = {h["kobo_bookmark_id"]: h for h in body["p_highlights"]}
assert set(high) == {"bm-1", "bm-note", "bm-notitle"}
orange = high["bm-1"]
assert 'UNIQUE-PASSAGE-ORANGE "quoted"\nnext line \u0007 bell \\ slash' == orange["text"]
assert orange["annotation"] == "a note with \\ backslash"
assert orange["chapter"] == "Chapter 1"
assert orange["kobo_progress"] == 0.25
assert orange["highlighted_at"] == "2024-06-01T15:04:05Z"
assert orange["source_type"] == "highlight"
assert high["bm-note"]["text"] == "margin note"
assert high["bm-note"]["source_type"] == "note"
assert high["bm-note"]["annotation"] is None
books = {b["kobo_content_id"]: b for b in body["p_books"]}
assert books["file:///mnt/onboard/Book.epub"]["title"] == "The Orange Book"
assert books["file:///mnt/onboard/Book.epub"]["author"] == "Ada Author"
assert books["file:///mnt/onboard/Missing.epub"]["title"] == ""
PY
  grep -F -q "apikey: $ANON" "$DOG_CURL_DIR/headers-1.txt" || exit 1
  grep -F -q "authorization: Bearer $ANON" "$DOG_CURL_DIR/headers-1.txt" || exit 1
  if grep -F -q "$TOKEN" "$DOG_CURL_DIR/headers-1.txt"; then exit 1; fi
  assert_clean
) && ok wifi-reconnect || bad wifi-reconnect

# Second wifi event during cooldown does not upload a changed highlight.
# A manual run does.
(
  new_case
  export DOG_SUCCESS_COOLDOWN=3600
  run_sync wifi
  test "$(bodies)" = "1" || exit 1
  sqlite3 "$DOG_DB" "update Bookmark set Annotation = 'edited note' where BookmarkID = 'bm-1';"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "0" || exit 1
  test "$(bodies)" = "1" || exit 1
  run_sync manual
  test "$(bodies)" = "2" || exit 1
  python3 - "$DOG_CURL_DIR"/body-2.json <<'PY'
import json, pathlib, sys
body = json.loads(pathlib.Path(sys.argv[1]).read_text())
ids = [h["kobo_bookmark_id"] for h in body["p_highlights"]]
assert ids == ["bm-1"]
assert body["p_highlights"][0]["annotation"] == "edited note"
PY
  assert_clean
) && ok cooldown-and-manual || bad cooldown-and-manual

# Unchanged library does not post twice.
(
  new_case
  run_sync manual
  run_sync manual
  test "$(bodies)" = "1" || exit 1
  grep -q "nothing new" "$DOG_ROOT/sync.log" || exit 1
  assert_clean
) && ok duplicate-import || bad duplicate-import

# Old state file must not suppress the repair resend.
(
  new_case
  echo bm-1 > "$DOG_ROOT/state.synced"
  run_sync manual
  test "$(bodies)" = "1" || exit 1
  assert_clean
) && ok ignores-old-state || bad ignores-old-state

# Offline retries are bounded. A later success commits state.
(
  new_case
  printf '%s\n' 503 503 200 > "$DOG_CURL_DIR/codes"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "0" || exit 1
  test "$(bodies)" = "3" || exit 1
  test -s "$DOG_ROOT/state.v2" || exit 1
  assert_clean
) && ok offline-retry-then-ok || bad offline-retry-then-ok

(
  new_case
  printf '%s\n' 503 503 503 > "$DOG_CURL_DIR/codes"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "75" || exit 1
  test "$(bodies)" = "3" || exit 1
  test ! -s "$DOG_ROOT/state.v2" || exit 1
  grep -q "result=offline" "$DOG_ROOT/last-status" || exit 1
  assert_clean
) && ok offline-gives-up || bad offline-gives-up

(
  new_case
  printf '%s\n' 000 000 000 > "$DOG_CURL_DIR/codes"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "75" || exit 1
  attempts=$(find "$DOG_CURL_DIR" -name 'attempt-*' | wc -l | tr -d ' ')
  test "$attempts" = "3" || exit 1
  assert_clean
) && ok connection-refused-bounded || bad connection-refused-bounded

(
  new_case
  printf '%s\n' 401 > "$DOG_CURL_DIR/codes"
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "1" || exit 1
  test ! -s "$DOG_ROOT/state.v2" || exit 1
  grep -q "result=auth" "$DOG_ROOT/last-status" || exit 1
  assert_clean
) && ok auth-failure-no-retry || bad auth-failure-no-retry

# One highlight per request. The first success is remembered if the next fails.
(
  new_case
  export DOG_BATCH=1
  printf '%s\n' 200 503 503 503 > "$DOG_CURL_DIR/codes"
  run_sync manual
  test "$(cat "$CASE/exit")" = "75" || exit 1
  grep -q "$(printf 'bm-1')" "$DOG_ROOT/state.v2" || exit 1
  if grep -q "$(printf 'bm-note')" "$DOG_ROOT/state.v2"; then exit 1; fi
  printf '%s\n' 200 200 200 > "$DOG_CURL_DIR/codes"
  run_sync manual
  test "$(cat "$CASE/exit")" = "0" || exit 1
  python3 - "$DOG_CURL_DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
sent = []
for path in sorted(root.glob("body-*.json")):
    body = json.loads(path.read_text())
    sent.append([h["kobo_bookmark_id"] for h in body["p_highlights"]])
flat = [item for batch in sent for item in batch]
assert flat.count("bm-1") == 1
assert "bm-note" in flat
assert "bm-notitle" in flat
PY
  assert_clean
) && ok partial-batch-retry || bad partial-batch-retry

# Malformed config never touches the network.
(
  new_case
  rm -f "$DOG_ROOT/config.env"
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "0" || exit 1
) && ok missing-config || bad missing-config

(
  new_case
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="https://example.supabase.co"
SUPABASE_ANON_KEY="$ANON"
DOGEAR_INGEST_TOKEN="$TOKEN"
SUPABASE_SERVICE_ROLE_KEY="$SERVICE"
EOF
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "0" || exit 1
  grep -q "SERVICE_ROLE_KEY" "$DOG_ROOT/sync.log" || exit 1
  if grep -q "$SERVICE" "$DOG_ROOT/sync.log"; then exit 1; fi
  run_sync status
  grep -q "service_role=blocked" "$CASE/stdout" || exit 1
  if grep -q "$SERVICE" "$CASE/stdout"; then exit 1; fi
  if grep -q "$TOKEN" "$CASE/stdout"; then exit 1; fi
) && ok rejects-service-role || bad rejects-service-role

(
  new_case
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="https://example.supabase.co"
SUPABASE_ANON_KEY="$SERVICE"
DOGEAR_INGEST_TOKEN="$TOKEN"
EOF
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "0" || exit 1
) && ok rejects-service-role-in-anon-field || bad rejects-service-role-in-anon-field

(
  new_case
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="https://example.supabase.co\$(touch $CASE/pwned)"
SUPABASE_ANON_KEY="$ANON"
DOGEAR_INGEST_TOKEN="$TOKEN"
EOF
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test ! -e "$CASE/pwned" || exit 1
  test "$(bodies)" = "0" || exit 1
  printf '%s\n' '$(touch '"$CASE"'/pwned2)' >> "$DOG_ROOT/config.env"
  # The first line already fails; rewrite a file whose only payload is substitution.
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="https://example.supabase.co"
SUPABASE_ANON_KEY="$ANON"
DOGEAR_INGEST_TOKEN="$TOKEN"
\$(touch $CASE/pwned2)
EOF
  run_sync manual
  test ! -e "$CASE/pwned2" || exit 1
) && ok rejects-command-substitution || bad rejects-command-substitution

(
  new_case
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="http://example.supabase.co"
SUPABASE_ANON_KEY="$ANON"
DOGEAR_INGEST_TOKEN="$TOKEN"
EOF
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "0" || exit 1
  cat > "$DOG_ROOT/config.env" <<EOF
SUPABASE_URL="https://example.supabase.co"
SUPABASE_ANON_KEY="$ANON"
DOGEAR_INGEST_TOKEN="eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig"
EOF
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "0" || exit 1
) && ok rejects-bad-url-and-jwt-token || bad rejects-bad-url-and-jwt-token

(
  new_case
  printf '%s\n' 'USER_ID="11111111-1111-1111-1111-111111111111"' >> "$DOG_ROOT/config.env"
  run_sync manual
  test "$(cat "$CASE/exit")" = "0" || exit 1
  if grep -q "11111111-1111-1111-1111-111111111111" "$DOG_ROOT/sync.log"; then exit 1; fi
  grep -q "ignoring USER_ID" "$DOG_ROOT/sync.log" || exit 1
  run_sync status
  if grep -q "$TOKEN" "$CASE/stdout"; then exit 1; fi
  if grep -q "$ANON" "$CASE/stdout"; then exit 1; fi
  grep -q "config=ok" "$CASE/stdout" || exit 1
  assert_clean
) && ok status-redacts-and-ignores-user-id || bad status-redacts-and-ignores-user-id

(
  new_case
  export DOG_BATTERY_FILE=$CASE/battery
  echo 5 > "$DOG_BATTERY_FILE"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "0" || exit 1
  test "$(bodies)" = "0" || exit 1
  grep -q "battery low" "$DOG_ROOT/last-status" || exit 1
  run_sync manual
  test "$(bodies)" = "1" || exit 1
) && ok low-battery-skips-wifi-not-manual || bad low-battery-skips-wifi-not-manual

(
  new_case
  mkdir -p "$DOG_LOCK_DIR"
  date +%s > "$DOG_LOCK_DIR/started"
  run_sync wifi
  test "$(cat "$CASE/exit")" = "0" || exit 1
  test "$(bodies)" = "0" || exit 1
  grep -q "already running" "$DOG_ROOT/sync.log" || exit 1
  echo 1 > "$DOG_LOCK_DIR/started"
  run_sync wifi
  test "$(bodies)" = "1" || exit 1
) && ok lock-and-stale-lock || bad lock-and-stale-lock

(
  new_case
  rm -f "$DOG_DB"
  sqlite3 "$DOG_DB" "create table not_kobo(x text);"
  run_sync manual
  test "$(cat "$CASE/exit")" = "1" || exit 1
  test "$(bodies)" = "0" || exit 1
) && ok malformed-database || bad malformed-database

(
  new_case
  export DOG_HTTP_CLIENT=wget
  run_sync manual
  test "$(cat "$CASE/exit")" = "0" || exit 1
  test "$(bodies)" = "1" || exit 1
  grep -q wget "$DOG_CURL_DIR/client-1.txt" || exit 1
  assert_clean
) && ok wget-client || bad wget-client

(
  new_case
  echo down > "$DOG_WIFI_FILE"
  sh "$repo/kobo-sync/auto-sync-on-wifi.sh" > "$CASE/stdout" 2> "$CASE/stderr"
  echo $? > "$CASE/exit"
  test "$(cat "$CASE/exit")" = "75" || exit 1
  test "$(bodies)" = "0" || exit 1
) && ok auto-sync-is-one-shot || bad auto-sync-is-one-shot

(
  tmp=$(mktemp -d)
  sh "$repo/kobo-sync/build-installer.sh" > "$tmp/build.out" || exit 1
  tar -tzf "$repo/kobo-sync/dist/KoboRoot.tgz" | sort > "$tmp/list"
  printf '%s\n' "etc/" "etc/udev/" "etc/udev/rules.d/" "etc/udev/rules.d/99-dogear-wifi.rules" \
    "usr/" "usr/local/" "usr/local/dogear/" "usr/local/dogear/wifi-hook.sh" | sort > "$tmp/expect"
  # GNU tar may omit directory entries. Compare file members only.
  tar -tzf "$repo/kobo-sync/dist/KoboRoot.tgz" | grep -v '/$' | sort > "$tmp/files"
  printf '%s\n' "etc/udev/rules.d/99-dogear-wifi.rules" "usr/local/dogear/wifi-hook.sh" | sort > "$tmp/files-expect"
  diff -u "$tmp/files-expect" "$tmp/files" || exit 1
  rule=$(tar -xOf "$repo/kobo-sync/dist/KoboRoot.tgz" etc/udev/rules.d/99-dogear-wifi.rules)
  printf '%s\n' "$rule" | grep 'KERNEL==' | grep -q 'usb' && exit 1
  printf '%s\n' "$rule" | grep -q 'koblime' && exit 1
  printf '%s\n' "$rule" | grep -q 'KERNEL=="wlan\*"' || exit 1
  if tar -xOf "$repo/kobo-sync/dist/KoboRoot.tgz" usr/local/dogear/wifi-hook.sh | grep -q "service_role"; then exit 1; fi
  # Refuse an unconfirmed volume write.
  mkdir -p "$tmp/kobo/.kobo"
  echo keep > "$tmp/kobo/keep"
  echo SECRET > "$tmp/kobo/.kobo/KoboReader.sqlite"
  if KOBO_MOUNT="$tmp/kobo" sh "$repo/kobo-sync/build-installer.sh" > "$tmp/no.out" 2> "$tmp/no.err"; then
    exit 1
  fi
  test "$(cat "$tmp/kobo/keep")" = "keep" || exit 1
  test "$(cat "$tmp/kobo/.kobo/KoboReader.sqlite")" = "SECRET" || exit 1
  test ! -e "$tmp/kobo/.adds" || exit 1
  # Confirmed copy touches only the sync files.
  mkdir -p "$tmp/kobo/.adds/dogear"
  echo "SUPABASE_URL=already" > "$tmp/kobo/.adds/dogear/config.env"
  echo book > "$tmp/kobo/My Book.epub"
  DOG_INSTALL_CONFIRM=yes KOBO_MOUNT="$tmp/kobo" sh "$repo/kobo-sync/build-installer.sh" > "$tmp/yes.out" || exit 1
  test -f "$tmp/kobo/.adds/dogear/kobo-sync.sh" || exit 1
  test -f "$tmp/kobo/.adds/dogear/extract.awk" || exit 1
  test -f "$tmp/kobo/.kobo/KoboRoot.tgz" || exit 1
  test -f "$tmp/kobo/.adds/nm/nm_kobosync" || exit 1
  test "$(cat "$tmp/kobo/.adds/dogear/config.env")" = "SUPABASE_URL=already" || exit 1
  test "$(cat "$tmp/kobo/.kobo/KoboReader.sqlite")" = "SECRET" || exit 1
  test "$(cat "$tmp/kobo/My Book.epub")" = "book" || exit 1
  if grep -R -q "SECRET" "$tmp/kobo/.adds" "$repo/kobo-sync/dist"; then exit 1; fi
) && ok installer-artifact || bad installer-artifact

(
  tmp=$(mktemp -d)
  cat > "$tmp/sync.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" > "$DOG_MARK"
EOF
  chmod 755 "$tmp/sync.sh"
  export DOG_MARK=$tmp/mark
  export DOG_SYNC_SCRIPT=$tmp/sync.sh
  export DOG_UDEV_LOG=$tmp/udev.log
  export DOG_MOUNT_WAIT=3
  export DOG_MOUNT_POLL=0
  sh "$repo/kobo-sync/rootfs/usr/local/dogear/wifi-hook.sh" || exit 1
  i=0
  while [ "$i" -lt 20 ]; do
    if [ -f "$DOG_MARK" ]; then
      break
    fi
    i=$((i + 1))
    sleep 0.1
  done
  test "$(cat "$DOG_MARK")" = "wifi" || exit 1
  export DOG_UDEV_DETACHED=1
  export DOG_SYNC_SCRIPT=$tmp/missing.sh
  sh "$repo/kobo-sync/rootfs/usr/local/dogear/wifi-hook.sh" > "$tmp/idle.out" || exit 1
  grep -q "idle" "$tmp/idle.out" || exit 1
) && ok wifi-hook || bad wifi-hook

echo
if [ "$failures" -eq 0 ]; then
  echo "shell tests passed"
  exit 0
fi
echo "$failures shell test(s) failed"
exit 1
