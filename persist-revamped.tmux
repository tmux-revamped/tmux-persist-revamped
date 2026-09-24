#!/usr/bin/env bash
#
# persist-revamped.tmux: TPM entry point. Binds the save and restore keys, kicks
# off a restore on server start when enabled, and runs a single detached auto-save
# worker. The worker ticks on a timer and calls the dispatcher's `auto`, which
# itself decides whether a save is actually due, so nothing ever touches
# status-right the way the upstream plugin does.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="${CURRENT_DIR}/src/persist.sh"

opt() {
  local v
  v="$(tmux show-option -gqv "${1}" 2>/dev/null)"
  printf '%s' "${v:-${2}}"
}

save_key="$(opt '@persist_revamped_save_key' 'C-s')"
restore_key="$(opt '@persist_revamped_restore_key' 'C-r')"

tmux bind-key "${save_key}" run-shell "bash '${DISPATCH}' save"
tmux bind-key "${restore_key}" run-shell "bash '${DISPATCH}' restore"

# Opt-in slot picker: bound only when a key is configured, since it needs fzf in a
# popup. Restores whichever named slot the user selects.
pick_key="$(opt '@persist_revamped_pick_key' '')"
if [[ -n "${pick_key}" ]]; then
  tmux bind-key "${pick_key}" display-popup -E "bash '${DISPATCH}' pick"
fi

# Install or remove the login agent to match @persist_revamped_boot. Restoring on
# server start only helps once a server exists, and on a freshly booted machine
# nothing has started one until a terminal is opened.
tmux run-shell -b "bash '${DISPATCH}' boot-sync"

# Restore on start, then stamp the boot time so the grace window can suppress the
# first auto-saves and avoid clobbering what was just restored.
tmux run-shell -b "bash '${DISPATCH}' boot"

# Opt-in event-based saves. When a debounce window is configured, genuine close
# events trigger a debounced save. Only close events are wired so a save can never
# fire while a restore is still creating windows.
event_debounce="$(opt '@persist_revamped_event_debounce' '0')"
if [[ "${event_debounce}" =~ ^[0-9]+$ ]] && (( event_debounce > 0 )); then
  for hook in session-closed window-unlinked; do
    tmux set-hook -g "${hook}" "run-shell -b \"bash '${DISPATCH}' event\""
  done
fi

# One auto-save worker per server. Kill a stale worker recorded in the server
# option, then detach a new one that ticks roughly every minute and exits when the
# server goes away. The tick is cheap; `auto` no-ops until the interval elapses.
old_worker="$(opt '@persist_revamped_worker_pid' '')"
if [[ -n "${old_worker}" ]]; then
  kill "${old_worker}" 2>/dev/null || true
  tmux set-option -gqu '@persist_revamped_worker_pid'
fi

# An interval of 0 is documented as auto-save off, so honour it here rather than
# spawning a worker that wakes every minute only to decide it has nothing to do.
# On a machine that runs a plugin test suite this is the difference between one
# background process and one per throwaway server.
interval="$(opt '@persist_revamped_interval' '15')"
if [[ ! "${interval}" =~ ^[0-9]+$ ]] || (( interval == 0 )); then
  return 0 2>/dev/null || exit 0
fi

socket="$(tmux display-message -p '#{socket_path}' 2>/dev/null)"
# The worker has to let go of this script's stdin, stdout and stderr. A
# background child that keeps them open holds the pipe open too, so tmux's
# run-shell waits on the worker instead of on the entry point and the config
# reload stalls for as long as the server lives.
(
  while [[ -S "${socket}" ]]; do
    sleep 60
    bash "${DISPATCH}" auto >/dev/null 2>&1
  done
) </dev/null >/dev/null 2>&1 &
tmux set-option -gq '@persist_revamped_worker_pid' "$!"
