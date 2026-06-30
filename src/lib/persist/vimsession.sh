#!/usr/bin/env bash
#
# vimsession.sh: pure decision for the Vim/Neovim session strategy. When a pane was
# running an editor and a Session.vim sits in its directory, restore reopens the
# editor with that session instead of a bare editor. The file-existence check is a
# seam in the dispatcher; the naming and the command shape live here. The replayed
# command still only ever goes into a fresh shell pane, never a running program.

[[ -n "${_PERSIST_REVAMPED_VIMSESSION_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_VIMSESSION_LOADED=1

# vimsession_file -> the session file name an editor restore looks for.
vimsession_file() {
  printf '%s' "Session.vim"
}

# vimsession_is_editor CMD -> success when CMD is an editor that understands "-S".
vimsession_is_editor() {
  case "${1}" in
    vim | nvim | vi | gvim | mvim) return 0 ;;
    *) return 1 ;;
  esac
}

# vimsession_command CMD -> the command to send to reopen CMD with its session file
# from the pane's current directory ("nvim -S" loads ./Session.vim).
vimsession_command() {
  printf '%s -S' "${1}"
}

export -f vimsession_file
export -f vimsession_is_editor
export -f vimsession_command
