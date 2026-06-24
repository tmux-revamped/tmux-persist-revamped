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
readonly PERSIST_OPT_BOOTED="@persist_revamped_booted"

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
    '#{session_name}	#{window_index}	#{pane_index}	#{pane_active}	#{pane_current_path}	#{pane_current_command}	#{pane_pid}' 2>/dev/null
}

_has_session() {
  command tmux has-session -t "${1}" 2>/dev/null
}

_mktemp() {
  mktemp "${1}/.save.XXXXXX" 2>/dev/null
}

_capture_pane() {
  command tmux capture-pane -p -t "${1}" 2>/dev/null
}

# _pane_current_command TARGET -> the command currently running in TARGET's active
# pane. Used to decide whether sending keys to the pane is safe. Under dry-run the
# tests feed a value through PERSIST_FAKE_PANE_CMD, defaulting to a shell so the
# normal restore path stays exercised.
_pane_current_command() {
  if [[ -n "${PERSIST_DRY_RUN:-}" ]]; then
    printf '%s' "${PERSIST_FAKE_PANE_CMD:-zsh}"
  else
    command tmux display-message -p -t "${1}" '#{pane_current_command}' 2>/dev/null
  fi
}

# _read_ps_forest -> "pid ppid command-with-args" for every process. The flags
# differ by userland: BSD ps treats -e as "show environment", so macOS needs
# -axo command=, while Linux procps needs -eo args=. Any failure yields empty,
# which makes the caller fall back to the bare command, never a wrong one.
_read_ps_forest() {
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    ps -axo pid=,ppid=,command= 2>/dev/null
  else
    ps -eo pid=,ppid=,args= 2>/dev/null
  fi
}

# argv_from_forest FOREST SHELL_PID [EXPECT] -> the full command line of
# SHELL_PID's foreground program, read from a direct child of the pane shell.
# FOREST is _read_ps_forest output. When EXPECT is given (the pane_current_command)
# only a child whose program basename matches it is returned, so a backgrounded
# sibling with a higher pid can never be replayed in its place; with no match the
# result is empty and the caller falls back to the bare command. Without EXPECT
# the highest-pid child is returned. Pure: fixture in, string out, no ps, no tmux.
argv_from_forest() {
  local forest="${1}" pid="${2}" expect="${3:-}"
  local fpid fppid frest base match="" fb="" fbpid=""
  while read -r fpid fppid frest; do
    [[ "${fppid}" == "${pid}" ]] || continue
    if [[ -z "${fbpid}" ]] || (( fpid > fbpid )); then fbpid="${fpid}"; fb="${frest}"; fi
    if [[ -n "${expect}" && -z "${match}" ]]; then
      base="${frest%% *}"; base="${base##*/}"
      [[ "${base}" == "${expect}"* ]] && match="${frest}"
    fi
  done <<< "${forest}"
  if [[ -n "${match}" ]]; then printf '%s' "${match}"; return 0; fi
  if [[ -z "${expect}" && -n "${fb}" ]]; then printf '%s' "${fb}"; return 0; fi
  echo ""
}

# _repaint_pane TARGET CONTENT -> redraw a pane's saved screen by writing the
# content to a temp file and having the pane's shell cat it. The content is
# catted from a file rather than typed, so it can never be executed as commands.
_repaint_pane() {
  local target="${1}" content="${2}" tmpf
  tmpf="$(_mktemp "$(persist_save_dir)")" || return 0
  printf '%s\n' "${content}" >"${tmpf}" 2>/dev/null || { rm -f "${tmpf}"; return 0; }
  _tmux send-keys -t "${target}" "clear; cat -- '${tmpf}'; command rm -f -- '${tmpf}'" Enter
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
  local s wi wn wa wl pi pa pp pc pid capture capture_args content full forest=""
  while IFS=$'\t' read -r s wi wn wa wl; do
    [[ -n "${s}" ]] && persist_join "window" "${s}" "${wi}" "${wn}" "${wa}" "${wl}"
  done < <(_list_windows)
  capture="$(get_tmux_option "@persist_revamped_capture_panes" "off")"
  capture_args="$(get_tmux_option "@persist_revamped_capture_args" "off")"
  [[ "${capture_args}" == "on" ]] && forest="$(_read_ps_forest)"
  while IFS=$'\t' read -r s wi pi pa pp pc pid; do
    [[ -n "${s}" ]] || continue
    content=""
    if [[ "${capture}" == "on" ]]; then
      content="$(persist_strip_trailing_blanks "$(_capture_pane "${s}:${wi}.${pi}")")"
    fi
    full=""
    if [[ "${capture_args}" == "on" && -n "${pid}" ]]; then
      full="$(argv_from_forest "${forest}" "${pid}" "${pc}")"
    fi
    persist_join "pane" "${s}" "${wi}" "${pi}" "${pa}" "${pp}" "${pc}" "${content}" "${full}"
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
    # Never type into a pane that is not a shell. A restore against a live server
    # can resolve to a window that already runs a program, and sending keys there
    # would inject commands into it. Skip the directory, repaint, and program
    # replay for any such pane.
    is_shell_cmd "$(_pane_current_command "${key}")" || continue
    _tmux send-keys -t "${key}" "cd ${pp}" Enter
    local content="${FIELDS[7]:-}"
    [[ -n "${content}" ]] && _repaint_pane "${key}" "${content}"
    local full="${FIELDS[8]:-}"
    if strategy_match "${pc}" "${proclist}"; then
      _tmux send-keys -t "${key}" "$(strategy_restore_command "${pc}" "${full}")" Enter
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
  # Restore once per server lifetime, not on every config reload. The entry point
  # runs boot on each plugin load, but a server option survives reloads and resets
  # only when the server dies, so it tells a genuine server start apart from a
  # source-file. Stamp the marker before restoring so a reload mid-restore cannot
  # start a second one.
  [[ "$(get_tmux_option "${PERSIST_OPT_BOOTED}" "0")" == "1" ]] && return 0
  set_tmux_option "${PERSIST_OPT_BOOTED}" "1"
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
