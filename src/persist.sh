#!/usr/bin/env bash
#
# persist.sh: the tmux-persist-revamped dispatcher. Orchestrates save, restore, and
# auto-save over the pure cores in src/lib/persist. Every tmux read is a seam the
# test suite feeds fixture data into; every tmux write goes through _tmux, which
# echoes instead of running when PERSIST_DRY_RUN is set, so the whole save/restore
# flow is verifiable without a live server.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/format.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/schedule.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/strategy.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/servers.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/tmux/tmux-ops.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/utils/error-logger.sh"

readonly PERSIST_OPT_INTERVAL="@persist_revamped_interval"
readonly PERSIST_OPT_DIR="@persist_revamped_dir"
readonly PERSIST_OPT_PROCESSES="@persist_revamped_processes"
readonly PERSIST_OPT_RESTORE_ON_START="@persist_revamped_restore_on_start"
readonly PERSIST_OPT_BOOT_GRACE="@persist_revamped_boot_grace"
readonly PERSIST_OPT_LAST_TS="@persist_revamped_last_ts"
readonly PERSIST_OPT_BOOT_TS="@persist_revamped_boot_ts"

# --- tmux seams (tests override these) -------------------------------------

_tmux() {
  if [[ -n "${PERSIST_DRY_RUN:-}" ]]; then
    printf 'tmux %s\n' "$*"
  else
    command tmux "$@"
  fi
}

_now() { date +%s; }

_list_windows() {
  command tmux list-windows -a -F \
    '#{session_name}	#{window_index}	#{window_name}	#{window_active}	#{window_layout}' 2>/dev/null
}

_list_panes() {
  command tmux list-panes -a -F \
    '#{session_name}	#{window_index}	#{pane_index}	#{pane_active}	#{pane_current_path}	#{pane_current_command}' 2>/dev/null
}

_has_session() {
  command tmux has-session -t "${1}" 2>/dev/null
}

_mktemp() {
  mktemp "${1}/.save.XXXXXX" 2>/dev/null
}

# --- options ---------------------------------------------------------------

persist_save_dir() {
  local custom
  custom="$(get_tmux_option "${PERSIST_OPT_DIR}" "")"
  if [[ -n "${custom}" ]]; then
    printf '%s' "${custom}"
    return 0
  fi
  printf '%s/tmux/persist' "${XDG_STATE_HOME:-${HOME}/.local/state}"
}

persist_proclist() {
  local extra
  extra="$(get_tmux_option "${PERSIST_OPT_PROCESSES}" "")"
  if [[ -n "${extra}" ]]; then
    printf '%s %s' "$(strategy_default_list)" "${extra}"
  else
    strategy_default_list
  fi
}

# --- save ------------------------------------------------------------------

# persist_dump -> the save-file content on stdout: one escaped record per window
# and per pane.
persist_dump() {
  local s wi wn wa wl pi pa pp pc
  while IFS=$'\t' read -r s wi wn wa wl; do
    [[ -n "${s}" ]] && persist_join "window" "${s}" "${wi}" "${wn}" "${wa}" "${wl}"
  done < <(_list_windows)
  while IFS=$'\t' read -r s wi pi pa pp pc; do
    [[ -n "${s}" ]] && persist_join "pane" "${s}" "${wi}" "${pi}" "${pa}" "${pp}" "${pc}"
  done < <(_list_panes)
}

# persist_save -> write the dump atomically: a temp file in the save dir, renamed
# over last.txt only when the dump succeeds. Returns non-zero on any failure so the
# caller never advances the timestamp.
persist_save() {
  local dir tmp
  dir="$(persist_save_dir)"
  mkdir -p "${dir}" 2>/dev/null || { log_error "persist_save" "mkdir ${dir} failed"; return 1; }
  chmod 0700 "${dir}" 2>/dev/null
  tmp="$(_mktemp "${dir}")" || { log_error "persist_save" "mktemp in ${dir} failed"; return 1; }
  if persist_dump >"${tmp}" 2>/dev/null; then
    mv -f "${tmp}" "${dir}/last.txt" && return 0
  fi
  rm -f "${tmp}"
  log_error "persist_save" "dump failed"
  return 1
}

