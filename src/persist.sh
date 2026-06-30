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
source "${PLUGIN_DIR}/src/lib/persist/slots.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/schema.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/transform.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/backup.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/event.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/persist/vimsession.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/tmux/tmux-ops.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/utils/has-command.sh"
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
readonly PERSIST_OPT_CAPTURE="@persist_revamped_capture_panes"
readonly PERSIST_OPT_CAPTURE_ARGS="@persist_revamped_capture_args"
readonly PERSIST_OPT_REDACT="@persist_revamped_redact"
readonly PERSIST_OPT_REWRITE="@persist_revamped_rewrite_home"
readonly PERSIST_OPT_VIM_SESSIONS="@persist_revamped_vim_sessions"
readonly PERSIST_OPT_BACKUPS="@persist_revamped_backups"
readonly PERSIST_OPT_EVENT_DEBOUNCE="@persist_revamped_event_debounce"
readonly PERSIST_OPT_EVENT_TS="@persist_revamped_event_ts"
readonly PERSIST_OPT_STALE_SECS="@persist_revamped_stale_secs"
readonly PERSIST_OPT_PRE_SAVE="@persist_revamped_pre_save_hook"
readonly PERSIST_OPT_POST_SAVE="@persist_revamped_post_save_hook"
readonly PERSIST_OPT_PRE_RESTORE="@persist_revamped_pre_restore_hook"
readonly PERSIST_OPT_POST_RESTORE="@persist_revamped_post_restore_hook"

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
    '#{session_name}	#{window_index}	#{window_name}	#{window_active}	#{window_layout}	#{window_zoomed_flag}' 2>/dev/null
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

# _file_exists PATH -> success when PATH is a regular file. A seam so the Vim
# session probe and the doctor report can be driven without a real filesystem.
_file_exists() {
  [[ -f "${1}" ]]
}

# _list_dir DIR PATTERN -> the base names of files in DIR matching PATTERN, one per
# line. A seam over a directory read; returns nothing when DIR has no match.
_list_dir() {
  local d="${1}" pat="${2:-*}" f
  for f in "${d}/"${pat}; do
    [[ -e "${f}" ]] || continue
    printf '%s\n' "${f##*/}"
  done
}

# _fzf -> filter stdin through fzf and echo the choice. Returns non-zero when fzf is
# absent so the caller can bail. Tests override this seam.
_fzf() {
  if has_command fzf; then
    fzf
  else
    return 1
  fi
}

