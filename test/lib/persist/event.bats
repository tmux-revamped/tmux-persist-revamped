#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_EVENT_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/event.sh"
}

teardown() {
  cleanup_test_environment
}

@test "event - disabled is true at zero and below" {
  run event_disabled 0
  [ "${status}" -eq 0 ]
  run event_disabled -3
  [ "${status}" -eq 0 ]
}

@test "event - disabled is false for a positive debounce" {
  run event_disabled 2
  [ "${status}" -eq 1 ]
}

@test "event - should_save is true past the debounce window" {
  run event_should_save 100 105 2
  [ "${status}" -eq 0 ]
}

@test "event - should_save is false inside the debounce window" {
  run event_should_save 100 101 2
  [ "${status}" -eq 1 ]
}

@test "event - should_save is true exactly at the boundary" {
  run event_should_save 100 102 2
  [ "${status}" -eq 0 ]
}
