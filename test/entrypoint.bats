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
  command tmux -S "${SOCKET}-host" kill-server 2>/dev/null || true
  command tmux -S "${SOCKET}" kill-server 2>/dev/null || true
  rm -f "${SOCKET}" "${SOCKET}-host" 2>/dev/null || true
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

@test "entry point - the slot picker stays unbound by default" {
  # Arrange
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_interval' '0'

  # Act
  run_entry

  # Assert
  run command tmux -S "${SOCKET}" list-keys -T prefix
  [[ "${output}" == *"persist.sh' save"* ]] || false
  [[ "${output}" != *"persist.sh' pick"* ]]
}

wait_for() {
  local delay
  for delay in 0.01 0.02 0.05 0.1 0.1 0.2 0.2 0.5 0.5 1 1 1 2 2; do
    "$@" && return 0
    sleep "${delay}"
  done
  "$@"
}

attached() {
  local clients
  clients=$(command tmux -S "${SOCKET}" list-clients -F x 2>/dev/null)
  [[ -n "${clients}" ]]
}

called_with() {
  grep -qx -- "$1" "${BATS_TEST_TMPDIR}/calls" 2>/dev/null
}

odd_checkout() {
  local copy="${BATS_TEST_TMPDIR}/it's #S dir" quoted
  mkdir -p "${copy}/src"
  cp -f "${ENTRY}" "${copy}/"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >>"%s"\n' "${BATS_TEST_TMPDIR}/calls" >"${copy}/src/persist.sh"
  printf -v quoted '%q' "${copy}/persist-revamped.tmux"
  quoted="$(printf '%s\n' "${quoted}" | sed 's/#/##/g')"
  ODD_LOAD="bash ${quoted}"
}

@test "entry point - its keys and boot calls run from a checkout path with a space, a quote and a hash" {
  # Arrange
  local host="${SOCKET}-host"
  odd_checkout
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_interval' '0'
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_pick_key' 'P'
  command tmux -S "${host}" -f /dev/null new-session -d -s host -x 120 -y 30 \
    "env -u TMUX TERM=xterm-256color tmux -S '${SOCKET}' attach-session -t test"
  wait_for attached

  # Act
  command tmux -S "${SOCKET}" run-shell "${ODD_LOAD}"

  # Assert
  wait_for called_with boot-sync
  wait_for called_with boot
  command tmux -S "${host}" send-keys -t host C-b C-s
  wait_for called_with save
  command tmux -S "${host}" send-keys -t host C-b C-r
  wait_for called_with restore
  command tmux -S "${host}" send-keys -t host C-b P
  wait_for called_with pick
}

@test "entry point - a second load from such a path adds no second event hook, and the hook runs" {
  # Arrange
  local hooks
  odd_checkout
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_interval' '0'
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_event_debounce' '5'
  command tmux -S "${SOCKET}" new-window -d -t test:
  command tmux -S "${SOCKET}" run-shell "${ODD_LOAD}"

  # Act
  command tmux -S "${SOCKET}" run-shell "${ODD_LOAD}"

  # Assert
  hooks=$(command tmux -S "${SOCKET}" show-hooks -g window-unlinked)
  run grep -c "persist.sh" <<<"${hooks}"
  [[ "${output}" == "1" ]] || false
  command tmux -S "${SOCKET}" kill-window -t test:1
  wait_for called_with event
}

real_host() {
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_interval' '0'
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_dir' "${BATS_TEST_TMPDIR}/saves"
  command tmux -S "${SOCKET}" set-option -g default-command "env PS1='$ ' sh"
  command tmux -S "${SOCKET}-host" -f /dev/null new-session -d -s host -x 120 -y 30 \
    "env -u TMUX TERM=xterm-256color tmux -S '${SOCKET}' attach-session -t test"
  wait_for attached
  run_entry
}

