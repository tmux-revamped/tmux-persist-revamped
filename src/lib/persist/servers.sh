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

# servers_socket_label PATH -> a safe directory name for a server socket path.
# tmux names its socket "default" unless -L or -S says otherwise, so every other
# label identifies a distinct environment. Anything outside the safe set collapses
# to an underscore, which keeps a socket path from escaping the save directory.
servers_socket_label() {
  local path="${1:-}" base
  base="${path##*/}"
  [[ -z "${base}" ]] && base="default"
  printf '%s' "${base}" | tr -c 'A-Za-z0-9._-' '_'
}

# servers_scope_dir BASE LABEL -> where the saves of the server labelled LABEL
# live. The default socket keeps BASE untouched, so an existing save stays where
# it is; every other server gets its own subdirectory. Without this one server's
# save overwrites another's, and a throwaway server started by a test suite counts
# as a server.
servers_scope_dir() {
  local base="${1}" label="${2:-default}"
  if [[ "${label}" == "default" ]]; then
    printf '%s' "${base}"
  else
    printf '%s/servers/%s' "${base}" "${label}"
  fi
}

export -f servers_count_from_listing
export -f servers_other_exist
export -f servers_socket_label
export -f servers_scope_dir
