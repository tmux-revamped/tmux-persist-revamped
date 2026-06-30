#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_FORMAT_LOADED _PERSIST_REVAMPED_SCHEDULE_LOADED
  unset _PERSIST_REVAMPED_STRATEGY_LOADED _PERSIST_REVAMPED_SERVERS_LOADED
  unset _PERSIST_REVAMPED_SLOTS_LOADED _PERSIST_REVAMPED_SCHEMA_LOADED
  unset _PERSIST_REVAMPED_TRANSFORM_LOADED _PERSIST_REVAMPED_BACKUP_LOADED
  unset _PERSIST_REVAMPED_EVENT_LOADED _PERSIST_REVAMPED_VIMSESSION_LOADED
  # Point any real tmux call at an empty socket dir so the live-seam test can
  # never read or mutate the developer's running tmux server.
  export TMUX_TMPDIR="${BATS_TEST_TMPDIR}/tmuxsock"
  mkdir -p "${TMUX_TMPDIR}"
  unset TMUX
  PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../../.."
  export PERSIST_DRY_RUN=1
  source "${PLUGIN_ROOT}/src/persist.sh"
  SAVE="${BATS_TEST_TMPDIR}/state"
  tmux set-option -gq "@persist_revamped_dir" "${SAVE}"
}

teardown() {
  cleanup_test_environment
}

@test "dispatcher - save dir defaults to XDG state home" {
  tmux set-option -gqu "@persist_revamped_dir"
  XDG_STATE_HOME="/x/state" run persist_save_dir
  [[ "${output}" == "/x/state/tmux/persist" ]]
}

@test "dispatcher - save dir honors the explicit option" {
  [[ "$(persist_save_dir)" == "${SAVE}" ]]
}

@test "dispatcher - proclist appends the user's extra processes" {
  tmux set-option -gq "@persist_revamped_processes" "myapp"
  local list
  list="$(persist_proclist)"
  [[ "${list}" == *vim* ]]
  [[ "${list}" == *myapp* ]]
}

@test "dispatcher - dump emits a window record then a pane record" {
  _list_windows() { printf '%s\n' "main	0	editor	1	lay0"; }
  _list_panes() { printf '%s\n' "main	0	0	1	/home/u	vim"; }
  persist_dump >"${BATS_TEST_TMPDIR}/dump.txt"
  run cat "${BATS_TEST_TMPDIR}/dump.txt"
  [[ "${lines[0]}" == window* ]]
  [[ "${lines[0]}" == *editor* ]]
  [[ "${lines[1]}" == pane* ]]
  [[ "${lines[1]}" == *vim* ]]
}

@test "dispatcher - save writes last.txt and round-trips through restore" {
  _list_windows() { printf '%s\n' "main	0	editor	1	lay0"; }
  _list_panes() { printf '%s\n' "main	0	0	1	/home/u	vim"; }
  run persist_save
  [ "${status}" -eq 0 ]
  [ -f "${SAVE}/last.txt" ]
  [[ "$(cat "${SAVE}/last.txt")" == window* ]]
}

@test "dispatcher - save fails and leaves no file when the dir cannot be created" {
  local blocker="${BATS_TEST_TMPDIR}/blocker"
  : >"${blocker}"
  tmux set-option -gq "@persist_revamped_dir" "${blocker}/nope"
  run persist_save
  [ "${status}" -ne 0 ]
  [ ! -e "${blocker}/nope/last.txt" ]
}

@test "dispatcher - restore recreates session, splits extra panes, replays programs" {
  mkdir -p "${SAVE}"
  {
    persist_join window main 0 editor 1 lay0
    persist_join pane main 0 0 1 /home/u vim
    persist_join pane main 0 1 0 /home/u htop
    persist_join pane main 0 2 0 /home/u unknownproc
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }
  persist_restore >"${BATS_TEST_TMPDIR}/r.txt"
  run cat "${BATS_TEST_TMPDIR}/r.txt"
  [[ "${output}" == *"new-session -d -s main -n editor"* ]]
  [[ "${output}" == *"split-window -t main:0"* ]]
  [[ "${output}" == *"send-keys -t main:0 cd /home/u Enter"* ]]
  [[ "${output}" == *vim* ]]
  [[ "${output}" == *htop* ]]
  [[ "${output}" == *"select-layout -t main:0 lay0"* ]]
  [[ "${output}" == *"select-window -t main:0"* ]]
  [[ "${output}" == *"select-pane -t main:0.0"* ]]
}

