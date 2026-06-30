#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_SLOTS_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/slots.sh"
}

teardown() {
  cleanup_test_environment
}

@test "slots - validate accepts a normal slot name" {
  run slots_validate "work"
  [ "${status}" -eq 0 ]
}

@test "slots - validate accepts dots, dashes, and underscores" {
  run slots_validate "proj_1.dev-2"
  [ "${status}" -eq 0 ]
}

@test "slots - validate rejects an empty name" {
  run slots_validate ""
  [ "${status}" -eq 1 ]
}

@test "slots - validate rejects a leading dot" {
  run slots_validate ".hidden"
  [ "${status}" -eq 1 ]
}

@test "slots - validate rejects a slash" {
  run slots_validate "a/b"
  [ "${status}" -eq 1 ]
}

@test "slots - validate rejects a leading dash" {
  run slots_validate "-x"
  [ "${status}" -eq 1 ]
}

@test "slots - file resolves the default slot to last.txt" {
  [[ "$(slots_file "/d" "")" == "/d/last.txt" ]]
}

@test "slots - file resolves a named slot under slots/" {
  [[ "$(slots_file "/d" "work")" == "/d/slots/work.txt" ]]
}

@test "slots - parse listing returns slot names without the suffix" {
  local listing=$'work.txt\nscratch.txt'
  run slots_parse_listing "${listing}"
  [[ "${lines[0]}" == "work" ]]
  [[ "${lines[1]}" == "scratch" ]]
}

@test "slots - parse listing skips hidden temp files and non-txt entries" {
  local listing=$'.save.AB12\nwork.txt\nnotes.md\n'
  run slots_parse_listing "${listing}"
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "work" ]]
}
