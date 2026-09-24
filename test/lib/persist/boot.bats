#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _PERSIST_REVAMPED_BOOT_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/persist/boot.sh"
}

teardown() {
  cleanup_test_environment
}

@test "boot - a label of letters, digits and separators is valid" {
  run boot_label_valid "tmux-persist-revamped"

  [ "${status}" -eq 0 ]
}

@test "boot - a label that could escape a path is rejected" {
  run boot_label_valid "../evil"
  [ "${status}" -ne 0 ]

  run boot_label_valid "9lives"
  [ "${status}" -ne 0 ]

  run boot_label_valid ""
  [ "${status}" -ne 0 ]
}

@test "boot - the agent path on macOS is a launch agent plist" {
  run boot_agent_path Darwin /Users/me tmux-persist

  [[ "${output}" == "/Users/me/Library/LaunchAgents/tmux-persist.plist" ]]
}

@test "boot - the agent path elsewhere is a systemd user unit" {
  run boot_agent_path Linux /home/me tmux-persist

  [[ "${output}" == "/home/me/.config/systemd/user/tmux-persist.service" ]]
}

@test "boot - the plist carries the label, the binary and one entry per argument" {
  run boot_plist lbl /usr/bin/tmux "new-session -d"

  [[ "${output}" == *"<string>lbl</string>"* ]]
  [[ "${output}" == *"<string>/usr/bin/tmux</string>"* ]]
  [[ "${output}" == *"<string>new-session</string>"* ]]
  [[ "${output}" == *"<string>-d</string>"* ]]
  [[ "${output}" == *"<key>RunAtLoad</key>"* ]]
}

@test "boot - the plist does not restart a server the user killed" {
  run boot_plist lbl /usr/bin/tmux "new-session -d"

  [[ "${output}" != *"KeepAlive"* ]]
}

@test "boot - the unit starts the server at login and stops it at logout" {
  run boot_unit /usr/bin/tmux "new-session -d"

  [[ "${output}" == *"ExecStart=/usr/bin/tmux new-session -d"* ]]
  [[ "${output}" == *"ExecStop=/usr/bin/tmux kill-server"* ]]
  [[ "${output}" == *"WantedBy=default.target"* ]]
}
