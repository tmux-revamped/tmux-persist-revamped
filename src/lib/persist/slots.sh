#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_SLOTS_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SLOTS_LOADED=1

slots_validate() {
  local name="${1:-}"
  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && return 0
  return 1
}

slots_file() {
  local dir="${1}" name="${2:-}"
  if [[ -z "${name}" ]]; then
    printf '%s/last.txt' "${dir}"
  else
    printf '%s/slots/%s.txt' "${dir}" "${name}"
  fi
}

slots_parse_listing() {
  local listing="${1}" line name
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" == .* ]] && continue
    [[ "${line}" == *.txt ]] || continue
    name="${line%.txt}"
    printf '%s\n' "${name}"
  done <<< "${listing}"
  return 0
}

export -f slots_validate
export -f slots_file
export -f slots_parse_listing
