#!/usr/bin/env bash

readonly PERSIST_OPT_PRE_RESTORE="@persist_revamped_pre_restore_hook"
readonly PERSIST_OPT_POST_RESTORE="@persist_revamped_post_restore_hook"

readonly PERSIST_OPT_REWRITE="@persist_revamped_rewrite_home"
readonly PERSIST_OPT_VIM_SESSIONS="@persist_revamped_vim_sessions"
readonly PERSIST_SHELL_WAIT_TRIES=50

_read_fields() {
  FIELDS=()
  local f
  while IFS= read -r f; do
    FIELDS+=("$(persist_unescape "${f}")")
  done < <(persist_split "${1}")
}

_tmux_created() {
  _CREATED_INDEX=""
  if [[ -n "${PERSIST_DRY_RUN:-}" ]]; then
    printf 'tmux %s\n' "$*"
  else
    _CREATED_INDEX="$(command tmux "$@" -P -F '#{window_index}' 2>/dev/null)"
  fi
}

_window_taken() {
  command tmux list-windows -t "=${1}" -F '#{window_index}' 2>/dev/null | grep -qx "${2}"
}

_window_alive() {
  command tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -qxF "${1}"
}

_list_boot_panes() {
  command tmux list-panes -a -F '#{session_windows}	#{window_panes}	#{session_name}:#{window_index}	#{window_id}	#{pane_start_command}' 2>/dev/null
}

_line_in() {
  local item
  while IFS= read -r item; do
    [[ "${item}" == "${2}" ]] && return 0
  done <<<"${1}"
  return 1
}

_lookup() {
  local entry tab=$'\t'
  while IFS= read -r entry; do
    [[ -n "${entry}" && "${entry%%"${tab}"*}" == "${2}" ]] || continue
    printf '%s' "${entry#*"${tab}"}"
    return 0
  done <<<"${1}"
  return 1
}

persist_boot_placeholders() {
  local sw wp target id start
  while IFS=$'\t' read -r sw wp target id start; do
    [[ "${sw}" == "1" && "${wp}" == "1" && -z "${start}" ]] || continue
    printf '%s\t%s\n' "${target}" "${id}"
  done < <(_list_boot_panes)
}

_read_dir_args() {
  local rest="${1}" out="" hash="#"
  DIR_ARGS=()
  [[ -n "${rest}" ]] || return 0
  while [[ "${rest}" == *"${hash}"* ]]; do
    out+="${rest%%"${hash}"*}${hash}${hash}"
    rest="${rest#*"${hash}"}"
  done
  DIR_ARGS=(-c "${out}${rest}")
}

_restore_new_session() {
  local s="${1}" wi="${2}" wn="${3}"
  _tmux_created new-session -d -s "${s}" -n "${wn}" ${DIR_ARGS[@]+"${DIR_ARGS[@]}"}
  [[ -n "${_CREATED_INDEX}" && "${_CREATED_INDEX}" != "${wi}" ]] || return 0
  _tmux move-window -s "${s}:${_CREATED_INDEX}" -t "${s}:${wi}" || _LANDED="${s}:${_CREATED_INDEX}"
}

_restore_window() {
  local s="${1}" wi="${2}" wn="${3}" placeholders="${4}"
  _LANDED="${s}:${wi}"
  _read_dir_args "${5:-}"
  if ! _has_session "${s}"; then
    _restore_new_session "${s}" "${wi}" "${wn}"
  elif _lookup "${placeholders}" "${s}:${wi}" >/dev/null; then
    _tmux new-window -k -t "${s}:${wi}" -n "${wn}" ${DIR_ARGS[@]+"${DIR_ARGS[@]}"}
  elif ! _window_taken "${s}" "${wi}"; then
    _tmux new-window -t "${s}:${wi}" -n "${wn}" ${DIR_ARGS[@]+"${DIR_ARGS[@]}"}
  else
    _tmux_created new-window -t "${s}:" -n "${wn}" ${DIR_ARGS[@]+"${DIR_ARGS[@]}"}
    [[ -z "${_CREATED_INDEX}" ]] || _LANDED="${s}:${_CREATED_INDEX}"
  fi
  return 0
}

_restore_dirs() {
  local file="${1}" old_home="${2}" line tab=$'\t'
  while IFS= read -r line; do
    [[ "${line}" == pane* ]] || continue
    _read_fields "${line}"
    printf '%s:%s%s%s\n' "${FIELDS[1]}" "${FIELDS[2]}" "${tab}" \
      "$(transform_rewrite_path "${FIELDS[5]}" "${old_home}" "${HOME}")"
  done <"${file}"
}

_wait_tick() {
  [[ -n "${PERSIST_DRY_RUN:-}" ]] || sleep 0.1
}

_await_shell() {
  local tries=0
  while (( tries < PERSIST_SHELL_WAIT_TRIES )); do
    is_shell_cmd "$(_pane_current_command "${1}")" && return 0
    tries=$(( tries + 1 ))
    _wait_tick
  done
  return 1
}

