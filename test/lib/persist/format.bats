#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_FORMAT_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/format.sh"
  TAB=$'\t'
  NL=$'\n'
}

teardown() {
  cleanup_test_environment
}

# Read persist_split's per-line escaped fields, unescaping each, into SPLIT.
collect() {
  SPLIT=()
  local f
  while IFS= read -r f; do
    SPLIT+=("$(persist_unescape "${f}")")
  done
}

@test "format - escape/unescape round-trips plain values" {
  for v in "hello" "/path/to/dir" "vim file.txt"; do
    [[ "$(persist_unescape "$(persist_escape "${v}")")" == "${v}" ]]
  done
}

@test "format - a tab inside a value is escaped and restored" {
  local v="a${TAB}b"
  [[ "$(persist_escape "${v}")" == 'a\tb' ]]
  [[ "$(persist_unescape "$(persist_escape "${v}")")" == "${v}" ]]
}

@test "format - a backslash is escaped and a literal backslash-t is not a tab" {
  [[ "$(persist_escape 'back\slash')" == 'back\\slash' ]]
  [[ "$(persist_unescape "$(persist_escape 'back\slash')")" == 'back\slash' ]]
  [[ "$(persist_unescape "$(persist_escape 'x\ty')")" == 'x\ty' ]]
}

@test "format - a newline inside a value keeps a record on one line" {
  local v="line1${NL}line2"
  [[ "$(persist_escape "${v}")" == 'line1\nline2' ]]
  [[ "$(persist_unescape "$(persist_escape "${v}")")" == "${v}" ]]
}

@test "format - join then split round-trips empty, tab, backslash, newline, spaces" {
  local line
  line="$(persist_join "a" "" "b${TAB}tab" 'c\d' "e${NL}f" "with spaces")"
  collect < <(persist_split "${line}")
  [[ "${#SPLIT[@]}" == "6" ]]
  [[ "${SPLIT[0]}" == "a" ]]
  [[ "${SPLIT[1]}" == "" ]]
  [[ "${SPLIT[2]}" == "b${TAB}tab" ]]
  [[ "${SPLIT[3]}" == 'c\d' ]]
  [[ "${SPLIT[4]}" == "e${NL}f" ]]
  [[ "${SPLIT[5]}" == "with spaces" ]]
}

@test "format - an empty title field does not corrupt neighboring fields" {
  local line
  line="$(persist_join "left" "" "right")"
  collect < <(persist_split "${line}")
  [[ "${#SPLIT[@]}" == "3" ]]
  [[ "${SPLIT[0]}" == "left" ]]
  [[ "${SPLIT[1]}" == "" ]]
  [[ "${SPLIT[2]}" == "right" ]]
}

@test "format - a trailing empty field is preserved" {
  local line
  line="$(persist_join "a" "b" "")"
  collect < <(persist_split "${line}")
  [[ "${#SPLIT[@]}" == "3" ]]
  [[ "${SPLIT[2]}" == "" ]]
}

@test "format - unicode survives a round-trip" {
  local v="café ação número"
  [[ "$(persist_unescape "$(persist_escape "${v}")")" == "${v}" ]]
}

@test "format - strip_trailing_blanks drops trailing blank lines only" {
  local out
  out="$(persist_strip_trailing_blanks "$(printf 'one\ntwo\n\n  \n\t\n')")"
  [[ "${out}" == "$(printf 'one\ntwo')" ]]
}

@test "format - strip_trailing_blanks keeps interior blank lines" {
  local out
  out="$(persist_strip_trailing_blanks "$(printf 'a\n\nb\n')")"
  [[ "${out}" == "$(printf 'a\n\nb')" ]]
}

@test "format - strip_trailing_blanks is empty for all-blank input" {
  [[ -z "$(persist_strip_trailing_blanks "$(printf '\n  \n\n')")" ]]
}
