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
  [[ -z "${PERSIST_DIR_SOCKET:-}" ]] || command tmux -S "${PERSIST_DIR_SOCKET}" kill-server 2>/dev/null || true
  [[ -z "${PERSIST_DIR_SOCKET:-}" ]] || rm -f "${PERSIST_DIR_SOCKET}"
  cleanup_test_environment
}

write_two_window_save() {
  {
    persist_join window main 1 alpha 0 lay1
    persist_join window main 2 beta 1 lay2
    persist_join pane main 1 1 1 /home/u/alpha bash
    persist_join pane main 2 1 1 /home/u/beta bash
  } >"${SAVE}/last.txt"
}

@test "restore - replaces the boot window at its saved index instead of appending" {
  # Arrange
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { [[ "${2}" == "1" ]]; }
  _window_alive() { return 1; }

  # Act
  persist_restore "" "" $'main:1\t@0' >"${OUT}"

  # Assert
  run cat "${OUT}"
  [[ "${output}" == *"new-window -k -t main:1 -n alpha -c /home/u/alpha"* ]]
  [[ "${output}" == *"new-window -t main:2 -n beta -c /home/u/beta"* ]]
  [[ "${output}" != *"new-window -t main: -n"* ]]
  [[ "${output}" != *" cd "* ]]
  [[ "${output}" == *"select-window -t main:2"* ]]
  [[ "${output}" != *"kill-window"* ]]
}

@test "restore - kills a boot window left at an index the save does not use" {
  # Arrange
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { [[ "${2}" == "0" ]]; }
  _window_alive() { [[ "${1}" == "@0" ]]; }

  # Act
  persist_restore "" "" $'main:0\t@0' >"${OUT}"

  # Assert
  run cat "${OUT}"
  [[ "${output}" == *"new-window -t main:1 -n alpha"* ]]
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
  # Arrange
  write_two_window_save
  _has_session() { return 0; }
  _window_taken() { [[ "${2}" == "1" ]]; }
  _tmux_created() { printf 'tmux %s\n' "$*"; _CREATED_INDEX="3"; }

  # Act
  persist_restore >"${OUT}"

  # Assert
  run cat "${OUT}"
  [[ "${output}" == *"new-window -t main: -n alpha -c /home/u/alpha"* ]]
  [[ "${output}" == *"select-layout -t main:3 lay1"* ]]
  [[ "${output}" == *"select-pane -t main:3.1"* ]]
  [[ "${output}" == *"new-window -t main:2 -n beta -c /home/u/beta"* ]]
}

@test "restore - moves a new session's first window to its saved index" {
  # Arrange
  write_two_window_save
  _has_session() { return 1; }
  _tmux_created() { printf 'tmux %s\n' "$*"; _CREATED_INDEX="0"; }

  # Act
  persist_restore >"${OUT}"

  # Assert
  run cat "${OUT}"
  [[ "${output}" == *"new-session -d -s main -n alpha -c /home/u/alpha"* ]]
  [[ "${output}" == *"move-window -s main:0 -t main:1"* ]]
}

@test "restore - targets the created index when moving the first window fails" {
  # Arrange
  persist_join window main 1 alpha 1 lay1 >"${SAVE}/last.txt"
  _has_session() { return 1; }
  _tmux_created() { _CREATED_INDEX="0"; }
  _tmux() { printf 'tmux %s\n' "$*"; [[ "${1}" != "move-window" ]]; }

  # Act
  persist_restore >"${OUT}"

  # Assert
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

@test "restore - a saved folder holding a hash tmux reads as a format is where the window starts" {
  # Arrange
  local folder="${BATS_TEST_TMPDIR}/it's #S dir" real now delay
  PERSIST_DIR_SOCKET="/tmp/persist-dir-${BASHPID}-${RANDOM}"
  mkdir -p "${folder}" "${BATS_TEST_TMPDIR}/home"
  real="$(cd "${folder}" && pwd -P)"
  HOME="${BATS_TEST_TMPDIR}/home" command tmux -S "${PERSIST_DIR_SOCKET}" -f /dev/null new-session -d -s base /bin/sh

  # Act
  _read_dir_args "${folder}"

  # Assert
  command tmux -S "${PERSIST_DIR_SOCKET}" new-window -d -n probe "${DIR_ARGS[@]}" /bin/sh
  for delay in 0.01 0.05 0.1 0.2 0.5 1 2; do
    now="$(command tmux -S "${PERSIST_DIR_SOCKET}" display-message -p -t probe '#{pane_current_path}')"
    [[ "${now}" == "${real}" ]] && break
    sleep "${delay}"
  done
  [[ "${now}" == "${real}" ]]
}

@test "restore - no saved folder means no start directory" {
  # Arrange
  local folder=""

  # Act
  _read_dir_args "${folder}"

  # Assert
  [[ "${#DIR_ARGS[@]}" -eq 0 ]]
}
