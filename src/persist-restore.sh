#!/usr/bin/env bash

readonly PERSIST_OPT_PRE_RESTORE="@persist_revamped_pre_restore_hook"
readonly PERSIST_OPT_POST_RESTORE="@persist_revamped_post_restore_hook"

readonly PERSIST_OPT_REWRITE="@persist_revamped_rewrite_home"
readonly PERSIST_OPT_VIM_SESSIONS="@persist_revamped_vim_sessions"

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
    _tmux send-keys -t "${key}" "cd $(transform_shell_quote "${rpp}")" Enter
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