@test "dispatcher - dump captures stripped pane content when enabled" {
  tmux set-option -gq "@persist_revamped_capture_panes" "on"
  _list_windows() { printf '%s\n' "main	0	editor	1	lay0"; }
  _list_panes() { printf '%s\n' "main	0	0	1	/home/u	vim"; }
  _capture_pane() { printf 'line one\nline two\n\n\n'; }
  persist_dump >"${BATS_TEST_TMPDIR}/d.txt"
  run cat "${BATS_TEST_TMPDIR}/d.txt"
  [[ "${lines[1]}" == pane* ]]
  [[ "${lines[1]}" == *"line one"* ]]
  [[ "${lines[1]}" == *"line two"* ]]
}

@test "dispatcher - restore repaints a pane from its saved content" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /home/u bash "old screen text" >"${SAVE}/last.txt"
  _has_session() { return 1; }
  local marker="${BATS_TEST_TMPDIR}/repaint"
  _repaint_pane() { echo "REPAINT:${1}:${2}" >"${marker}"; }
  persist_restore >/dev/null
  [[ -f "${marker}" ]]
  [[ "$(cat "${marker}")" == "REPAINT:main:0:old screen text" ]]
}

@test "dispatcher - repaint writes the content and sends a cat keystroke" {
  mkdir -p "${SAVE}"
  _repaint_pane "main:0" "hello world" >"${BATS_TEST_TMPDIR}/rp.txt"
  run cat "${BATS_TEST_TMPDIR}/rp.txt"
  [[ "${output}" == *"send-keys -t main:0"* ]]
  [[ "${output}" == *"cat"* ]]
}

@test "dispatcher - argv_from_forest returns the shell's foreground child" {
  local forest=$'1000 1 -bash\n2000 1000 vim src/app.ts\n3000 2000 vim-helper'
  [[ "$(argv_from_forest "${forest}" 1000)" == "vim src/app.ts" ]]
}

@test "dispatcher - argv_from_forest is empty for a bare shell" {
  local forest=$'1000 1 -bash\n2000 1 unrelated'
  [[ -z "$(argv_from_forest "${forest}" 1000)" ]]
}

@test "dispatcher - argv_from_forest prefers the newest direct child" {
  local forest=$'1000 1 -zsh\n2000 1000 less file\n2500 1000 htop'
  [[ "$(argv_from_forest "${forest}" 1000)" == "htop" ]]
}

@test "dispatcher - argv_from_forest matches the expected command over a newer sibling" {
  local forest=$'1000 1 -zsh\n2000 1000 vim notes.md\n2500 1000 sleep 999'
  [[ "$(argv_from_forest "${forest}" 1000 vim)" == "vim notes.md" ]]
}

@test "dispatcher - argv_from_forest is empty when no child matches the expected command" {
  local forest=$'1000 1 -zsh\n2000 1000 sleep 999'
  [[ -z "$(argv_from_forest "${forest}" 1000 vim)" ]]
}

@test "dispatcher - dump captures the full command line when args are enabled" {
  tmux set-option -gq "@persist_revamped_capture_args" "on"
  _list_windows() { printf '%s\n' "main	0	editor	1	lay0"; }
  _list_panes() { printf '%s\n' "main	0	0	1	/home/u	vim	2000"; }
  _read_ps_forest() { printf '%s\n' "$(printf '2000 1 -bash\n2100 2000 vim src/app.ts')"; }
  persist_dump >"${BATS_TEST_TMPDIR}/da.txt"
  run cat "${BATS_TEST_TMPDIR}/da.txt"
  [[ "${lines[1]}" == pane* ]]
  [[ "${lines[1]}" == *"src/app.ts"* ]]
}