# --- restore ---------------------------------------------------------------

# _read_fields LINE -> populate the global FIELDS array with the record's fields.
_read_fields() {
  FIELDS=()
  local f
  while IFS= read -r f; do
    FIELDS+=("$(persist_unescape "${f}")")
  done < <(persist_split "${1}")
}

# persist_restore -> rebuild the session tree from last.txt: create sessions and
# windows, split out extra panes, restore each pane's directory, and replay an
# allow-listed foreground program. Returns non-zero when there is nothing to load.
persist_restore() {
  local dir file line proclist seen=""
  dir="$(persist_save_dir)"
  file="${dir}/last.txt"
  [[ -f "${file}" ]] || return 1
  proclist="$(persist_proclist)"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wn="${FIELDS[3]}"
    if _has_session "${s}"; then
      _tmux new-window -t "${s}:" -n "${wn}"
    else
      _tmux new-session -d -s "${s}" -n "${wn}"
    fi
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == pane* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" pp="${FIELDS[5]}" pc="${FIELDS[6]}"
    local key="${s}:${wi}"
    if [[ " ${seen} " == *" ${key} "* ]]; then
      _tmux split-window -t "${key}"
    else
      seen="${seen} ${key}"
    fi
    _tmux send-keys -t "${key}" "cd ${pp}" Enter
    if strategy_match "${pc}" "${proclist}"; then
      _tmux send-keys -t "${key}" "${pc}" Enter
    fi
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" wa="${FIELDS[4]}" wl="${FIELDS[5]}"
    [[ -n "${wl}" ]] && _tmux select-layout -t "${s}:${wi}" "${wl}"
    [[ "${wa}" == "1" ]] && _tmux select-window -t "${s}:${wi}"
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == pane* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" pi="${FIELDS[3]}" pa="${FIELDS[4]}"
    [[ "${pa}" == "1" ]] && _tmux select-pane -t "${s}:${wi}.${pi}"
  done <"${file}"
  return 0
}

# --- automation ------------------------------------------------------------

# persist_auto -> the periodic tick: save when enabled, out of boot grace, and the
# interval has elapsed, advancing the timestamp only on a successful save.
persist_auto() {
  local interval now last boot grace
  interval="$(get_tmux_option "${PERSIST_OPT_INTERVAL}" "15")"
  schedule_autosave_disabled "${interval}" && return 0
  now="$(_now)"
  boot="$(get_tmux_option "${PERSIST_OPT_BOOT_TS}" "0")"
  grace="$(get_tmux_option "${PERSIST_OPT_BOOT_GRACE}" "60")"
  schedule_in_boot_grace "${boot}" "${now}" "${grace}" && return 0
  last="$(get_tmux_option "${PERSIST_OPT_LAST_TS}" "0")"
  schedule_interval_elapsed "${last}" "${now}" "${interval}" || return 0
  local rc=0
  persist_save || rc="$?"
  if schedule_should_stamp "${rc}"; then
    set_tmux_option "${PERSIST_OPT_LAST_TS}" "${now}"
  fi
}

# persist_boot -> restore on server start when enabled, then stamp the boot time so
# the grace window can suppress the first auto-saves.
persist_boot() {
  [[ "$(get_tmux_option "${PERSIST_OPT_RESTORE_ON_START}" "off")" == "on" ]] || return 0
  persist_restore || true
  set_tmux_option "${PERSIST_OPT_BOOT_TS}" "$(_now)"
}

# --- dispatch --------------------------------------------------------------

persist_main() {
  case "${1:-}" in
    save) persist_save ;;
    restore) persist_restore ;;
    auto) persist_auto ;;
    boot) persist_boot ;;
    *) printf 'usage: persist.sh {save|restore|auto|boot}\n' >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  persist_main "$@"
fi
