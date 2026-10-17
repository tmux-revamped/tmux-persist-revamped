#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_SCHEDULE_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SCHEDULE_LOADED=1

schedule_autosave_disabled() {
  [[ "${1:-0}" -le 0 ]]
}

schedule_interval_elapsed() {
  local last="${1}" now="${2}" mins="${3}"
  (( now - last >= mins * 60 ))
}

schedule_in_boot_grace() {
  local boot="${1}" now="${2}" grace="${3}"
  (( boot > 0 && now - boot < grace ))
}

schedule_should_stamp() {
  [[ "${1}" -eq 0 ]]
}

export -f schedule_autosave_disabled
export -f schedule_interval_elapsed
export -f schedule_in_boot_grace
export -f schedule_should_stamp
