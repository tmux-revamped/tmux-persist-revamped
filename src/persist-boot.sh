#!/usr/bin/env bash

readonly PERSIST_OPT_BOOT="@persist_revamped_boot"
readonly PERSIST_OPT_BOOT_COMMAND="@persist_revamped_boot_command"
readonly PERSIST_OPT_BOOT_LABEL="@persist_revamped_boot_label"

_uname() {
  uname -s 2>/dev/null
}

_tmux_bin() {
  command -v tmux 2>/dev/null
}

_write_file() {
  local path="${1}" content="${2}"
  mkdir -p "$(dirname "${path}")" 2>/dev/null || return 1
  printf '%s' "${content}" >"${path}" 2>/dev/null
}

_agent_load() {
  local os="${1}" path="${2}" label="${3}"
  if [[ "${os}" == "Darwin" ]]; then
    launchctl unload "${path}" >/dev/null 2>&1
    launchctl load "${path}" >/dev/null 2>&1
  else
    systemctl --user daemon-reload >/dev/null 2>&1
    systemctl --user enable "${label}" >/dev/null 2>&1
  fi
  return 0
}

_agent_unload() {
  local os="${1}" path="${2}" label="${3}"
  if [[ "${os}" == "Darwin" ]]; then
    launchctl unload "${path}" >/dev/null 2>&1
  else
    systemctl --user disable "${label}" >/dev/null 2>&1
    systemctl --user daemon-reload >/dev/null 2>&1
  fi
  return 0
}

persist_boot_label() {
  local label
  label="$(get_tmux_option "${PERSIST_OPT_BOOT_LABEL}" "tmux-persist-revamped")"
  boot_label_valid "${label}" || label="tmux-persist-revamped"
  printf '%s' "${label}"
}

persist_boot_install() {
  local os home label path bin args content
  os="$(_uname)"
  home="${HOME}"
  label="$(persist_boot_label)"
  path="$(boot_agent_path "${os}" "${home}" "${label}")"
  bin="$(_tmux_bin)"
  [[ -n "${bin}" ]] || { log_error "persist_boot_install" "no tmux on PATH"; return 1; }
  args="$(get_tmux_option "${PERSIST_OPT_BOOT_COMMAND}" "new-session -d")"
  if [[ "${os}" == "Darwin" ]]; then
    content="$(boot_plist "${label}" "${bin}" "${args}")"
  else
    content="$(boot_unit "${bin}" "${args}")"
  fi
  _write_file "${path}" "${content}" || { log_error "persist_boot_install" "could not write ${path}"; return 1; }
  _agent_load "${os}" "${path}" "${label}"
  printf '%s\n' "${path}"
}

persist_boot_uninstall() {
  local os home label path
  os="$(_uname)"
  home="${HOME}"
  label="$(persist_boot_label)"
  path="$(boot_agent_path "${os}" "${home}" "${label}")"
  [[ -e "${path}" ]] || return 0
  _agent_unload "${os}" "${path}" "${label}"
  rm -f "${path}"
  printf '%s\n' "${path}"
}

persist_boot_sync() {
  if [[ "$(get_tmux_option "${PERSIST_OPT_BOOT}" "off")" == "on" ]]; then
    persist_boot_install >/dev/null
  else
    persist_boot_uninstall >/dev/null
  fi
  return 0
}
