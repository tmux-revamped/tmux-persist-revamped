#!/usr/bin/env bash
#
# backup.sh: pure rolling-backup rotation. Before a save overwrites a slot, the
# previous content is copied aside under a timestamped name. These helpers name a
# backup and decide which old backups to delete so only the newest N survive. The
# copy and the delete are seams in the dispatcher; the policy lives here. Backup
# names embed a zero-padded-width epoch, so a lexical sort is a chronological sort.

[[ -n "${_PERSIST_REVAMPED_BACKUP_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_BACKUP_LOADED=1

# backup_name TS -> the file name for a backup written at epoch TS.
backup_name() {
  printf 'last-%s.txt' "${1}"
}

# backup_prune_list LISTING MAX -> the backup file names in LISTING (one per line)
# that must be deleted so at most MAX newest remain. Oldest names are emitted first.
# A MAX of zero prunes everything; nothing is emitted when the count is within MAX.
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
export -f backup_prune_list
