#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_SCHEMA_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SCHEMA_LOADED=1

# shellcheck disable=SC2034  # read by the dispatcher when writing the header
PERSIST_SCHEMA_VERSION="1"

schema_count_kind() {
  local content="${1}" kind="${2}" line count=0
  while IFS= read -r line; do
    case "${line}" in
      "${kind}"$'\t'*) count=$(( count + 1 )) ;;
    esac
  done <<< "${content}"
  printf '%d' "${count}"
}

schema_header_field() {
  local content="${1}" index="${2}" line
  while IFS= read -r line; do
    case "${line}" in
      header$'\t'*)
        printf '%s' "${line}" | cut -d$'\t' -f"${index}"
        return 0
        ;;
    esac
  done <<< "${content}"
  return 0
}

schema_replacement_allowed() {
  local new="${1}" old="${2}"
  [[ "$(schema_count_kind "${new}" "window")" -gt 0 ]] && return 0
  [[ "$(schema_count_kind "${old}" "window")" -gt 0 ]] && return 1
  return 0
}

schema_stale() {
  local ts="${1}" now="${2}" max="${3}"
  (( max > 0 && now - ts > max )) && return 0
  return 1
}

export -f schema_count_kind
export -f schema_header_field
export -f schema_stale
export -f schema_replacement_allowed
