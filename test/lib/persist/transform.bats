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

@test "transform - expand_path resolves a leading tilde" {
  [[ "$(transform_expand_path "~/state" /home/me box)" == "/home/me/state" ]]
  [[ "$(transform_expand_path "~" /home/me box)" == "/home/me" ]]
}

@test "transform - expand_path resolves HOME and HOSTNAME placeholders" {
  [[ "$(transform_expand_path '$HOME/state' /home/me box)" == "/home/me/state" ]]
  [[ "$(transform_expand_path '/state/$HOSTNAME' /home/me box)" == "/state/box" ]]
}

@test "transform - expand_path leaves a plain path alone" {
  [[ "$(transform_expand_path /state/persist /home/me box)" == "/state/persist" ]]
  [[ "$(transform_expand_path "/state/~notahome" /home/me box)" == "/state/~notahome" ]]
}

@test "transform - shell_quote wraps a plain path in single quotes" {
  local q="'"

  run transform_shell_quote /home/me/work

  [ "${output}" = "${q}/home/me/work${q}" ]
}

@test "transform - shell_quote keeps a path with spaces as one word" {
  local q="'"

  run transform_shell_quote "/home/me/@ Pessoal/fdstoolkit"

  [ "${output}" = "${q}/home/me/@ Pessoal/fdstoolkit${q}" ]
}

@test "transform - shell_quote escapes an embedded single quote" {
  local q="'"

  run transform_shell_quote "/home/me/it${q}s here"

  [ "${output}" = "${q}/home/me/it${q}\\${q}${q}s here${q}" ]
}

@test "transform - shell_quote neutralises glob and expansion characters" {
  local q="'"

  run transform_shell_quote '/home/me/$HOME *?[a] `x`'

  [ "${output}" = "${q}"'/home/me/$HOME *?[a] `x`'"${q}" ]
}

@test "transform - shell_quote agrees across every bash on this machine" {
  local q="'" expected shell out
  expected="${q}/x/${q}\\${q}${q}a b${q}"

  for shell in /bin/bash "$(command -v bash)"; do
    out="$("${shell}" -c "source '${BATS_TEST_DIRNAME}/../../../src/lib/persist/transform.sh'; transform_shell_quote \"/x/${q}a b\"")"
    [ "${out}" = "${expected}" ]
  done
}
