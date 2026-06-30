#!/usr/bin/env bash
#
# schema.sh: pure save-file integrity logic for doctor/verify. A save file carries
# one trailing "header" record naming the schema version, the origin home, and the
# write time. These helpers parse that header and count the records so verify can
# report a save's shape and staleness without a live server. Text in, text out.

[[ -n "${_PERSIST_REVAMPED_SCHEMA_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SCHEMA_LOADED=1

# The on-disk save-file schema. Bumped only when the record layout changes.
# shellcheck disable=SC2034  # read by the dispatcher when writing the header
PERSIST_SCHEMA_VERSION="1"

# schema_count_kind CONTENT KIND -> how many records in CONTENT start with KIND.
# A record is "<kind><TAB>...", so the match is anchored to the kind plus a tab.
schema_count_kind() {
  local content="${1}" kind="${2}" line count=0
  while IFS= read -r line; do
    case "${line}" in
      "${kind}"$'\t'*) count=$(( count + 1 )) ;;
    esac
  done <<< "${content}"
  printf '%d' "${count}"
}

# schema_header_field CONTENT INDEX -> field INDEX (1-based) of the header record in
# CONTENT, or empty when there is no header. The header is "header<TAB>ver<TAB>home
# <TAB>ts", so index 2 is the version, 3 the origin home, 4 the write timestamp.
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

# schema_stale TS NOW MAX_SECONDS -> success when the save is older than MAX_SECONDS.
# A MAX_SECONDS of zero or less disables the staleness check (never stale).
schema_stale() {
  local ts="${1}" now="${2}" max="${3}"
  (( max > 0 && now - ts > max )) && return 0
  return 1
}

export -f schema_count_kind
export -f schema_header_field
export -f schema_stale
