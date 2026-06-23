#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_SERVERS_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/servers.sh"
}

teardown() {
  cleanup_test_environment
}

@test "servers - counts other sockets and excludes the current one" {
  local listing
  listing="$(printf '%s\n' default work play)"
  [[ "$(servers_count_from_listing "${listing}" "default")" == "2" ]]
}

@test "servers - ignores blank lines" {
  local listing
  listing="$(printf '%s\n' default '' work)"
  [[ "$(servers_count_from_listing "${listing}" "default")" == "1" ]]
}

@test "servers - zero when only the current socket exists" {
  [[ "$(servers_count_from_listing "default" "default")" == "0" ]]
}

@test "servers - other exist is true when another server is present" {
  local listing
  listing="$(printf '%s\n' default work)"
  run servers_other_exist "${listing}" "default"
  [ "${status}" -eq 0 ]
}

@test "servers - other exist is false when alone" {
  run servers_other_exist "default" "default"
  [ "${status}" -eq 1 ]
}
