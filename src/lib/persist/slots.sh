#!/usr/bin/env bash
#
# slots.sh: pure helpers for named save slots. A slot parks a whole environment
# under its own file so several can coexist and be swapped. The default (empty)
# slot is the legacy single last.txt, so nothing changes for callers that never
# name a slot. No tmux and no files here: path strings in, path strings out, and
# the directory read is a seam in the dispatcher.

[[ -n "${_PERSIST_REVAMPED_SLOTS_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SLOTS_LOADED=1

# slots_validate NAME -> success when NAME is a safe slot name: it must start with
# an alphanumeric and contain only letters, digits, dot, dash, and underscore. This
# keeps a slot name from escaping the slots directory or naming a hidden temp file.
slots_validate() {
  local name="${1:-}"
  [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && return 0
  return 1
}

# slots_file DIR NAME -> the save-file path for a slot. An empty NAME resolves to
# the legacy ${DIR}/last.txt; a named slot lives under ${DIR}/slots/${NAME}.txt.
slots_file() {
  local dir="${1}" name="${2:-}"
  if [[ -z "${name}" ]]; then
    printf '%s/last.txt' "${dir}"
  else
    printf '%s/slots/%s.txt' "${dir}" "${name}"
  fi
}

# slots_parse_listing LISTING -> the slot names in a directory LISTING (one file
# name per line). Only "*.txt" files count, hidden names (a leading dot, such as a
# ".save.XXXX" temp file) are skipped, and the ".txt" suffix is stripped.
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
