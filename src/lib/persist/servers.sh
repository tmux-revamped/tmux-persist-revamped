#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_SERVERS_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SERVERS_LOADED=1

servers_count_from_listing() {
  local listing="${1}" current="${2}" count=0 s
  while IFS= read -r s; do
    [[ -z "${s}" ]] && continue
    [[ "${s}" == "${current}" ]] && continue
    count=$(( count + 1 ))
  done <<< "${listing}"
  printf '%d' "${count}"
}

servers_other_exist() {
  [[ "$(servers_count_from_listing "${1}" "${2}")" -gt 0 ]]
}

servers_socket_label() {
  local path="${1:-}" default_path="${2:-}" label
  if [[ -z "${path}" || "${path}" == "${default_path}" ]]; then
    printf 'default'
    return 0
  fi
  label="${path}"
  [[ -n "${default_path}" && "${path%/*}" == "${default_path%/*}" ]] && label="${path##*/}"
  printf '%s' "${label}" | tr -c 'A-Za-z0-9._-' '_'
}

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
