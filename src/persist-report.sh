#!/usr/bin/env bash

readonly PERSIST_OPT_STALE_SECS="@persist_revamped_stale_secs"

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
  local halt agent
  halt="$(persist_halt_file)"
  if _file_exists "${halt}"; then
    printf 'restore:      HALTED by %s\n' "${halt}"
  else
    printf 'halt file:    %s (absent)\n' "${halt}"
  fi
  agent="$(boot_agent_path "$(_uname)" "${HOME}" "$(persist_boot_label)")"
  if _file_exists "${agent}"; then
    printf 'login agent:  installed at %s\n' "${agent}"
  else
    printf 'login agent:  not installed\n'
  fi
  printf 'sensitive:    %s\n' "$(persist_sensitive_list)"
  printf 'replay list:  %s\n' "$(persist_proclist)"
  return 0
}
