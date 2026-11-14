#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_FORMAT_LOADED _PERSIST_REVAMPED_SCHEDULE_LOADED
  unset _PERSIST_REVAMPED_STRATEGY_LOADED _PERSIST_REVAMPED_SERVERS_LOADED
  unset _PERSIST_REVAMPED_SLOTS_LOADED _PERSIST_REVAMPED_SCHEMA_LOADED
  unset _PERSIST_REVAMPED_TRANSFORM_LOADED _PERSIST_REVAMPED_BACKUP_LOADED
  unset _PERSIST_REVAMPED_EVENT_LOADED _PERSIST_REVAMPED_VIMSESSION_LOADED
  unset _PERSIST_REVAMPED_AISESSION_LOADED
  export TMUX_TMPDIR="${BATS_TEST_TMPDIR}/tmuxsock"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/xdgstate"
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/claude"
  mkdir -p "${TMUX_TMPDIR}" "${HOME}" "${XDG_STATE_HOME}" "${CLAUDE_CONFIG_DIR}/sessions"
  unset TMUX
  PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../../.."
  export PERSIST_DRY_RUN=1
  source "${PLUGIN_ROOT}/src/persist.sh"
  SAVE="${BATS_TEST_TMPDIR}/state"
  OUT="${BATS_TEST_TMPDIR}/out.txt"
  mkdir -p "${SAVE}"
  tmux set-option -gq "@persist_revamped_dir" "${SAVE}"
}

teardown() {
  cleanup_test_environment
}

pane_row() {
  local f="${PERSIST_FIELD_SEP}"
  printf '%s\n' "main${f}${1}${f}${2}${f}1${f}${3}${f}${4}${f}${5}"
}

@test "ai - dump records the claude session id of the pane's process" {
  # Arrange
  _list_windows() { :; }
  _list_panes() { pane_row 1 1 /p/proj claude 500; }
  _read_ps_forest() { printf '  500     1 -zsh\n  501   500 claude --model opus\n'; }
  printf '{"pid":501,"sessionId":"00000000-0000-4000-8000-000000000001"}\n' \
    >"${CLAUDE_CONFIG_DIR}/sessions/501.json"

  # Act
  persist_dump >"${OUT}"

  # Assert
  [ "$(head -n 1 "${OUT}")" = "$(persist_join pane main 1 1 1 /p/proj claude "" "" 00000000-0000-4000-8000-000000000001)" ]
}

@test "ai - dump uses the pane pid when claude is the pane's own process" {
  # Arrange
  _list_windows() { :; }
  _list_panes() { pane_row 1 1 /p/proj claude 700; }
  _read_ps_forest() { printf '  700     1 claude\n'; }
  printf '{"pid":700,"sessionId":"aaaa-bbbb"}\n' >"${CLAUDE_CONFIG_DIR}/sessions/700.json"

  # Act
  persist_dump >"${OUT}"

  # Assert
  [ "$(head -n 1 "${OUT}")" = "$(persist_join pane main 1 1 1 /p/proj claude "" "" aaaa-bbbb)" ]
}

@test "ai - dump names a node AI tool after its script" {
  # Arrange
  tmux set-option -gq "@persist_revamped_capture_args" "on"
  _list_windows() { :; }
  _list_panes() { pane_row 2 1 /p/web node 600; }
  _read_ps_forest() { printf '  600     1 -zsh\n  601   600 node /opt/homebrew/bin/gemini\n'; }

  # Act
  persist_dump >"${OUT}"

  # Assert
  [ "$(head -n 1 "${OUT}")" = "$(persist_join pane main 2 1 1 /p/web gemini "" "node /opt/homebrew/bin/gemini")" ]
}

@test "ai - dump with ai resume off keeps the raw command and reads no process list" {
  # Arrange
  tmux set-option -gq "@persist_revamped_ai_resume" "off"
  _list_windows() { :; }
  _list_panes() { pane_row 1 1 /p/proj claude 500; }
  _read_ps_forest() { printf 'called\n' >"${BATS_TEST_TMPDIR}/forest-read"; }

  # Act
  persist_dump >"${OUT}"

  # Assert
  [ "$(head -n 1 "${OUT}")" = "$(persist_join pane main 1 1 1 /p/proj claude "" "")" ]
  [ ! -e "${BATS_TEST_TMPDIR}/forest-read" ]
}

@test "ai - restore resumes the exact claude session" {
  # Arrange
  {
    persist_join window main 1 alpha 1 lay1
    persist_join pane main 1 1 1 /p/proj claude "" "claude" 00000000-0000-4000-8000-000000000001
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }

  # Act
  persist_restore >"${OUT}"

  # Assert
  [[ "$(cat "${OUT}")" == *"send-keys -t main:1 claude --resume 00000000-0000-4000-8000-000000000001 Enter"* ]]
}

