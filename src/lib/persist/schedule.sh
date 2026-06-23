#!/usr/bin/env bash
#
# schedule.sh: pure timing logic for auto-save. No tmux, no clock of its own; the
# caller passes timestamps in. This is where the boot-race and the
# stamp-only-on-success fixes live.

[[ -n "${_PERSIST_REVAMPED_SCHEDULE_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_SCHEDULE_LOADED=1

# schedule_autosave_disabled INTERVAL_MIN -> success when auto-save is off
# (interval of zero or less).
schedule_autosave_disabled() {
  [[ "${1:-0}" -le 0 ]]
}

# schedule_interval_elapsed LAST NOW INTERVAL_MIN -> success when at least
# INTERVAL_MIN minutes have passed since LAST, so a save is due.
schedule_interval_elapsed() {
  local last="${1}" now="${2}" mins="${3}"
  (( now - last >= mins * 60 ))
}

# schedule_in_boot_grace BOOT NOW GRACE_SEC -> success while still inside the grace
# window that follows a restore-on-start, during which auto-save must not run so it
# cannot clobber the restore. A BOOT of zero means no restore happened, so no grace.
schedule_in_boot_grace() {
  local boot="${1}" now="${2}" grace="${3}"
  (( boot > 0 && now - boot < grace ))
}

# schedule_should_stamp EXIT -> success only when the save command exited zero, so a
# failed save never advances the last-save timestamp.
schedule_should_stamp() {
  [[ "${1}" -eq 0 ]]
}

export -f schedule_autosave_disabled
export -f schedule_interval_elapsed
export -f schedule_in_boot_grace
export -f schedule_should_stamp
