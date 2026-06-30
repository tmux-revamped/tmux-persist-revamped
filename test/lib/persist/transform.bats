#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_TRANSFORM_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/transform.sh"
}

teardown() {
  cleanup_test_environment
}

@test "transform - default sensitive list covers ssh and sudo" {
  local list
  list="$(transform_default_sensitive)"
  [[ "${list}" == *ssh* ]]
  [[ "${list}" == *sudo* ]]
}

@test "transform - rewrite swaps a leading home prefix" {
  [[ "$(transform_rewrite_path "/home/old/proj" "/home/old" "/home/new")" == "/home/new/proj" ]]
}

@test "transform - rewrite swaps an exact home match" {
  [[ "$(transform_rewrite_path "/home/old" "/home/old" "/home/new")" == "/home/new" ]]
}

@test "transform - rewrite leaves a non-boundary prefix alone" {
  [[ "$(transform_rewrite_path "/home/older/x" "/home/old" "/home/new")" == "/home/older/x" ]]
}

@test "transform - rewrite is a no-op when old is empty" {
  [[ "$(transform_rewrite_path "/a/b" "" "/home/new")" == "/a/b" ]]
}

@test "transform - rewrite is a no-op when old equals new" {
  [[ "$(transform_rewrite_path "/a/b" "/a" "/a")" == "/a/b" ]]
}

@test "transform - rewrite leaves an unrelated path alone" {
  [[ "$(transform_rewrite_path "/var/log" "/home/old" "/home/new")" == "/var/log" ]]
}

@test "transform - is_sensitive matches a command in the list" {
  run transform_is_sensitive "ssh" "ssh sudo"
  [ "${status}" -eq 0 ]
}

@test "transform - is_sensitive supports globs" {
  run transform_is_sensitive "ssh-keygen" "ssh*"
  [ "${status}" -eq 0 ]
}

@test "transform - is_sensitive rejects a safe command and the empty value" {
  run transform_is_sensitive "vim" "ssh sudo"
  [ "${status}" -eq 1 ]
  run transform_is_sensitive "" "ssh sudo"
  [ "${status}" -eq 1 ]
}

@test "transform - keep_session keeps everything with an empty filter" {
  run transform_keep_session "anything" ""
  [ "${status}" -eq 0 ]
}

@test "transform - keep_session keeps the matching session only" {
  run transform_keep_session "work" "work"
  [ "${status}" -eq 0 ]
  run transform_keep_session "other" "work"
  [ "${status}" -eq 1 ]
}