_pane_command() {
  local pc="${1}" full="${2}" ai_id="${3}" dir="${4}" vim_sessions="${5}" ai_resume="${6}" proclist="${7}"
  if [[ "${vim_sessions}" == "on" ]] && vimsession_is_editor "${pc}" && _file_exists "${dir}/$(vimsession_file)"; then
    vimsession_command "${pc}"
  elif [[ "${ai_resume}" == "on" ]] && aisession_tool "${pc}" >/dev/null; then
    aisession_command "${pc}" "${ai_id}"
  elif strategy_match "${pc}" "${proclist}"; then
    strategy_restore_command "${pc}" "${full}"
  fi
  return 0
}

_drop_placeholders() {
  local placeholders="${1}" restored="${2}" target id
  while IFS=$'\t' read -r target id; do
    [[ -n "${id}" ]] || continue
    _line_in "${restored}" "${target%:*}" || continue
    _window_alive "${id}" || continue
    _tmux kill-window -t "${id}"
  done <<<"${placeholders}"
  return 0
}

_restore_windows() {
  local file="${1}" filter="${2}" placeholders="${3}" dirs="${4:-}" line map="" restored="" tab=$'\t'
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" wn="${FIELDS[3]}"
    transform_keep_session "${s}" "${filter}" || continue
    _restore_window "${s}" "${wi}" "${wn}" "${placeholders}" "$(_lookup "${dirs}" "${s}:${wi}")"
    map="${map}${s}:${wi}${tab}${_LANDED}"$'\n'
    restored="${restored}${s}"$'\n'
  done <"${file}"
  _RESTORE_MAP="${map}"
  _drop_placeholders "${placeholders}" "${restored}"
}

_restored_target() {
  _lookup "${_RESTORE_MAP:-}" "${1}" || printf '%s' "${1}"
}

persist_restore() {
  local slot="${1:-}" filter="${2:-}" placeholders="${3:-}"
  local dir file line proclist seen=""
  dir="$(persist_save_dir)"
  file="$(slots_file "${dir}" "${slot}")"
  [[ -f "${file}" ]] || return 1
  proclist="$(persist_proclist)"
  _run_hook "$(get_tmux_option "${PERSIST_OPT_PRE_RESTORE}" "")"
  local vim_sessions ai_resume old_home=""
  vim_sessions="$(get_tmux_option "${PERSIST_OPT_VIM_SESSIONS}" "off")"
  ai_resume="$(get_tmux_option "${PERSIST_OPT_AI_RESUME}" "on")"
  [[ "$(get_tmux_option "${PERSIST_OPT_REWRITE}" "off")" == "on" ]] && old_home="$(schema_header_field "$(cat "${file}")" 3)"
  _restore_windows "${file}" "${filter}" "${placeholders}" "$(_restore_dirs "${file}" "${old_home}")"
  while IFS= read -r line; do
    [[ "${line}" == pane* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" pc="${FIELDS[6]}" rpp
    transform_keep_session "${s}" "${filter}" || continue
    rpp="$(transform_rewrite_path "${FIELDS[5]}" "${old_home}" "${HOME}")"
    local key
    key="$(_restored_target "${s}:${wi}")"
    if [[ " ${seen} " == *" ${key} "* ]]; then
      _read_dir_args "${rpp}"
      _tmux split-window -t "${key}" ${DIR_ARGS[@]+"${DIR_ARGS[@]}"}
    else
      seen="${seen} ${key}"
    fi
    local content="${FIELDS[7]:-}" cmd
    cmd="$(_pane_command "${pc}" "${FIELDS[8]:-}" "${FIELDS[9]:-}" "${rpp}" "${vim_sessions}" "${ai_resume}" "${proclist}")"
    [[ -n "${content}" || -n "${cmd}" ]] || continue
    _await_shell "${key}" || continue
    [[ -n "${content}" ]] && _repaint_pane "${key}" "${content}"
    [[ -n "${cmd}" ]] && _tmux send-keys -t "${key}" "${cmd}" Enter
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" wa="${FIELDS[4]}" wl="${FIELDS[5]}"
    transform_keep_session "${s}" "${filter}" || continue
    local wt
    wt="$(_restored_target "${s}:${wi}")"
    [[ -n "${wl}" ]] && _tmux select-layout -t "${wt}" "${wl}"
    [[ "${wa}" == "1" ]] && _tmux select-window -t "${wt}"
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == pane* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" pi="${FIELDS[3]}" pa="${FIELDS[4]}"
    transform_keep_session "${s}" "${filter}" || continue
    [[ "${pa}" == "1" ]] && _tmux select-pane -t "$(_restored_target "${s}:${wi}").${pi}"
  done <"${file}"
  while IFS= read -r line; do
    [[ "${line}" == window* ]] || continue
    _read_fields "${line}"
    local s="${FIELDS[1]}" wi="${FIELDS[2]}" wz="${FIELDS[6]:-}"
    transform_keep_session "${s}" "${filter}" || continue
    [[ "${wz}" == "1" ]] && _tmux resize-pane -Z -t "$(_restored_target "${s}:${wi}")"
  done <"${file}"
  _run_hook "$(get_tmux_option "${PERSIST_OPT_POST_RESTORE}" "")"
  return 0
}

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
