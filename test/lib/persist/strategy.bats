#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_STRATEGY_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/strategy.sh"
}

teardown() {
  cleanup_test_environment
}

@test "strategy - default list covers editors, pagers, and modern CLIs" {
  local list
  list="$(strategy_default_list)"
  [[ "${list}" == *vim* ]]
  [[ "${list}" == *less* ]]
  [[ "${list}" == *ssh* ]]
  [[ "${list}" == *claude* ]]
}

@test "strategy - match finds an exact command in the default list" {
  run strategy_match "vim" "$(strategy_default_list)"
  [ "${status}" -eq 0 ]
}

@test "strategy - match supports glob entries without expanding paths" {
  run strategy_match "vimdiff" "vi vim*"
  [ "${status}" -eq 0 ]
}

@test "strategy - empty command never matches" {
  run strategy_match "" "vim ssh"
  [ "${status}" -eq 1 ]
}

@test "strategy - a command outside the list does not match" {
  run strategy_match "rm" "$(strategy_default_list)"
  [ "${status}" -eq 1 ]
}

@test "strategy - restore replays the full command line when given" {
  [[ "$(strategy_restore_command "vim" "vim /tmp/a file.txt")" == "vim /tmp/a file.txt" ]]
}

@test "strategy - restore falls back to the bare command" {
  [[ "$(strategy_restore_command "htop" "")" == "htop" ]]
}