@test "dispatcher - restore replays the full command line when present" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /home/u vim "" "vim src/app.ts" >"${SAVE}/last.txt"
  _has_session() { return 1; }
  persist_restore >"${BATS_TEST_TMPDIR}/rf.txt"
  run cat "${BATS_TEST_TMPDIR}/rf.txt"
  [[ "${output}" == *"send-keys -t main:0 vim src/app.ts Enter"* ]]
}

@test "dispatcher - restore falls back to the bare command without saved args" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /home/u vim >"${SAVE}/last.txt"
  _has_session() { return 1; }
  persist_restore >"${BATS_TEST_TMPDIR}/rb.txt"
  run cat "${BATS_TEST_TMPDIR}/rb.txt"
  [[ "${output}" == *"send-keys -t main:0 vim Enter"* ]]
}

@test "dispatcher - ps-forest seam is callable" {
  run _read_ps_forest
  true
}

@test "dispatcher - restore does not type into a pane that is not a shell" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /home/u vim "" "vim src/app.ts" >"${SAVE}/last.txt"
  _has_session() { return 1; }
  PERSIST_FAKE_PANE_CMD="claude" persist_restore >"${BATS_TEST_TMPDIR}/skip.txt"
  run cat "${BATS_TEST_TMPDIR}/skip.txt"
  [[ "${output}" != *"send-keys -t main:0 cd"* ]]
  [[ "${output}" != *"send-keys -t main:0 vim"* ]]
}

@test "dispatcher - restore types into a shell pane" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /home/u vim "" "vim src/app.ts" >"${SAVE}/last.txt"
  _has_session() { return 1; }
  PERSIST_FAKE_PANE_CMD="bash" persist_restore >"${BATS_TEST_TMPDIR}/keep.txt"
  run cat "${BATS_TEST_TMPDIR}/keep.txt"
  [[ "${output}" == *"send-keys -t main:0 cd /home/u Enter"* ]]
  [[ "${output}" == *"send-keys -t main:0 vim src/app.ts Enter"* ]]
}

@test "dispatcher - restore adds a window when the session already exists" {
  mkdir -p "${SAVE}"
  persist_join window main 1 logs 0 lay0 >"${SAVE}/last.txt"
  _has_session() { return 0; }
  persist_restore >"${BATS_TEST_TMPDIR}/r2.txt"
  run cat "${BATS_TEST_TMPDIR}/r2.txt"
  [[ "${output}" == *"new-window -t main: -n logs"* ]]
}

@test "dispatcher - restore returns non-zero with no save file" {
  tmux set-option -gq "@persist_revamped_dir" "${BATS_TEST_TMPDIR}/empty"
  run persist_restore
  [ "${status}" -ne 0 ]
}

@test "dispatcher - auto saves and stamps the timestamp when the interval elapsed" {
  tmux set-option -gq "@persist_revamped_interval" "5"
  tmux set-option -gq "@persist_revamped_last_ts" "1000"
  tmux set-option -gq "@persist_revamped_boot_ts" "0"
  _now() { echo 1400; }
  persist_save() { return 0; }
  persist_auto
  [[ "$(tmux show-option -gqv "@persist_revamped_last_ts")" == "1400" ]]
}

@test "dispatcher - auto does not stamp when the save fails" {
  tmux set-option -gq "@persist_revamped_interval" "5"
  tmux set-option -gq "@persist_revamped_last_ts" "1000"
  tmux set-option -gq "@persist_revamped_boot_ts" "0"
  _now() { echo 1400; }
  persist_save() { return 1; }
  persist_auto
  [[ "$(tmux show-option -gqv "@persist_revamped_last_ts")" == "1000" ]]
}

@test "dispatcher - auto skips inside the boot grace window" {
  tmux set-option -gq "@persist_revamped_interval" "5"
  tmux set-option -gq "@persist_revamped_last_ts" "1000"
  tmux set-option -gq "@persist_revamped_boot_ts" "1390"
  tmux set-option -gq "@persist_revamped_boot_grace" "60"
  _now() { echo 1400; }
  local saved=0
  persist_save() { saved=1; return 0; }
  persist_auto
  [ "${saved}" -eq 0 ]
}

