#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_BACKUP_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_BACKUP_LOADED=1

backup_name() {
  printf 'last-%s.txt' "${1}"
}

backup_history_base() {
  local target="${1}" base
  base="${target##*/}"
  printf '%s' "${base%.txt}"
}

backup_history_name() {
  printf '%s-%s.txt' "${1}" "${2}"
}

backup_history_glob() {
  printf '%s-*.txt' "${1}"
}

backup_history_entries() {
  local base="${1}" listing="${2}" line stamp
  local prefix="${base}-" suffix=".txt"
  while IFS= read -r line; do
    [[ "${line}" == "${prefix}"*"${suffix}" ]] || continue
    stamp="${line#"${prefix}"}"
    stamp="${stamp%"${suffix}"}"
    [[ "${stamp}" =~ ^[0-9]+$ ]] || continue
    printf '%s\n' "${line}"
  done <<< "${listing}"
  return 0
}

backup_prune_list() {
  local listing="${1}" max="${2}" line
  local -a names=()
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    names+=("${line}")
  done <<< "${listing}"
  local total="${#names[@]}"
  (( total == 0 )) && return 0
  (( max < 0 )) && max=0
  local -a sorted=()
  while IFS= read -r line; do
    sorted+=("${line}")
  done < <(printf '%s\n' "${names[@]}" | sort)
  local prune=$(( total - max )) i
  (( prune <= 0 )) && return 0
  for (( i = 0; i < prune; i++ )); do
    printf '%s\n' "${sorted[i]}"
  done
  return 0
}

export -f backup_name
export -f backup_history_base
export -f backup_history_name
export -f backup_history_glob
export -f backup_history_entries
export -f backup_prune_list
