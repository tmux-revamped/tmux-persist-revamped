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
fi

socket="$(tmux display-message -p '#{socket_path}' 2>/dev/null)"
(
  while [[ -S "${socket}" ]]; do
    sleep 60
    bash "${DISPATCH}" auto >/dev/null 2>&1
  done
) &
tmux set-option -gq '@persist_revamped_worker_pid' "$!"
