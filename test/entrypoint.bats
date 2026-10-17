#!/usr/bin/env bats

setup() {
  PLUGIN_DIR="${BATS_TEST_DIRNAME}/.."
  ENTRY="${PLUGIN_DIR}/persist-revamped.tmux"
  SOCKET="/tmp/persist-entry-${BASHPID}-${RANDOM}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${HOME}" "${XDG_STATE_HOME}"
  command tmux -S "${SOCKET}" -f /dev/null new-session -d -s test 2>/dev/null
  sleep 0.1
}

teardown() {
  local worker
  worker="$(command tmux -S "${SOCKET}" show-option -gqv '@persist_revamped_worker_pid' 2>/dev/null)"
  [[ -n "${worker}" ]] && kill "${worker}" 2>/dev/null
  command tmux -S "${SOCKET}" kill-server 2>/dev/null || true
  rm -f "${SOCKET}" 2>/dev/null || true
}

process_running() {
  local state
  state="$(ps -o stat= -p "${1}" 2>/dev/null)"
  [[ -n "${state}" && "${state}" != Z* ]]
}

run_entry() {
  local quoted
  printf -v quoted '%q' "${ENTRY}"
  command tmux -S "${SOCKET}" run-shell "bash ${quoted}"
}

@test "entry point - returns instead of waiting on the auto-save worker" {
  local start end
  start="$(date +%s)"
  run bash -c '
    tmux() { command tmux -S "'"${SOCKET}"'" "$@"; }
    export -f tmux
    out=$(bash "'"${ENTRY}"'" 2>&1)
    printf "returned\n"
  '
  end="$(date +%s)"

  [[ "${output}" == *"returned"* ]]
  (( end - start < 30 ))
}

@test "entry point - the worker holds none of the entry point's descriptors" {
  command -v lsof >/dev/null || skip "lsof is not installed"
  run_entry
  sleep 0.3
  local worker
  worker="$(command tmux -S "${SOCKET}" show-option -gqv '@persist_revamped_worker_pid' 2>/dev/null)"

  [[ -n "${worker}" ]]
  run bash -c "lsof -p ${worker} 2>/dev/null | awk '\$4 ~ /^[012][ur]?\$/ {print \$9}' | sort -u"

  [[ "${output}" != *"pipe"* ]]
}

@test "entry point - records the worker pid it started" {
  run_entry
  sleep 0.3

  run command tmux -S "${SOCKET}" show-option -gqv '@persist_revamped_worker_pid'

  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "entry point - starts no worker when auto-save is off" {
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_interval' '0'

  run_entry
  sleep 0.3

  run command tmux -S "${SOCKET}" show-option -gqv '@persist_revamped_worker_pid'

  [[ -z "${output}" ]]
}

@test "entry point - still binds the save and restore keys with auto-save off" {
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_interval' '0'

  run_entry

  run command tmux -S "${SOCKET}" list-keys -T prefix
  [[ "${output}" == *"persist.sh' save"* ]]
  [[ "${output}" == *"persist.sh' restore"* ]]
}

@test "entry point - the worker exits when its server dies and leaves the socket file" {
  run bash -c '
    tmux() { command tmux -S "'"${SOCKET}"'" "$@"; }
    export -f tmux
    PERSIST_WORKER_SLEEP=1 bash "'"${ENTRY}"'" >/dev/null 2>&1
  '
  local worker server
  worker="$(command tmux -S "${SOCKET}" show-option -gqv '@persist_revamped_worker_pid')"
  server="$(command tmux -S "${SOCKET}" display-message -p '#{pid}')"

  kill -9 "${server}"

  [[ -S "${SOCKET}" ]]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    process_running "${worker}" || break
    sleep 0.5
  done
  ! process_running "${worker}"
}

@test "entry point - the server it drives never sees the developer's home" {
  # Arrange
  local expected="HOME=${BATS_TEST_TMPDIR}/home"

  # Act
  run command tmux -S "${SOCKET}" show-environment -g HOME

  # Assert
  [[ "${output}" == "${expected}" ]]
}

@test "entry point - event saves keep a hook the user already set" {
  # Arrange
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_event_debounce' '5'
  command tmux -S "${SOCKET}" set-hook -g session-closed 'set-option -gq @user_hook_ran 1'

  # Act
  run_entry

  # Assert
  run command tmux -S "${SOCKET}" show-hooks -g session-closed
  [[ "${output}" == *"@user_hook_ran"* ]] || false
  [[ "${output}" == *"persist.sh' event"* ]]
}

@test "entry point - a second load adds no second event hook" {
  # Arrange
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_event_debounce' '5'
  run_entry

  # Act
  run_entry

  # Assert
  [ "$(command tmux -S "${SOCKET}" show-hooks -g window-unlinked | grep -c "persist.sh")" -eq 1 ]
}

@test "entry point - turning event saves off removes only the plugin's hook" {
  # Arrange
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_event_debounce' '5'
  command tmux -S "${SOCKET}" set-hook -g session-closed 'set-option -gq @user_hook_ran 1'
  run_entry
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_event_debounce' '0'

  # Act
  run_entry

  # Assert
  run command tmux -S "${SOCKET}" show-hooks -g session-closed
  [[ "${output}" == *"@user_hook_ran"* ]] || false
  [[ "${output}" != *"persist.sh"* ]]
}

@test "entry point - a worker the pid option no longer names exits" {
  # Arrange
  run bash -c '
    tmux() { command tmux -S "'"${SOCKET}"'" "$@"; }
    export -f tmux
    PERSIST_WORKER_SLEEP=1 bash "'"${ENTRY}"'" >/dev/null 2>&1
  '
  local worker
  worker="$(command tmux -S "${SOCKET}" show-option -gqv '@persist_revamped_worker_pid')"
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_worker_pid' '999999'

  # Act
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    process_running "${worker}" || break
    sleep 0.5
  done

  # Assert
  run process_running "${worker}"
  [ "${status}" -ne 0 ]
}