has_window() {
  local now
  now="$(command tmux -S "${SOCKET}" list-windows -a -F '#{window_name}' | tr '\n' ' ')"
  [[ " ${now}" == *" $1 "* ]]
}

lacks_window() {
  ! has_window "$1"
}

said() {
  local messages
  messages="$(command tmux -S "${SOCKET}" show-messages)"
  [[ "${messages}" == *"$1"* ]]
}

saved() {
  local file
  for file in "${BATS_TEST_TMPDIR}/saves"/servers/*/*; do
    [[ -f "${file}" && -s "${file}" ]] && return 0
  done
  return 1
}

@test "keys - prefix C-r with nothing saved says so in a message, not in a raw error screen" {
  # Arrange
  real_host

  # Act
  command tmux -S "${SOCKET}-host" send-keys -t host C-b
  command tmux -S "${SOCKET}-host" send-keys -t host C-r

  # Assert
  wait_for said "persist-revamped: nothing saved to restore"
  run command tmux -S "${SOCKET}" display-message -p -t test '#{pane_mode}'
  [[ "${output}" == "" ]]
}

@test "keys - prefix C-s saves every window, and prefix C-r brings back one that was closed" {
  # Arrange
  real_host
  command tmux -S "${SOCKET}" rename-window -t test:0 first
  command tmux -S "${SOCKET}" new-window -d -t test: -n second
  command tmux -S "${SOCKET}-host" send-keys -t host C-b
  command tmux -S "${SOCKET}-host" send-keys -t host C-s
  wait_for saved
  command tmux -S "${SOCKET}" kill-window -t test:second
  wait_for lacks_window second

  # Act
  command tmux -S "${SOCKET}-host" send-keys -t host C-b
  command tmux -S "${SOCKET}-host" send-keys -t host C-r

  # Assert
  wait_for has_window second
}

server_gone() {
  ! command tmux -S "${SOCKET}" list-sessions >/dev/null 2>&1
}

host_shows() {
  local screen
  screen="$(command tmux -S "${SOCKET}-host" capture-pane -p -t host)"
  [[ "${screen}" == *"$1"* ]]
}

host_lacks() {
  ! host_shows "$1"
}

@test "keys - the picker key with no slot saved says so and waits for Enter" {
  # Arrange
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_pick_key' 'P'
  real_host

  # Act
  command tmux -S "${SOCKET}-host" send-keys -t host C-b
  command tmux -S "${SOCKET}-host" send-keys -t host P

  # Assert
  wait_for host_shows "persist-revamped: no named slot is saved yet"
  command tmux -S "${SOCKET}-host" send-keys -t host Enter
  wait_for host_lacks "persist-revamped: no named slot is saved yet"
}

@test "keys - the picker key restores the slot chosen in fzf" {
  # Arrange
  local stubs="${BATS_TEST_TMPDIR}/stubs" quoted
  mkdir -p "${stubs}"
  printf '#!/bin/sh\nhead -n 1\n' >"${stubs}/fzf"
  chmod +x "${stubs}/fzf"
  command tmux -S "${SOCKET}" kill-server
  wait_for server_gone
  PATH="${stubs}:${PATH}" command tmux -S "${SOCKET}" -f /dev/null new-session -d -s test
  command tmux -S "${SOCKET}" set-option -gq '@persist_revamped_pick_key' 'P'
  real_host
  command tmux -S "${SOCKET}" rename-window -t test:0 first
  command tmux -S "${SOCKET}" new-window -d -t test: -n second
  printf -v quoted '%q' "${PLUGIN_DIR}/src/persist.sh"
  command tmux -S "${SOCKET}" run-shell "bash ${quoted} save work"
  command tmux -S "${SOCKET}" kill-window -t test:second
  wait_for lacks_window second

  # Act
  command tmux -S "${SOCKET}-host" send-keys -t host C-b
  command tmux -S "${SOCKET}-host" send-keys -t host P

  # Assert
  wait_for has_window second
}
