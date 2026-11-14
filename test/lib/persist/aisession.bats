#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_AISESSION_LOADED
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/claude"
  mkdir -p "${CLAUDE_CONFIG_DIR}/sessions"
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/aisession.sh"
}

teardown() {
  cleanup_test_environment
}

resume_each() {
  local id="${1}" tool out=""
  shift
  for tool in "$@"; do
    out="${out}$(aisession_command "${tool}" "${id}")|"
  done
  printf '%s' "${out}"
}

@test "aisession - recognizes a native AI binary by its command name" {
  # Arrange
  local pc="claude" argv=""

  # Act
  run aisession_tool "${pc}" "${argv}"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "claude" ]
}

@test "aisession - recognizes a node AI tool by the script it runs" {
  # Arrange
  local pc="node" argv="node --no-warnings /opt/homebrew/bin/gemini --yolo"

  # Act
  run aisession_tool "${pc}" "${argv}"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "gemini" ]
}

@test "aisession - recognizes a python AI tool under the framework interpreter name" {
  # Arrange
  local pc="Python" argv="/usr/local/bin/Python /Users/u/.local/bin/aider"

  # Act
  run aisession_tool "${pc}" "${argv}"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "aider" ]
}

@test "aisession - rejects a runtime that runs some other script" {
  # Arrange
  local pc="node" argv="node /srv/app/server.js"

  # Act
  run aisession_tool "${pc}" "${argv}"

  # Assert
  [ "${status}" -eq 1 ]
  [ "${output}" = "" ]
}

@test "aisession - rejects a runtime with no script argument" {
  # Arrange
  local pc="node" argv="node"

  # Act
  run aisession_tool "${pc}" "${argv}"

  # Assert
  [ "${status}" -eq 1 ]
  [ "${output}" = "" ]
}

@test "aisession - rejects a program that is not an AI tool" {
  # Arrange
  local pc="vim" argv="vim notes.md"

  # Act
  run aisession_tool "${pc}" "${argv}"

  # Assert
  [ "${status}" -eq 1 ]
  [ "${output}" = "" ]
}

@test "aisession - reads the claude session id of a running process" {
  # Arrange
  printf '{"pid":4242,"sessionId": "00000000-0000-4000-8000-000000000001","cwd":"/p"}\n' \
    >"${CLAUDE_CONFIG_DIR}/sessions/4242.json"

  # Act
  run aisession_id "claude" "4242"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "00000000-0000-4000-8000-000000000001" ]
}

@test "aisession - yields no claude id when the process left no record" {
  # Arrange
  local pid="9999"

  # Act
  run aisession_id "claude" "${pid}"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "aisession - yields no claude id for an empty pid" {
  # Arrange
  printf '{"sessionId":"abc"}\n' >"${CLAUDE_CONFIG_DIR}/sessions/.json"

  # Act
  run aisession_id "claude" ""

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "aisession - yields no claude id from a record without one" {
  # Arrange
  printf '{"pid":4242}\n' >"${CLAUDE_CONFIG_DIR}/sessions/4242.json"

  # Act
  run aisession_id "claude" "4242"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "aisession - yields no id for a tool without a process record" {
  # Arrange
  printf '{"pid":4242,"sessionId":"abc"}\n' >"${CLAUDE_CONFIG_DIR}/sessions/4242.json"

  # Act
  run aisession_id "codex" "4242"

  # Assert
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "aisession - resumes each tool by session id" {
  # Arrange
  local tools=(claude codex opencode copilot crush)

  # Act
  local got
  got="$(resume_each "abc-1" "${tools[@]}")"

  # Assert
  [ "${got}" = "claude --resume abc-1|codex resume abc-1|opencode --session abc-1|copilot --resume=abc-1|crush --session abc-1|" ]
}

@test "aisession - continues the latest session of each tool without an id" {
  # Arrange
  local tools=(claude codex opencode copilot crush gemini qwen amp aider)

  # Act
  local got
  got="$(resume_each "" "${tools[@]}")"

  # Assert
  [ "${got}" = "claude --continue|codex resume --last|opencode --continue|copilot --continue|crush --continue|gemini --resume latest|qwen --continue|amp last|aider --restore-chat-history|" ]
}

@test "aisession - falls back to the latest session for a tool that has no id form" {
  # Arrange
  local id="abc-1"

  # Act
  run aisession_command gemini "${id}"

  # Assert
  [ "${output}" = "gemini --resume latest" ]
}

@test "aisession - refuses an id holding shell metacharacters" {
  # Arrange
  local id='x; rm -rf ~'

  # Act
  run aisession_command claude "${id}"

  # Assert
  [ "${output}" = "claude --continue" ]
}

@test "aisession - runs an unknown tool bare" {
  # Arrange
  local tool="mystery"

  # Act
  run aisession_resume_latest "${tool}"

  # Assert
  [ "${output}" = "mystery" ]
}