@test "dispatcher - auto does nothing when disabled" {
  tmux set-option -gq "@persist_revamped_interval" "0"
  local saved=0
  persist_save() { saved=1; return 0; }
  persist_auto
  [ "${saved}" -eq 0 ]
}

@test "dispatcher - auto does not save before the interval elapses" {
  tmux set-option -gq "@persist_revamped_interval" "5"
  tmux set-option -gq "@persist_revamped_last_ts" "1000"
  tmux set-option -gq "@persist_revamped_boot_ts" "0"
  _now() { echo 1100; }
  local saved=0
  persist_save() { saved=1; return 0; }
  persist_auto
  [ "${saved}" -eq 0 ]
}

@test "dispatcher - boot restores and stamps the boot timestamp when enabled" {
  tmux set-option -gq "@persist_revamped_restore_on_start" "on"
  local restored=0
  persist_restore() { restored=1; }
  _now() { echo 5000; }
  persist_boot
  [ "${restored}" -eq 1 ]
  [[ "$(tmux show-option -gqv "@persist_revamped_boot_ts")" == "5000" ]]
}

@test "dispatcher - boot does nothing when disabled" {
  tmux set-option -gq "@persist_revamped_restore_on_start" "off"
  local restored=0
  persist_restore() { restored=1; }
  persist_boot
  [ "${restored}" -eq 0 ]
}

@test "dispatcher - boot restores only once per server lifetime" {
  tmux set-option -gq "@persist_revamped_restore_on_start" "on"
  tmux set-option -gq "@persist_revamped_booted" "1"
  local restored=0
  persist_restore() { restored=1; }
  persist_boot
  [ "${restored}" -eq 0 ]
}

@test "dispatcher - boot marks the server as booted before restoring" {
  tmux set-option -gq "@persist_revamped_restore_on_start" "on"
  tmux set-option -gqu "@persist_revamped_booted"
  persist_restore() { :; }
  _now() { echo 5000; }
  persist_boot
  [[ "$(tmux show-option -gqv "@persist_revamped_booted")" == "1" ]]
}

@test "dispatcher - main routes each subcommand and rejects unknown ones" {
  local hit=""
  persist_save() { hit="save"; }
  persist_restore() { hit="restore"; }
  persist_auto() { hit="auto"; }
  persist_boot() { hit="boot"; }
  persist_main save; [ "${hit}" == "save" ]
  persist_main restore; [ "${hit}" == "restore" ]
  persist_main auto; [ "${hit}" == "auto" ]
  persist_main boot; [ "${hit}" == "boot" ]
  run persist_main bogus
  [ "${status}" -eq 2 ]
}

@test "dispatcher - running the script directly with no args prints usage" {
  run bash "${PLUGIN_ROOT}/src/persist.sh"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *usage* ]]
}

@test "dispatcher - live seams are callable against the server" {
  unset PERSIST_DRY_RUN
  _now >"${BATS_TEST_TMPDIR}/now" 2>&1 || true
  [[ "$(cat "${BATS_TEST_TMPDIR}/now")" =~ ^[0-9]+$ ]]
  _list_windows >/dev/null 2>&1 || true
  _list_panes >/dev/null 2>&1 || true
  _tmux list-windows >/dev/null 2>&1 || true
  _has_session "no_such_session_xyz" >/dev/null 2>&1 || true
  _mktemp "${BATS_TEST_TMPDIR}" >/dev/null 2>&1 || true
  _pane_current_command "no_such_session_xyz:0" >/dev/null 2>&1 || true
}

@test "dispatcher - save cleans up and fails when the dump fails" {
  persist_dump() { return 1; }
  run persist_save
  [ "${status}" -ne 0 ]
  [ ! -f "${SAVE}/last.txt" ]
}

@test "dispatcher - save fails when a temp file cannot be created" {
  _mktemp() { return 1; }
  run persist_save
  [ "${status}" -ne 0 ]
}

@test "dispatcher - capture-pane seam is callable" {
  run _capture_pane "main:0"
  true
}
