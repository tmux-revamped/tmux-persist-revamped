#!/usr/bin/env bash
#
# strategy.sh: pure decision of whether and how to restore a pane's foreground
# program. Data-driven from a space-separated allow list so a new CLI is a config
# change, not a code change. Restoring only an allow-listed set is what keeps a
# restore from blindly re-running arbitrary commands.

[[ -n "${_PERSIST_REVAMPED_STRATEGY_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_STRATEGY_LOADED=1

# strategy_default_list -> the built-in restorable programs. Glob entries are
# allowed (for example "git*").
strategy_default_list() {
  printf '%s' "vi vim nvim emacs nano man less more tail top htop btop watch ssh mosh irssi weechat mutt claude codex"
}

# strategy_match CMD LIST -> success when CMD matches a word in LIST. Each word is a
# glob, so "vim*" matches "vimdiff". An empty CMD never matches.
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

# strategy_restore_command CMD FULL -> what to send on restore. FULL is the pane's
# full command line; CMD is its first word. When FULL is given it is replayed (so
# arguments such as a filename survive), otherwise the bare command.
strategy_restore_command() {
  local cmd="${1}" full="${2:-}"
  if [[ -n "${full}" ]]; then
    printf '%s' "${full}"
  else
    printf '%s' "${cmd}"
  fi
}

# is_shell_cmd CMD -> success when CMD names an interactive shell, that is, a pane
# it is safe to type into. A restore must never send keystrokes to a pane that is
# already running a program, so anything outside this set, including an empty
# value, is treated as unsafe. The leading-dash forms cover login shells.
is_shell_cmd() {
  case "${1}" in
    bash | -bash | zsh | -zsh | fish | -fish | sh | -sh | dash | -dash | ksh | -ksh | tcsh | -tcsh | csh | -csh | ash | -ash) return 0 ;;
    *) return 1 ;;
  esac
}

export -f strategy_default_list
export -f strategy_match
export -f strategy_restore_command
export -f is_shell_cmd
