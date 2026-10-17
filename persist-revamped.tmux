#!/usr/bin/env bash

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

pick_key="$(opt '@persist_revamped_pick_key' '')"
if [[ -n "${pick_key}" ]]; then
  tmux bind-key "${pick_key}" display-popup -E "bash '${DISPATCH}' pick"
fi

tmux run-shell -b "bash '${DISPATCH}' boot-sync"

tmux run-shell -b "bash '${DISPATCH}' boot"

own_hook_indices() {
  local line idx
  tmux show-hooks -g "${1}" 2>/dev/null | while IFS= read -r line; do
    [[ "${line}" == *"${DISPATCH}"* ]] || continue
    idx="${line%%\]*}"
    printf '%s\n' "${idx#*\[}"
  done
}

event_debounce="$(opt '@persist_revamped_event_debounce' '0')"
for hook in session-closed window-unlinked; do
  if [[ "${event_debounce}" =~ ^[0-9]+$ ]] && (( event_debounce > 0 )); then
    [[ -n "$(own_hook_indices "${hook}")" ]] ||
      tmux set-hook -ga "${hook}" "run-shell -b \"bash '${DISPATCH}' event\""
  else
    own_hook_indices "${hook}" | while IFS= read -r index; do
      tmux set-hook -gu "${hook}[${index}]"
    done
  fi
done

old_worker="$(opt '@persist_revamped_worker_pid' '')"
if [[ -n "${old_worker}" ]]; then
  kill "${old_worker}" 2>/dev/null || true
  tmux set-option -gqu '@persist_revamped_worker_pid'
fi

interval="$(opt '@persist_revamped_interval' '15')"
if [[ ! "${interval}" =~ ^[0-9]+$ ]] || (( interval == 0 )); then
  return 0 2>/dev/null || exit 0
fi

socket="$(tmux display-message -p '#{socket_path}' 2>/dev/null)"
worker_sleep="${PERSIST_WORKER_SLEEP:-60}"
(
  me="${BASHPID:-$(exec sh -c 'printf "%s" "${PPID}"')}"
  while sleep "${worker_sleep}" && tmux -S "${socket}" list-sessions >/dev/null 2>&1 &&
    [[ "$(tmux -S "${socket}" show-option -gqv '@persist_revamped_worker_pid' 2>/dev/null)" == "${me}" ]]; do
    bash "${DISPATCH}" auto >/dev/null 2>&1
  done
) </dev/null >/dev/null 2>&1 &
tmux set-option -gq '@persist_revamped_worker_pid' "$!"
