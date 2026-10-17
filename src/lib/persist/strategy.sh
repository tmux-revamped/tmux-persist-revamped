#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_STRATEGY_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_STRATEGY_LOADED=1

strategy_default_list() {
  printf '%s' "vi vim nvim emacs nano man less more tail top htop btop watch ssh mosh irssi weechat mutt claude codex"
}

strategy_match() {
  local cmd="${1}" list="${2}" entry
  local -a entries
  [[ -z "${cmd}" ]] && return 1
  read -ra entries <<< "${list}"
  for entry in "${entries[@]}"; do
    # shellcheck disable=SC2053
    [[ "${cmd}" == ${entry} ]] && return 0
  done
  return 1
}

strategy_replay_safe() {
  local newline=$'\n'
  case "${1}" in
    *"${newline}"* | *[\;\|\&\$\`\<\>\(\)\\\'\"\!]*) return 1 ;;
  esac
  return 0
}

strategy_restore_command() {
  local cmd="${1}" full="${2:-}"
  if [[ -n "${full}" ]] && strategy_replay_safe "${full}"; then
    printf '%s' "${full}"
  else
    printf '%s' "${cmd}"
  fi
}

is_shell_cmd() {
  case "${1}" in
    bash | -bash | zsh | -zsh | fish | -fish | sh | -sh | dash | -dash | ksh | -ksh | tcsh | -tcsh | csh | -csh | ash | -ash) return 0 ;;
    *) return 1 ;;
  esac
}

export -f strategy_default_list
export -f strategy_match
export -f strategy_replay_safe
export -f strategy_restore_command
export -f is_shell_cmd
