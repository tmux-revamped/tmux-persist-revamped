#!/usr/bin/env bash
#
# backup.sh: pure naming and pruning for the save history. Every save is written
# as its own timestamped file under history/, and the slot's path is a symlink
# pointing at the newest one, so a bad write can never destroy an earlier save and
# rolling back is repointing the link. These helpers name a history file and decide
# which old ones to delete so only the newest N survive; the writes and deletes are
# seams in the dispatcher. Names embed a fixed-width epoch, so a lexical sort is a
# chronological sort.

[[ -n "${_PERSIST_REVAMPED_BACKUP_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_BACKUP_LOADED=1

# backup_name TS -> the file name for a backup written at epoch TS.
backup_name() {
  printf 'last-%s.txt' "${1}"
}

# backup_history_base TARGET -> the file-name stem a slot's history entries share.
# "…/last.txt" yields "last" and "…/slots/work.txt" yields "work", so one slot's
# history can be listed and pruned without touching another's.
backup_history_base() {
  local target="${1}" base
  base="${target##*/}"
  printf '%s' "${base%.txt}"
}

# backup_history_name BASE TS -> the history file name for BASE written at epoch TS.
backup_history_name() {
  printf '%s-%s.txt' "${1}" "${2}"
}

# backup_history_glob BASE -> the pattern matching every history entry of BASE.
backup_history_glob() {
  printf '%s-*.txt' "${1}"
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
export -f backup_history_base
export -f backup_history_name
export -f backup_history_glob
export -f backup_prune_list
