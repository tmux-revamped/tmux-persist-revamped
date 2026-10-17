#!/usr/bin/env bash

[[ -n "${_PERSIST_REVAMPED_VIMSESSION_LOADED:-}" ]] && return 0
_PERSIST_REVAMPED_VIMSESSION_LOADED=1

vimsession_file() {
  printf '%s' "Session.vim"
}

vimsession_is_editor() {
  case "${1}" in
    vim | nvim | vi | gvim | mvim) return 0 ;;
    *) return 1 ;;
  esac
}

vimsession_command() {
  printf '%s -S' "${1}"
}

export -f vimsession_file
export -f vimsession_is_editor
export -f vimsession_command
