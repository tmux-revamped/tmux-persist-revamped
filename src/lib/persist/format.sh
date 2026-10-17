#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_FORMAT_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_FORMAT_LOADED=1

persist_escape() {
  printf '%s' "${1}" | LC_ALL=C awk '{gsub(/\\/,"\\\\"); gsub(/\t/,"\\t")} NR>1{printf "%s","\\n"} {printf "%s",$0}'
}

persist_unescape() {
  printf '%s' "${1}" | LC_ALL=C awk '{gsub(/\\\\/,"\001"); gsub(/\\t/,"\t"); gsub(/\\n/,"\n"); gsub(/\001/,"\\"); printf "%s",$0}'
}

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

persist_split() {
  local rest="${1}" field
  while [[ "${rest}" == *$'\t'* ]]; do
    field="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    printf '%s\n' "${field}"
  done
  printf '%s\n' "${rest}"
}

persist_strip_trailing_blanks() {
  printf '%s' "${1}" | awk '{ lines[NR] = $0 } END { last = NR; while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--; for (i = 1; i <= last; i++) print lines[i] }'
}

export -f persist_escape
export -f persist_unescape
export -f persist_join
export -f persist_split
export -f persist_strip_trailing_blanks
