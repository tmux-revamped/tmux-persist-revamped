#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_FORMAT_LOADED _PERSIST_REVAMPED_SCHEDULE_LOADED
  unset _PERSIST_REVAMPED_STRATEGY_LOADED _PERSIST_REVAMPED_SERVERS_LOADED
  unset _PERSIST_REVAMPED_SLOTS_LOADED _PERSIST_REVAMPED_SCHEMA_LOADED
  unset _PERSIST_REVAMPED_TRANSFORM_LOADED _PERSIST_REVAMPED_BACKUP_LOADED
  unset _PERSIST_REVAMPED_EVENT_LOADED _PERSIST_REVAMPED_VIMSESSION_LOADED
  export TMUX_TMPDIR="${BATS_TEST_TMPDIR}/tmuxsock"
  mkdir -p "${TMUX_TMPDIR}"
  unset TMUX
  PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../../.."
  export PERSIST_DRY_RUN=1
  source "${PLUGIN_ROOT}/src/persist.sh"
  SAVE="${BATS_TEST_TMPDIR}/state"
  OUT="${BATS_TEST_TMPDIR}/out.txt"
  tmux set-option -gq "@persist_revamped_dir" "${SAVE}"
  mkdir -p "${SAVE}"
}

teardown() {
  cleanup_test_environment
}

write_two_window_save() {
  {
    persist_join window main 1 Personal 0 lay1
    persist_join window main 2 GamesCare 1 lay2
    persist_join pane main 1 1 1 /home/u/personal bash
    persist_join pane main 2 1 1 /home/u/games bash
  } >"${SAVE}/last.txt"
}

@test "restore - replaces the boot window at its saved index instead of appending" {
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { [[ "${2}" == "1" ]]; }
  _window_alive() { return 1; }

  persist_restore "" "" $'main:1\t@0' >"${OUT}"

  run cat "${OUT}"
  [[ "${output}" == *"new-window -k -t main:1 -n Personal"* ]]
  [[ "${output}" == *"new-window -t main:2 -n GamesCare"* ]]
  [[ "${output}" != *"new-window -t main: -n"* ]]
  [[ "${output}" == *"send-keys -t main:1 cd '/home/u/personal' Enter"* ]]
  [[ "${output}" == *"send-keys -t main:2 cd '/home/u/games' Enter"* ]]
  [[ "${output}" == *"select-window -t main:2"* ]]
  [[ "${output}" != *"kill-window"* ]]
}

@test "restore - kills a boot window left at an index the save does not use" {
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { [[ "${2}" == "0" ]]; }
  _window_alive() { [[ "${1}" == "@0" ]]; }

  persist_restore "" "" $'main:0\t@0' >"${OUT}"

  run cat "${OUT}"
  [[ "${output}" == *"new-window -t main:1 -n Personal"* ]]
  [[ "${output}" == *"kill-window -t @0"* ]]
}

@test "restore - keeps a boot window of a session the save does not hold" {
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { return 1; }
  _window_alive() { return 0; }

  persist_restore "" "" $'other:1\t@7' >"${OUT}"

  run cat "${OUT}"
  [[ "${output}" != *"kill-window"* ]]
}

@test "restore - moves a taken index to a free one and sends panes and layout there" {
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { [[ "${2}" == "1" ]]; }
  _tmux_created() { printf 'tmux %s\n' "$*"; _CREATED_INDEX="3"; }

  persist_restore >"${OUT}"

  run cat "${OUT}"
  [[ "${output}" == *"new-window -t main: -n Personal"* ]]
  [[ "${output}" == *"send-keys -t main:3 cd '/home/u/personal' Enter"* ]]
  [[ "${output}" == *"select-layout -t main:3 lay1"* ]]
  [[ "${output}" == *"select-pane -t main:3.1"* ]]
  [[ "${output}" == *"send-keys -t main:2 cd '/home/u/games' Enter"* ]]
}

@test "restore - moves a new session's first window to its saved index" {
  write_two_window_save
  _has_session() { return 1; }
  _tmux_created() { printf 'tmux %s\n' "$*"; _CREATED_INDEX="0"; }

  persist_restore >"${OUT}"

  run cat "${OUT}"
  [[ "${output}" == *"new-session -d -s main -n Personal"* ]]
  [[ "${output}" == *"move-window -s main:0 -t main:1"* ]]
  [[ "${output}" == *"send-keys -t main:1 cd '/home/u/personal' Enter"* ]]
}

@test "restore - targets the created index when moving the first window fails" {
  persist_join window main 1 Personal 1 lay1 >"${SAVE}/last.txt"
  _has_session() { return 1; }
  _tmux_created() { _CREATED_INDEX="0"; }
  _tmux() { printf 'tmux %s\n' "$*"; [[ "${1}" != "move-window" ]]; }

  persist_restore >"${OUT}"

  run cat "${OUT}"
  [[ "${output}" == *"select-layout -t main:0 lay1"* ]]
}

@test "restore - records the index tmux reports for a created window" {
  _tmux_bin_fake="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${_tmux_bin_fake}"
  printf '#!/bin/sh\necho 4\n' >"${_tmux_bin_fake}/tmux"
  chmod +x "${_tmux_bin_fake}/tmux"
  unset PERSIST_DRY_RUN

  PATH="${_tmux_bin_fake}:${PATH}" _tmux_created new-window -t main: -n x

  [[ "${_CREATED_INDEX}" == "4" ]]
}

@test "boot placeholders - lists only a lone default-shell window" {
  _list_boot_panes() {
    printf '1\t1\tmain:1\t@0\t\n'
    printf '2\t1\twork:1\t@1\t\n'
    printf '1\t2\tsplit:1\t@2\t\n'
    printf '1\t1\tedit:1\t@3\tvim notes\n'
  }

  run persist_boot_placeholders

  [ "${status}" -eq 0 ]
  [[ "${output}" == $'main:1\t@0' ]]
}

@test "boot - passes the boot placeholders to the restore" {
  tmux set-option -gq "@persist_revamped_restore_on_start" "on"
  tmux set-option -gqu "@persist_revamped_booted"
  persist_boot_placeholders() { printf 'main:1\t@0\n'; }
  local got=""
  persist_restore() { got="${3}"; }
  _now() { echo 5000; }

  persist_boot

  [[ "${got}" == $'main:1\t@0' ]]
}
