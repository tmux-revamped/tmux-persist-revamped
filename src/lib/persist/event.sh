#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_EVENT_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_EVENT_LOADED=1

event_disabled() {
  [[ "${1:-0}" -le 0 ]]
}

event_should_save() {
  local last="${1}" now="${2}" debounce="${3}"
  (( now - last >= debounce )) && return 0
  return 1
}

export -f event_disabled
export -f event_should_save
