# Turn a sqlite3 quote() dump into ingest batches.
# Input rows use ASCII 034 between 11 quote()-encoded fields:
#   bookmark id, volume id, text, annotation, date, chapter title,
#   chapter progress, book title, book author, type, content id
# content id is accepted so the field count stays stable; chapter title
# is what we store.
# stdout: one line, "pending N skipped N batches N errors N"

BEGIN {
  for (i = 1; i <= 255; i++) ORD[sprintf("%c", i)] = i
  SEP = sprintf("%c", 28)
  if (batchsize + 0 < 1) batchsize = 20
  if (statefile != "") {
    while ((getline line < statefile) > 0) {
      tab = index(line, "\t")
      if (tab > 0) {
        seen[substr(line, tab + 1)] = substr(line, 1, tab - 1)
      }
    }
    close(statefile)
  }
}

function hash(s,    h, i, c, b) {
  h = 2166136261
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    b = ORD[c]
    if (b == "") b = 0
    h = (h * 33 + b) % 4294967296
  }
  return sprintf("%.0f", h)
}

function trim(s) {
  gsub(/^[ \t\r\n]+/, "", s)
  gsub(/[ \t\r\n]+$/, "", s)
  return s
}

function jesc(s,    i, c, o, b) {
  o = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\") o = o "\\\\"
    else if (c == "\"") o = o "\\\""
    else if (c == "\n") o = o "\\n"
    else if (c == "\r") o = o "\\r"
    else if (c == "\t") o = o "\\t"
    else {
      b = ORD[c]
      if (b != "" && b < 32) o = o sprintf("\\u%04x", b)
      else o = o c
    }
  }
  return o
}

function jstr(s) {
  if (s == "") return "null"
  return "\"" jesc(s) "\""
}

function jnum(s) {
  if (s ~ /^-?[0-9]+([.][0-9]+)?$/) return s + 0
  return "null"
}

function jdate(s,    head, rest) {
  # mawk panics on one large optional regex, so the pieces stay separate.
  if (s == "") return "null"
  if (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return "\"" s "\""
  if (length(s) < 19) return "null"
  head = substr(s, 1, 19)
  if (head !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/)
    return "null"
  rest = substr(s, 20)
  if (rest == "" || rest == "Z") return "\"" jesc(s) "\""
  if (rest ~ /^[.][0-9][0-9]*$/) return "\"" jesc(s) "\""
  if (rest ~ /^[.][0-9][0-9]*Z$/) return "\"" jesc(s) "\""
  if (rest ~ /^[+-][0-9][0-9][0-9][0-9]$/) return "\"" jesc(s) "\""
  if (rest ~ /^[+-][0-9][0-9]:[0-9][0-9]$/) return "\"" jesc(s) "\""
  return "null"
}

function flush(    b, i, books, highs, fname, fpname) {
  if (npending < 1) return
  books = ""
  for (b in bookjson) {
    if (books != "") books = books ","
    books = books bookjson[b]
  }
  highs = ""
  for (i = 1; i <= npending; i++) {
    if (i > 1) highs = highs ","
    highs = highs pend_json[i]
  }
  bn++
  fname = sprintf("%s/batch-%03d.json", outdir, bn)
  printf "%s\n", "{\"p_books\":[" books "],\"p_highlights\":[" highs "]}" > fname
  close(fname)
  fpname = sprintf("%s/batch-%03d.fp", outdir, bn)
  for (i = 1; i <= npending; i++)
    printf "%s\t%s\n", pend_fp[i], pend_id[i] > fpname
  close(fpname)
  npending = 0
  delete bookjson
  delete pend_json
  delete pend_fp
  delete pend_id
}

function handle(    id, vol, raw_text, raw_ann, date, chapter, progress, title, author, type, kind, text_out, ann_out, fp) {
  if (nf == 1 && f[1] == "") return
  if (nf != 11) { errors++; return }
  id = trim(f[1])
  vol = trim(f[2])
  raw_text = trim(f[3])
  raw_ann = trim(f[4])
  date = trim(f[5])
  chapter = trim(f[6])
  progress = trim(f[7])
  title = trim(f[8])
  author = trim(f[9])
  type = tolower(trim(f[10]))
  if (id == "" || vol == "") { errors++; return }
  if (raw_text == "" && raw_ann == "") return
  kind = "highlight"
  text_out = raw_text
  ann_out = raw_ann
  if (raw_text == "") {
    kind = "note"
    text_out = raw_ann
    ann_out = ""
  } else if (type == "note") {
    kind = "note"
  }
  fp = hash(id "\036" vol "\036" text_out "\036" ann_out "\036" date "\036" chapter "\036" progress "\036" title "\036" author "\036" kind)
  if ((id in seen) && (seen[id] "" == fp "")) {
    skipped++
    return
  }
  npending++
  pending++
  pend_id[npending] = id
  pend_fp[npending] = fp
  pend_json[npending] = sprintf("{\"kobo_bookmark_id\":\"%s\",\"kobo_content_id\":\"%s\",\"text\":\"%s\",\"annotation\":%s,\"chapter\":%s,\"highlighted_at\":%s,\"source_type\":\"%s\",\"kobo_progress\":%s}", jesc(id), jesc(vol), jesc(text_out), jstr(ann_out), jstr(chapter), jdate(date), kind, jnum(progress))
  bookjson[vol] = sprintf("{\"kobo_content_id\":\"%s\",\"title\":\"%s\",\"author\":\"%s\"}", jesc(vol), jesc(title), jesc(author))
  if (npending >= batchsize) flush()
}

{
  buf = buf $0 "\n"
}

END {
  n = length(buf)
  fld = ""
  nf = 0
  inq = 0
  for (i = 1; i <= n; i++) {
    c = substr(buf, i, 1)
    if (inq) {
      if (c == "'") {
        if (substr(buf, i + 1, 1) == "'") {
          fld = fld "'"
          i++
        } else {
          inq = 0
        }
      } else {
        fld = fld c
      }
      continue
    }
    if (c == "'") { inq = 1; continue }
    if (c == SEP) {
      nf++
      f[nf] = fld
      fld = ""
      continue
    }
    if (c == "\n") {
      nf++
      f[nf] = fld
      handle()
      nf = 0
      fld = ""
      delete f
      continue
    }
  }
  flush()
  printf "pending %d skipped %d batches %d errors %d\n", pending + 0, skipped + 0, bn + 0, errors + 0
}
