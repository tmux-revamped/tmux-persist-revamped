#!/usr/bin/env bash
#
# format.sh: the save-file record codec for tmux-persist-revamped.
#
# A record is one line of tab-joined fields. Every field is escaped so a tab, a
# newline, or a backslash inside a value (a pane title, a path, a command) can
# never be mistaken for a delimiter, and an empty field round-trips as empty. This
# is the corruption-proof replacement for the upstream tab-delimited format, where
# empty fields and embedded tabs lose data. Parsing is forced to LC_ALL=C so a
# locale never reinterprets the bytes.
#
# These are pure functions: text in, text out, no tmux and no files. They are the
# part tested hardest, since a codec bug loses a user's saved sessions.

[[ -n "${_PERSIST_REVAMPED_FORMAT_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_FORMAT_LOADED=1

# persist_escape FIELD -> FIELD with backslash, tab, and newline escaped. Backslash
# is escaped first so the escapes it introduces are not re-escaped.
persist_escape() {
  printf '%s' "${1}" | LC_ALL=C awk '{gsub(/\\/,"\\\\"); gsub(/\t/,"\\t")} NR>1{printf "%s","\\n"} {printf "%s",$0}'
}

# persist_unescape FIELD -> the inverse of persist_escape. A doubled backslash is
# parked on a sentinel first so that "\\t" reads as backslash-then-t, not as a tab.
persist_unescape() {
  printf '%s' "${1}" | LC_ALL=C awk '{gsub(/\\\\/,"\001"); gsub(/\\t/,"\t"); gsub(/\\n/,"\n"); gsub(/\001/,"\\"); printf "%s",$0}'
}

# persist_join FIELD... -> one record line: each field escaped, joined by a tab.
persist_join() {
  local out="" f first=1
  for f in "$@"; do
    if (( first )); then
      out="$(persist_escape "${f}")"
      first=0
    else
      out="${out}"$'\t'"$(persist_escape "${f}")"
    fi
  done
  printf '%s\n' "${out}"
}

# persist_split LINE -> the record's fields, each unescaped, NUL separated so a
# value that contains a newline still reads back as one field. Empty and trailing
# empty fields are preserved.
persist_split() {
  printf '%s' "${1}" | LC_ALL=C awk -F'\t' 'BEGIN{RS="\n"} {for(i=1;i<=NF;i++){f=$i; gsub(/\\\\/,"\001",f); gsub(/\\t/,"\t",f); gsub(/\\n/,"\n",f); gsub(/\001/,"\\",f); printf "%s\000",f}}'
}

export -f persist_escape
export -f persist_unescape
export -f persist_join
export -f persist_split
