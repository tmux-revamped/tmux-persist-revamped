#!/usr/bin/env bats

setup() {
  PLUGIN_DIR="${BATS_TEST_DIRNAME}/.."
  ENTRY="${PLUGIN_DIR}/persist-revamped.tmux"
  SOCKET="/tmp/persist-entry-${BASHPID}-${RANDOM}"
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
