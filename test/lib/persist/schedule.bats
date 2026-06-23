#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_SCHEDULE_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/schedule.sh"
}

teardown() {
  cleanup_test_environment
}

@test "schedule - autosave disabled at interval zero, enabled above" {
  run schedule_autosave_disabled 0
  [ "${status}" -eq 0 ]
  run schedule_autosave_disabled 5
  [ "${status}" -eq 1 ]
}

@test "schedule - interval elapsed at the boundary, not one second before" {
  run schedule_interval_elapsed 1000 1300 5
  [ "${status}" -eq 0 ]
  run schedule_interval_elapsed 1000 1299 5
  [ "${status}" -eq 1 ]
}

@test "schedule - boot grace active inside the window, expired past it" {
  run schedule_in_boot_grace 1000 1100 300
  [ "${status}" -eq 0 ]
  run schedule_in_boot_grace 1000 1400 300
  [ "${status}" -eq 1 ]
}

@test "schedule - no boot grace when the boot timestamp is zero" {
  run schedule_in_boot_grace 0 1100 300
  [ "${status}" -eq 1 ]
}

@test "schedule - stamp only when the save exited zero" {
  run schedule_should_stamp 0
  [ "${status}" -eq 0 ]
  run schedule_should_stamp 1
  [ "${status}" -eq 1 ]
}
