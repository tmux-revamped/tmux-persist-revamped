#!/usr/bin/env bash
#
# servers.sh: pure counting of other tmux servers from a socket-directory listing.
# The actual directory read is a seam in the dispatcher; this is the parser. It
# replaces the upstream ps-argv scan that spikes CPU on macOS after sleep and
# miscounts.

[[ -n "${_PERSIST_REVAMPED_SERVERS_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SERVERS_LOADED=1

# servers_count_from_listing LISTING CURRENT -> number of sockets in LISTING (one
# name per line) other than CURRENT. Blank lines are ignored.
servers_count_from_listing() {
  local listing="${1}" current="${2}" count=0 s
  while IFS= read -r s; do
    [[ -z "${s}" ]] && continue
    [[ "${s}" == "${current}" ]] && continue
    count=$(( count + 1 ))
  done <<< "${listing}"
  printf '%d' "${count}"
}

# servers_other_exist LISTING CURRENT -> success when at least one other server
# socket is present.
servers_other_exist() {
  [[ "$(servers_count_from_listing "${1}" "${2}")" -gt 0 ]]
}

export -f servers_count_from_listing
export -f servers_other_exist
