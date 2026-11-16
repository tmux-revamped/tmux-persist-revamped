#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_FORMAT_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_FORMAT_LOADED=1

persist_escape() {
  printf '%s' "${1}" | LC_ALL=C awk '{ out = ""; for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); if (c == "\\") { out = out "\\\\" } else if (c == "\t") { out = out "\\t" } else { out = out c } } if (NR > 1) { printf "%s", "\\n" } printf "%s", out }'
}

persist_unescape() {
  printf '%s' "${1}" | LC_ALL=C awk '{ out = ""; n = length($0); for (i = 1; i <= n; i++) { c = substr($0, i, 1); d = substr($0, i + 1, 1); if (c != "\\" || i == n) { out = out c } else if (d == "\\") { out = out "\\"; i++ } else if (d == "t") { out = out "\t"; i++ } else if (d == "n") { out = out "\n"; i++ } else { out = out c } } printf "%s", out }'
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
