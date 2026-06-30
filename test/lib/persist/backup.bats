#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_BACKUP_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/backup.sh"
}

teardown() {
  cleanup_test_environment
}

@test "backup - name embeds the timestamp" {
  [[ "$(backup_name 1700000000)" == "last-1700000000.txt" ]]
}

@test "backup - prune emits the oldest beyond the keep count" {
  local listing=$'last-100.txt\nlast-300.txt\nlast-200.txt'
  run backup_prune_list "${listing}" 2
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "last-100.txt" ]]
}

@test "backup - prune emits nothing when within the keep count" {
  local listing=$'last-100.txt\nlast-200.txt'
  run backup_prune_list "${listing}" 5
  [ "${#lines[@]}" -eq 0 ]
}

@test "backup - prune with zero keep deletes everything" {
  local listing=$'last-100.txt\nlast-200.txt'
  run backup_prune_list "${listing}" 0
  [ "${#lines[@]}" -eq 2 ]
}

@test "backup - prune handles an empty listing" {
  run backup_prune_list "" 3
  [ "${#lines[@]}" -eq 0 ]
}

@test "backup - prune ignores blank lines and clamps a negative keep" {
  local listing=$'last-100.txt\n\nlast-200.txt\n'
  run backup_prune_list "${listing}" -1
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "last-100.txt" ]]
  [[ "${lines[1]}" == "last-200.txt" ]]
}
