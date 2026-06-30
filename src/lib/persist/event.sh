#!/usr/bin/env bash
#
# event.sh: pure debounce logic for event-based saves. tmux hooks for window or
# session close and layout change can fire in bursts; debouncing collapses a burst
# into at most one save per window. No clock of its own; the caller passes the
# timestamps in. This mirrors schedule.sh but works in seconds, not minutes.

[[ -n "${_PERSIST_REVAMPED_EVENT_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_EVENT_LOADED=1

# event_disabled DEBOUNCE_SEC -> success when event saves are off (debounce <= 0).
event_disabled() {
  [[ "${1:-0}" -le 0 ]]
}

# event_should_save LAST NOW DEBOUNCE_SEC -> success when at least DEBOUNCE_SEC have
# passed since the last event save, so this event is allowed to trigger a save.
event_should_save() {
  local last="${1}" now="${2}" debounce="${3}"
  (( now - last >= debounce )) && return 0
  return 1
}

export -f event_disabled
export -f event_should_save
