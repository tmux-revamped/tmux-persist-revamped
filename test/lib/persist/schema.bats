#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_SCHEMA_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/schema.sh"
}

teardown() {
  cleanup_test_environment
}

@test "schema - version constant is exported" {
  [[ -n "${PERSIST_SCHEMA_VERSION}" ]]
}

@test "schema - count_kind counts only matching records" {
  local content
  content=$(printf 'window\ta\npane\tb\npane\tc\nheader\t1\n')
  [[ "$(schema_count_kind "${content}" window)" == "1" ]]
  [[ "$(schema_count_kind "${content}" pane)" == "2" ]]
}

@test "schema - count_kind is zero when nothing matches" {
  local content
  content=$(printf 'window\ta\n')
  [[ "$(schema_count_kind "${content}" pane)" == "0" ]]
}

@test "schema - header field returns the requested column" {
  local content
  content=$(printf 'window\ta\nheader\t1\t/home/old\t1700000000\n')
  [[ "$(schema_header_field "${content}" 2)" == "1" ]]
  [[ "$(schema_header_field "${content}" 3)" == "/home/old" ]]
  [[ "$(schema_header_field "${content}" 4)" == "1700000000" ]]
}

@test "schema - header field is empty when there is no header" {
  local content
  content=$(printf 'window\ta\npane\tb\n')
  [[ -z "$(schema_header_field "${content}" 2)" ]]
}

@test "schema - stale is true past the max age" {
  run schema_stale 100 1000 500
  [ "${status}" -eq 0 ]
}

@test "schema - stale is false within the max age" {
  run schema_stale 900 1000 500
  [ "${status}" -eq 1 ]
}

@test "schema - stale check is disabled with a max of zero" {
  run schema_stale 1 100000 0
  [ "${status}" -eq 1 ]
}
