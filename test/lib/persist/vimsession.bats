#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_VIMSESSION_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/vimsession.sh"
}

teardown() {
  cleanup_test_environment
}

@test "vimsession - file is Session.vim" {
  [[ "$(vimsession_file)" == "Session.vim" ]]
}

@test "vimsession - is_editor accepts vim and neovim and friends" {
  is_editor_ok() { vimsession_is_editor "$1"; }
  is_editor_ok "vim"
  is_editor_ok "nvim"
  is_editor_ok "vi"
  is_editor_ok "gvim"
}

@test "vimsession - is_editor rejects non-editors" {
  ! vimsession_is_editor "htop"
  ! vimsession_is_editor "bash"
  ! vimsession_is_editor ""
}

@test "vimsession - command appends the session flag" {
  [[ "$(vimsession_command "nvim")" == "nvim -S" ]]
  [[ "$(vimsession_command "vim")" == "vim -S" ]]
}