@test "ai - restore continues the latest claude session of a save without an id" {
  # Arrange
  {
    persist_join window main 2 beta 1 lay2
    persist_join pane main 2 1 1 /p/web claude "" "claude --resume"
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }

  # Act
  persist_restore >"${OUT}"

  # Assert
  [[ "$(cat "${OUT}")" == *"send-keys -t main:2 claude --continue Enter"* ]]
  [[ "$(cat "${OUT}")" != *"claude --resume Enter"* ]]
}

@test "ai - restore with ai resume off replays the program as before" {
  # Arrange
  tmux set-option -gq "@persist_revamped_ai_resume" "off"
  {
    persist_join window main 1 alpha 1 lay1
    persist_join pane main 1 1 1 /p/proj claude "" "" abc-1
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }

  # Act
  persist_restore >"${OUT}"

  # Assert
  [[ "$(cat "${OUT}")" == *"send-keys -t main:1 claude Enter"* ]]
  [[ "$(cat "${OUT}")" != *"--resume"* ]]
}

@test "restore - opens every window and split in its own saved directory" {
  # Arrange
  {
    persist_join window main 1 alpha 1 lay1
    persist_join window main 2 beta 0 lay2
    persist_join window main 3 "gamma docs" 0 lay3
    persist_join pane main 1 1 0 "/w/my projects/app" claude
    persist_join pane main 1 2 0 "/w/my projects" claude
    persist_join pane main 1 3 1 "/w/my projects/lib" claude
    persist_join pane main 2 1 1 /w/beta/api claude
    persist_join pane main 2 2 0 /w/beta/web claude
    persist_join pane main 3 1 1 "/w/gamma docs" claude
  } >"${SAVE}/last.txt"
  _has_session() { [[ "${1}" == "main" && -e "${BATS_TEST_TMPDIR}/made" ]]; }
  _window_taken() { return 1; }
  _tmux_created() { printf '%s|' "$@" >>"${OUT}"; printf '\n' >>"${OUT}"; : >"${BATS_TEST_TMPDIR}/made"; _CREATED_INDEX="1"; }
  _tmux() { printf '%s|' "$@" >>"${OUT}"; printf '\n' >>"${OUT}"; }

  # Act
  persist_restore

  # Assert
  run grep -E '^(new-session|new-window|split-window)\|' "${OUT}"
  [ "${output}" = "new-session|-d|-s|main|-n|alpha|-c|/w/my projects/app|
new-window|-t|main:2|-n|beta|-c|/w/beta/api|
new-window|-t|main:3|-n|gamma docs|-c|/w/gamma docs|
split-window|-t|main:1|-c|/w/my projects|
split-window|-t|main:1|-c|/w/my projects/lib|
split-window|-t|main:2|-c|/w/beta/web|" ]
}

@test "restore - waits for the new pane's shell before typing into it" {
  # Arrange
  {
    persist_join window main 1 alpha 1 lay1
    persist_join pane main 1 1 1 /p/proj claude "" "" abc-1
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }
  printf '0' >"${BATS_TEST_TMPDIR}/polls"
  _pane_current_command() {
    local n
    n=$(( $(cat "${BATS_TEST_TMPDIR}/polls") + 1 ))
    printf '%s' "${n}" >"${BATS_TEST_TMPDIR}/polls"
    if (( n < 3 )); then printf 'tmux'; else printf 'zsh'; fi
  }

  # Act
  persist_restore >"${OUT}"

  # Assert
  [ "$(cat "${BATS_TEST_TMPDIR}/polls")" = "3" ]
  [[ "$(cat "${OUT}")" == *"send-keys -t main:1 claude --resume abc-1 Enter"* ]]
}

@test "restore - types nothing into a pane whose shell never starts" {
  # Arrange
  {
    persist_join window main 1 alpha 1 lay1
    persist_join pane main 1 1 1 /p/proj claude "" "" abc-1
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }
  printf '0' >"${BATS_TEST_TMPDIR}/polls"
  _pane_current_command() {
    printf '%s' "$(( $(cat "${BATS_TEST_TMPDIR}/polls") + 1 ))" >"${BATS_TEST_TMPDIR}/polls"
    printf 'tmux'
  }

  # Act
  persist_restore >"${OUT}"

  # Assert
  [ "$(cat "${BATS_TEST_TMPDIR}/polls")" = "50" ]
  [[ "$(cat "${OUT}")" != *"send-keys"* ]]
}
