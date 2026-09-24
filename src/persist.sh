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
source "${PLUGIN_DIR}/src/lib/persist/boot.sh"
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
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/persist-boot.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/persist-restore.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/persist-report.sh"

readonly PERSIST_OPT_INTERVAL="@persist_revamped_interval"
readonly PERSIST_OPT_DIR="@persist_revamped_dir"
readonly PERSIST_OPT_SCOPE_SOCKET="@persist_revamped_scope_socket"
readonly PERSIST_OPT_HALT_FILE="@persist_revamped_halt_file"
readonly PERSIST_OPT_PROCESSES="@persist_revamped_processes"
readonly PERSIST_OPT_RESTORE_ON_START="@persist_revamped_restore_on_start"
readonly PERSIST_OPT_BOOT_GRACE="@persist_revamped_boot_grace"
readonly PERSIST_OPT_LAST_TS="@persist_revamped_last_ts"
readonly PERSIST_OPT_BOOT_TS="@persist_revamped_boot_ts"
readonly PERSIST_OPT_BOOTED="@persist_revamped_booted"
readonly PERSIST_OPT_CAPTURE="@persist_revamped_capture_panes"
readonly PERSIST_OPT_CAPTURE_ARGS="@persist_revamped_capture_args"
readonly PERSIST_OPT_REDACT="@persist_revamped_redact"
readonly PERSIST_OPT_BACKUPS="@persist_revamped_backups"
readonly PERSIST_OPT_EVENT_DEBOUNCE="@persist_revamped_event_debounce"
readonly PERSIST_OPT_EVENT_TS="@persist_revamped_event_ts"
readonly PERSIST_OPT_PRE_SAVE="@persist_revamped_pre_save_hook"
readonly PERSIST_OPT_POST_SAVE="@persist_revamped_post_save_hook"

# --- tmux seams (tests override these) -------------------------------------

_tmux() {
  if [[ -n "${PERSIST_DRY_RUN:-}" ]]; then
    printf 'tmux %s\n' "$*"
  else
    command tmux "$@"
  fi
}

_now() { date +%s; }

# _socket_path -> the socket of the server this call is talking to. tmux answers
# "default" unless the server was started with -L or -S, so the value identifies
# the environment the save belongs to.
_socket_path() {
  command tmux display-message -p '#{socket_path}' 2>/dev/null
}

# _hostname -> this host's name, for expanding $HOSTNAME in the save directory.
_hostname() {
  hostname 2>/dev/null
}

# _lock_acquire PATH -> success when this process took the save lock. mkdir is the
# atomic primitive available everywhere. A lock left behind by a killed save is
# taken over once it is older than two minutes, which is far longer than a save.
_lock_acquire() {
  local lock="${1}"
  mkdir "${lock}" 2>/dev/null && return 0
  [[ -n "$(find "${lock}" -maxdepth 0 -mmin +2 2>/dev/null)" ]] || return 1
  rmdir "${lock}" 2>/dev/null || return 1
  mkdir "${lock}" 2>/dev/null
}

_lock_release() {
  rmdir "${1}" 2>/dev/null || true
}

# _save_body PATH -> the save's records without its header. The header carries the
# write time, so two saves of one unchanged environment differ in it and in nothing
# else; comparing bodies is what lets an unchanged environment be recognised.
_save_body() {
  grep -v "^header	" "${1}" 2>/dev/null
}

# _files_identical A B -> success when both exist and describe the same environment.
# A save that repeats the previous one is dropped rather than added to the history,
# so an idle machine does not fill the history with copies of one environment.
_files_identical() {
  [[ -e "${1}" && -e "${2}" ]] || return 1
  [[ "$(_save_body "${1}")" == "$(_save_body "${2}")" ]]
}

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
  local custom base scope label
  custom="$(get_tmux_option "${PERSIST_OPT_DIR}" "")"
  if [[ -n "${custom}" ]]; then
    base="$(transform_expand_path "${custom}" "${HOME}" "$(_hostname)")"
  else
    base="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/persist"
  fi
  scope="$(get_tmux_option "${PERSIST_OPT_SCOPE_SOCKET}" "on")"
  if [[ "${scope}" != "on" ]]; then
    printf '%s' "${base}"
    return 0
  fi
  label="$(servers_socket_label "$(_socket_path)")"
  servers_scope_dir "${base}" "${label}"
}