# _run_hook CMD -> run a user hook. Empty CMD is a no-op. Under dry-run the command
# is echoed instead of run, so hook wiring is testable without side effects.
_run_hook() {
  local cmd="${1:-}"
  [[ -n "${cmd}" ]] || return 0
  if [[ -n "${PERSIST_DRY_RUN:-}" ]]; then
    printf 'hook %s\n' "${cmd}"
  else
    bash -c "${cmd}" >/dev/null 2>&1 || true
  fi
  return 0
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

# persist_sensitive_list -> the commands whose scrollback is never captured: the
# built-in set plus the user's extra entries.
persist_sensitive_list() {
  local extra
  extra="$(get_tmux_option "${PERSIST_OPT_REDACT}" "")"
  if [[ -n "${extra}" ]]; then
    printf '%s %s' "$(transform_default_sensitive)" "${extra}"
  else
    transform_default_sensitive
  fi
}

# --- save ------------------------------------------------------------------

# persist_dump -> the save-file content on stdout: one escaped record per window
# and per pane, then a trailing header record naming the schema version, origin
# home, and write time.
persist_dump() {
  local s wi wn wa wl wz pi pa pp pc pid capture capture_args content full forest=""
  local redact
  while IFS=$'\t' read -r s wi wn wa wl wz; do
    [[ -n "${s}" ]] && persist_join "window" "${s}" "${wi}" "${wn}" "${wa}" "${wl}" "${wz}"
  done < <(_list_windows)
  capture="$(get_tmux_option "${PERSIST_OPT_CAPTURE}" "off")"
  capture_args="$(get_tmux_option "${PERSIST_OPT_CAPTURE_ARGS}" "off")"
  redact="$(persist_sensitive_list)"
  [[ "${capture_args}" == "on" ]] && forest="$(_read_ps_forest)"
  while IFS=$'\t' read -r s wi pi pa pp pc pid; do
    [[ -n "${s}" ]] || continue
    content=""
    if [[ "${capture}" == "on" ]] && ! transform_is_sensitive "${pc}" "${redact}"; then
      content="$(persist_strip_trailing_blanks "$(_capture_pane "${s}:${wi}.${pi}")")"
    fi
    full=""
    if [[ "${capture_args}" == "on" && -n "${pid}" ]]; then
      full="$(argv_from_forest "${forest}" "${pid}" "${pc}")"
    fi
    persist_join "pane" "${s}" "${wi}" "${pi}" "${pa}" "${pp}" "${pc}" "${content}" "${full}"
  done < <(_list_panes)
  persist_join "header" "${PERSIST_SCHEMA_VERSION}" "${HOME}" "$(_now)"
}

# persist_rotate_backups TARGET -> keep a rolling set of timestamped copies of
# TARGET under TARGET's directory/backups, pruning to the configured count. A count
# of zero (the default) writes no backups at all.
persist_rotate_backups() {
  local target="${1}" keep dir bdir name victim
  keep="$(get_tmux_option "${PERSIST_OPT_BACKUPS}" "0")"
  [[ "${keep}" =~ ^[0-9]+$ ]] || return 0
  (( keep > 0 )) || return 0
  dir="$(dirname "${target}")"
  bdir="${dir}/backups"
  mkdir -p "${bdir}" 2>/dev/null || return 0
  name="$(backup_name "$(_now)")"
  cp -f "${target}" "${bdir}/${name}" 2>/dev/null || return 0
  while IFS= read -r victim; do
    [[ -n "${victim}" ]] && rm -f "${bdir}/${victim}"
  done < <(backup_prune_list "$(_list_dir "${bdir}" 'last-*.txt')" "${keep}")
  return 0
}

# persist_save [SLOT] -> write the dump atomically into SLOT's file (or last.txt
# when no slot is named): a temp file in the save dir, renamed over the target only
# when the dump succeeds. Runs the pre- and post-save hooks and rolls backups.
# Returns non-zero on any failure so the caller never advances the timestamp.
persist_save() {
  local slot="${1:-}" dir target tdir tmp
  dir="$(persist_save_dir)"
  target="$(slots_file "${dir}" "${slot}")"
  tdir="$(dirname "${target}")"
  mkdir -p "${tdir}" 2>/dev/null || { log_error "persist_save" "mkdir ${tdir} failed"; return 1; }
  chmod 0700 "${dir}" 2>/dev/null
  _run_hook "$(get_tmux_option "${PERSIST_OPT_PRE_SAVE}" "")"
  tmp="$(_mktemp "${tdir}")" || { log_error "persist_save" "mktemp in ${tdir} failed"; return 1; }
  if persist_dump >"${tmp}" 2>/dev/null && mv -f "${tmp}" "${target}"; then
    persist_rotate_backups "${target}"
    _run_hook "$(get_tmux_option "${PERSIST_OPT_POST_SAVE}" "")"
    return 0
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

# persist_restore [SLOT] [SESSION_FILTER] -> rebuild the session tree from SLOT's
# file (last.txt by default): create sessions and windows, split out extra panes,
# restore each pane's directory, reapply the layout and zoom, and replay an
# allow-listed foreground program. SESSION_FILTER, when set, restores only that one
# session (selective merge). Returns non-zero when there is nothing to load.
persist_restore() {
  local slot="${1:-}" filter="${2:-}"
  local dir file line proclist seen=""
  dir="$(persist_save_dir)"
  file="$(slots_file "${dir}" "${slot}")"
  [[ -f "${file}" ]] || return 1
  proclist="$(persist_proclist)"
  _run_hook "$(get_tmux_option "${PERSIST_OPT_PRE_RESTORE}" "")"
  local rewrite vim_sessions old_home new_home="${HOME}"
  rewrite="$(get_tmux_option "${PERSIST_OPT_REWRITE}" "off")"
  vim_sessions="$(get_tmux_option "${PERSIST_OPT_VIM_SESSIONS}" "off")"
  old_home=""
  [[ "${rewrite}" == "on" ]] && old_home="$(schema_header_field "$(cat "${file}")" 3)"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wn="${FIELDS[3]}"
    transform_keep_session "${s}" "${filter}" || continue
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
    transform_keep_session "${s}" "${filter}" || continue
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
    local rpp="${pp}"
    [[ "${rewrite}" == "on" ]] && rpp="$(transform_rewrite_path "${pp}" "${old_home}" "${new_home}")"
    _tmux send-keys -t "${key}" "cd ${rpp}" Enter
    local content="${FIELDS[7]:-}"
    [[ -n "${content}" ]] && _repaint_pane "${key}" "${content}"
    local full="${FIELDS[8]:-}"
    if [[ "${vim_sessions}" == "on" ]] && vimsession_is_editor "${pc}" && _file_exists "${rpp}/$(vimsession_file)"; then
      _tmux send-keys -t "${key}" "$(vimsession_command "${pc}")" Enter
    elif strategy_match "${pc}" "${proclist}"; then
      _tmux send-keys -t "${key}" "$(strategy_restore_command "${pc}" "${full}")" Enter
    fi
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" wa="${FIELDS[4]}" wl="${FIELDS[5]}"
    transform_keep_session "${s}" "${filter}" || continue
    [[ -n "${wl}" ]] && _tmux select-layout -t "${s}:${wi}" "${wl}"
    [[ "${wa}" == "1" ]] && _tmux select-window -t "${s}:${wi}"
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == pane* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" pi="${FIELDS[3]}" pa="${FIELDS[4]}"
    transform_keep_session "${s}" "${filter}" || continue
    [[ "${pa}" == "1" ]] && _tmux select-pane -t "${s}:${wi}.${pi}"
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" wz="${FIELDS[6]:-}"
    transform_keep_session "${s}" "${filter}" || continue
    [[ "${wz}" == "1" ]] && _tmux resize-pane -Z -t "${s}:${wi}"
  done <"${file}"
  _run_hook "$(get_tmux_option "${PERSIST_OPT_POST_RESTORE}" "")"
  return 0
}

# persist_merge SESSION [SLOT] -> restore only SESSION from a save, and never when
# that session already exists, so a running environment is never clobbered.
persist_merge() {
  local sess="${1:-}" slot="${2:-}"
  if [[ -z "${sess}" ]]; then
    printf 'usage: persist.sh merge <session> [slot]\n' >&2
    return 2
  fi
  if _has_session "${sess}"; then
    return 0
  fi
  persist_restore "${slot}" "${sess}"
}

# --- slots and inspection --------------------------------------------------

# persist_slots -> the names of the saved slots, one per line.
persist_slots() {
  local dir
  dir="$(persist_save_dir)"
  slots_parse_listing "$(_list_dir "${dir}/slots" '*.txt')"
}

# persist_pick -> let the user pick a slot through fzf and restore it. Returns
# non-zero when there are no slots or the pick is cancelled.
persist_pick() {
  local list choice
  list="$(persist_slots)"
  [[ -n "${list}" ]] || return 1
  choice="$(printf '%s\n' "${list}" | _fzf)" || return 1
  [[ -n "${choice}" ]] || return 1
  persist_restore "${choice}"
}

# persist_preview [SLOT] -> a human summary of what a save holds, without touching
# the live server. Returns non-zero when the save is missing.
persist_preview() {
  local slot="${1:-}" dir file content
  dir="$(persist_save_dir)"
  file="$(slots_file "${dir}" "${slot}")"
  if [[ ! -f "${file}" ]]; then
    printf 'no save at %s\n' "${file}"
    return 1
  fi
  content="$(cat "${file}")"
  printf 'save:    %s\n' "${file}"
  printf 'schema:  %s\n' "$(schema_header_field "${content}" 2)"
  printf 'origin:  %s\n' "$(schema_header_field "${content}" 3)"
  printf 'windows: %s\n' "$(schema_count_kind "${content}" window)"
  printf 'panes:   %s\n' "$(schema_count_kind "${content}" pane)"
  return 0
}

# persist_verify [SLOT] -> check a save's integrity: it exists, carries a schema
# header, holds at least one window, and is not stale. Prints findings and returns
# non-zero when anything is wrong.
persist_verify() {
  local slot="${1:-}" dir file content windows panes ver ts now max rc=0
  dir="$(persist_save_dir)"
  file="$(slots_file "${dir}" "${slot}")"
  if [[ ! -f "${file}" ]]; then
    printf 'FAIL no save file at %s\n' "${file}"
    return 1
  fi
  content="$(cat "${file}")"
  windows="$(schema_count_kind "${content}" window)"
  panes="$(schema_count_kind "${content}" pane)"
  ver="$(schema_header_field "${content}" 2)"
  ts="$(schema_header_field "${content}" 4)"
  if [[ -n "${ver}" ]]; then
    printf 'OK   schema version %s\n' "${ver}"
  else
    printf 'WARN no schema header (legacy save)\n'
    rc=1
  fi
  if (( windows > 0 )); then
    printf 'OK   %s window record(s)\n' "${windows}"
  else
    printf 'FAIL no window records\n'
    rc=1
  fi
  printf 'OK   %s pane record(s)\n' "${panes}"
  now="$(_now)"
  max="$(get_tmux_option "${PERSIST_OPT_STALE_SECS}" "0")"
  if [[ -n "${ts}" ]] && schema_stale "${ts}" "${now}" "${max}"; then
    printf 'WARN save is stale (older than %ss)\n' "${max}"
    rc=1
  fi
  return "${rc}"
}

# persist_doctor -> report what the plugin found on this host and why a feature may
# be inert: tmux and fzf presence, the save directory, and the active lists.
persist_doctor() {
  local dir
  dir="$(persist_save_dir)"
  printf 'tmux-persist-revamped doctor\n'
  printf 'save dir:     %s\n' "${dir}"
  if has_command tmux; then
    printf 'tmux:         found\n'
  else
    printf 'tmux:         MISSING\n'
  fi
  if has_command fzf; then
    printf 'fzf:          found (slot picker enabled)\n'
  else
    printf 'fzf:          missing (slot picker disabled)\n'
  fi
  if _file_exists "$(slots_file "${dir}" "")"; then
    printf 'default save: present\n'
  else
    printf 'default save: none yet\n'
  fi
  printf 'sensitive:    %s\n' "$(persist_sensitive_list)"
  printf 'replay list:  %s\n' "$(persist_proclist)"
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

# persist_event -> a debounced save triggered by a tmux hook (window or session
# close, layout change). Off by default; the debounce window collapses a burst of
# hooks into one save and is opt-in through the event-debounce option.
persist_event() {
  local deb now last boot grace
  deb="$(get_tmux_option "${PERSIST_OPT_EVENT_DEBOUNCE}" "0")"
  event_disabled "${deb}" && return 0
  now="$(_now)"
  # Honor the boot grace window so a close event cannot trigger a save that
  # clobbers what a restore-on-start just brought back.
  boot="$(get_tmux_option "${PERSIST_OPT_BOOT_TS}" "0")"
  grace="$(get_tmux_option "${PERSIST_OPT_BOOT_GRACE}" "60")"
  schedule_in_boot_grace "${boot}" "${now}" "${grace}" && return 0
  last="$(get_tmux_option "${PERSIST_OPT_EVENT_TS}" "0")"
  event_should_save "${last}" "${now}" "${deb}" || return 0
  set_tmux_option "${PERSIST_OPT_EVENT_TS}" "${now}"
  persist_save
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
    save) shift; persist_save "$@" ;;
    restore) shift; persist_restore "$@" ;;
    merge) shift; persist_merge "$@" ;;
    auto) persist_auto ;;
    boot) persist_boot ;;
    event) persist_event ;;
    slots) persist_slots ;;
    pick) persist_pick ;;
    preview) shift; persist_preview "$@" ;;
    verify) shift; persist_verify "$@" ;;
    doctor) persist_doctor ;;
    *) printf 'usage: persist.sh {save|restore|merge|auto|boot|event|slots|pick|preview|verify|doctor}\n' >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  persist_main "$@"
fi