persist_halt_file() {
  local custom
  custom="$(get_tmux_option "${PERSIST_OPT_HALT_FILE}" "")"
  if [[ -n "${custom}" ]]; then
    transform_expand_path "${custom}" "${HOME}" "$(_hostname)"
    return 0
  fi
  printf '%s/no-restore' "$(persist_save_dir)"
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
  local target="${1}" keep hdir base victim
  keep="$(get_tmux_option "${PERSIST_OPT_BACKUPS}" "5")"
  [[ "${keep}" =~ ^[0-9]+$ ]] || keep=5
  # The current save is one of the kept entries, so the floor is one. A zero here
  # would prune the file the slot symlink points at and leave a dangling link.
  (( keep < 1 )) && keep=1
  hdir="$(persist_history_dir "${target}")"
  base="$(backup_history_base "${target}")"
  while IFS= read -r victim; do
    [[ -n "${victim}" ]] && rm -f "${hdir}/${victim}"
  done < <(backup_prune_list "$(_list_dir "${hdir}" "$(backup_history_glob "${base}")")" "${keep}")
  return 0
}

# persist_unique_history_name DIR BASE TS -> a history file name for BASE that is
# not taken yet, advancing the stamp until it is free. Two writes inside one second
# are normal when a save follows an adoption, and a name collision would silently
# drop the older of the two.
persist_unique_history_name() {
  local dir="${1}" base="${2}" ts="${3}" name
  name="$(backup_history_name "${base}" "${ts}")"
  while [[ -e "${dir}/${name}" ]]; do
    ts=$(( ts + 1 ))
    name="$(backup_history_name "${base}" "${ts}")"
  done
  printf '%s' "${name}"
}

# persist_history_dir TARGET -> where TARGET's timestamped saves live. One level
# below the slot file, so listing and pruning a slot's history never walks over the
# save directory itself or over another slot.
persist_history_dir() {
  printf '%s/history' "$(dirname "${1}")"
}

# persist_adopt_legacy_save TARGET -> move a pre-history regular file into the
# history directory and leave the slot pointing at it. Without this the first save
# after an upgrade would replace the only existing save with a symlink, which is
# the exact loss this whole design exists to prevent.
persist_adopt_legacy_save() {
  local target="${1}" hdir name
  [[ -f "${target}" && ! -L "${target}" ]] || return 0
  hdir="$(persist_history_dir "${target}")"
  mkdir -p "${hdir}" 2>/dev/null || return 0
  name="$(persist_unique_history_name "${hdir}" "$(backup_history_base "${target}")" "$(_now)")"
  mv -f "${target}" "${hdir}/${name}" 2>/dev/null || return 0
  ln -sfn "history/${name}" "${target}" 2>/dev/null || true
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
  local lock="${dir}/.save.lock"
  _lock_acquire "${lock}" || { log_error "persist_save" "another save holds ${lock}"; return 1; }
  _run_hook "$(get_tmux_option "${PERSIST_OPT_PRE_SAVE}" "")"
  tmp="$(_mktemp "${tdir}")" || { _lock_release "${lock}"; log_error "persist_save" "mktemp in ${tdir} failed"; return 1; }
  if ! persist_dump >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    _lock_release "${lock}"
    log_error "persist_save" "dump failed"
    return 1
  fi
  if ! schema_replacement_allowed "$(cat "${tmp}" 2>/dev/null)" "$(cat "${target}" 2>/dev/null)"; then
    rm -f "${tmp}"
    _lock_release "${lock}"
    log_error "persist_save" "refused an empty dump over ${target}"
    return 1
  fi
  persist_adopt_legacy_save "${target}"
  local hdir name
  hdir="$(persist_history_dir "${target}")"
  mkdir -p "${hdir}" 2>/dev/null
  name="$(persist_unique_history_name "${hdir}" "$(backup_history_base "${target}")" "$(_now)")"
  if ! mv -f "${tmp}" "${hdir}/${name}"; then
    rm -f "${tmp}"
    _lock_release "${lock}"
    log_error "persist_save" "could not write ${hdir}/${name}"
    return 1
  fi
  if _files_identical "${hdir}/${name}" "${target}"; then
    rm -f "${hdir}/${name}"
  else
    ln -sfn "history/${name}" "${target}" 2>/dev/null || true
  fi
  persist_rotate_backups "${target}"
  _lock_release "${lock}"
  _run_hook "$(get_tmux_option "${PERSIST_OPT_POST_SAVE}" "")"
  return 0
}

# --- restore ---------------------------------------------------------------

# --- slots and inspection --------------------------------------------------

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
  if _file_exists "$(persist_halt_file)"; then
    set_tmux_option "${PERSIST_OPT_BOOTED}" "1"
    return 0
  fi
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
    boot-install) persist_boot_install ;;
    boot-uninstall) persist_boot_uninstall ;;
    boot-sync) persist_boot_sync ;;
    *) printf 'usage: persist.sh {save|restore|merge|auto|boot|boot-install|boot-uninstall|boot-sync|event|slots|pick|preview|verify|doctor}\n' >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  persist_main "$@"
fi
