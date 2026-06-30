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
  tmux set-option -gq "@persist_revamped_dir" "${SAVE}"
}

teardown() {
  cleanup_test_environment
}

# --- sensitive list and capture redaction ----------------------------------

@test "features - sensitive list defaults without extras" {
  local l
  l="$(persist_sensitive_list)"
  [[ "${l}" == *ssh* ]]
}

@test "features - sensitive list appends user entries" {
  tmux set-option -gq "@persist_revamped_redact" "myvpn"
  local l
  l="$(persist_sensitive_list)"
  [[ "${l}" == *ssh* ]]
  [[ "${l}" == *myvpn* ]]
}

@test "features - capture redacts a sensitive pane" {
  tmux set-option -gq "@persist_revamped_capture_panes" "on"
  _list_windows() { :; }
  _list_panes() { printf 'main\t0\t0\t1\t/h\tssh\t1\n'; }
  _capture_pane() { printf 'TOPSECRET\n'; }
  persist_dump >"${BATS_TEST_TMPDIR}/r.txt"
  run cat "${BATS_TEST_TMPDIR}/r.txt"
  [[ "${output}" != *TOPSECRET* ]]
}

@test "features - capture keeps a non-sensitive pane" {
  tmux set-option -gq "@persist_revamped_capture_panes" "on"
  _list_windows() { :; }
  _list_panes() { printf 'main\t0\t0\t1\t/h\tbash\t1\n'; }
  _capture_pane() { printf 'visible text\n'; }
  persist_dump >"${BATS_TEST_TMPDIR}/k.txt"
  run cat "${BATS_TEST_TMPDIR}/k.txt"
  [[ "${output}" == *"visible text"* ]]
}

# --- schema header and zoom capture ----------------------------------------

@test "features - dump appends a schema header record" {
  _list_windows() { printf 'main\t0\te\t1\tlay\t0\n'; }
  _list_panes() { printf 'main\t0\t0\t1\t/h\tbash\t1\n'; }
  persist_dump >"${BATS_TEST_TMPDIR}/d.txt"
  run cat "${BATS_TEST_TMPDIR}/d.txt"
  local last="${lines[$(( ${#lines[@]} - 1 ))]}"
  [[ "${last}" == header* ]]
  [[ "${last}" == *"${HOME}"* ]]
}

@test "features - dump records the window zoom flag" {
  _list_windows() { printf 'main\t0\te\t1\tlay\t1\n'; }
  _list_panes() { :; }
  persist_dump >"${BATS_TEST_TMPDIR}/z.txt"
  run cat "${BATS_TEST_TMPDIR}/z.txt"
  [[ "${lines[0]}" == window* ]]
  [[ "${lines[0]}" == *"lay"$'	'"1"* ]]
}

# --- named slots: save, restore, list --------------------------------------

@test "features - save writes a named slot file" {
  _list_windows() { printf 'main\t0\te\t1\tlay\t0\n'; }
  _list_panes() { :; }
  run persist_save work
  [ "${status}" -eq 0 ]
  [ -f "${SAVE}/slots/work.txt" ]
}

@test "features - restore loads a named slot" {
  mkdir -p "${SAVE}/slots"
  persist_join window proj 0 e 1 lay0 0 >"${SAVE}/slots/work.txt"
  _has_session() { return 1; }
  persist_restore work >"${BATS_TEST_TMPDIR}/o.txt"
  run cat "${BATS_TEST_TMPDIR}/o.txt"
  [[ "${output}" == *"new-session -d -s proj -n e"* ]]
}

@test "features - slots lists saved slot names" {
  mkdir -p "${SAVE}/slots"
  : >"${SAVE}/slots/work.txt"
  : >"${SAVE}/slots/play.txt"
  run persist_slots
  [[ "${output}" == *work* ]]
  [[ "${output}" == *play* ]]
}

# --- save hooks and rolling backups ----------------------------------------

@test "features - save runs the pre and post save hooks" {
  tmux set-option -gq "@persist_revamped_pre_save_hook" "echo PRE"
  tmux set-option -gq "@persist_revamped_post_save_hook" "echo POST"
  _list_windows() { :; }
  _list_panes() { :; }
  run persist_save
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"hook echo PRE"* ]]
  [[ "${output}" == *"hook echo POST"* ]]
}

@test "features - save writes no backups when disabled" {
  _list_windows() { :; }
  _list_panes() { :; }
  persist_save
  [ ! -d "${SAVE}/backups" ]
}

@test "features - rotate backups keeps the newest and prunes the oldest" {
  tmux set-option -gq "@persist_revamped_backups" "2"
  mkdir -p "${SAVE}/backups"
  : >"${SAVE}/last.txt"
  : >"${SAVE}/backups/last-100.txt"
  : >"${SAVE}/backups/last-200.txt"
  export MOCK_EPOCH=300
  persist_rotate_backups "${SAVE}/last.txt"
  [ ! -f "${SAVE}/backups/last-100.txt" ]
  [ -f "${SAVE}/backups/last-200.txt" ]
  [ -f "${SAVE}/backups/last-300.txt" ]
}

@test "features - rotate backups is a no-op for a non-numeric count" {
  tmux set-option -gq "@persist_revamped_backups" "lots"
  mkdir -p "${SAVE}"
  : >"${SAVE}/last.txt"
  persist_rotate_backups "${SAVE}/last.txt"
  [ ! -d "${SAVE}/backups" ]
}

# --- restore hooks, zoom, portable rewrite, vim sessions -------------------

@test "features - restore runs the pre and post restore hooks" {
  mkdir -p "${SAVE}"
  persist_join window main 0 e 1 lay0 0 >"${SAVE}/last.txt"
  _has_session() { return 1; }
  tmux set-option -gq "@persist_revamped_pre_restore_hook" "echo PRER"
  tmux set-option -gq "@persist_revamped_post_restore_hook" "echo POSTR"
  persist_restore >"${BATS_TEST_TMPDIR}/h.txt"
  run cat "${BATS_TEST_TMPDIR}/h.txt"
  [[ "${output}" == *"hook echo PRER"* ]]
  [[ "${output}" == *"hook echo POSTR"* ]]
}

@test "features - restore re-zooms a window saved as zoomed" {
  mkdir -p "${SAVE}"
  persist_join window main 0 e 1 lay0 1 >"${SAVE}/last.txt"
  _has_session() { return 1; }
  persist_restore >"${BATS_TEST_TMPDIR}/z.txt"
  run cat "${BATS_TEST_TMPDIR}/z.txt"
  [[ "${output}" == *"resize-pane -Z -t main:0"* ]]
}

@test "features - restore does not zoom an unzoomed window" {
  mkdir -p "${SAVE}"
  persist_join window main 0 e 1 lay0 0 >"${SAVE}/last.txt"
  _has_session() { return 1; }
  persist_restore >"${BATS_TEST_TMPDIR}/z2.txt"
  run cat "${BATS_TEST_TMPDIR}/z2.txt"
  [[ "${output}" != *"resize-pane -Z"* ]]
}

@test "features - restore rewrites the home prefix when portable is on" {
  mkdir -p "${SAVE}"
  {
    persist_join pane main 0 0 1 /home/old/proj bash
    persist_join header 1 /home/old 1000
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }
  tmux set-option -gq "@persist_revamped_rewrite_home" "on"
  HOME="/home/new" persist_restore >"${BATS_TEST_TMPDIR}/p.txt"
  run cat "${BATS_TEST_TMPDIR}/p.txt"
  [[ "${output}" == *"send-keys -t main:0 cd /home/new/proj Enter"* ]]
}

@test "features - restore opens an editor session when Session.vim exists" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /proj nvim >"${SAVE}/last.txt"
  _has_session() { return 1; }
  _file_exists() { return 0; }
  tmux set-option -gq "@persist_revamped_vim_sessions" "on"
  persist_restore >"${BATS_TEST_TMPDIR}/v.txt"
  run cat "${BATS_TEST_TMPDIR}/v.txt"
  [[ "${output}" == *"send-keys -t main:0 nvim -S Enter"* ]]
}

@test "features - restore falls back to a bare editor without a session file" {
  mkdir -p "${SAVE}"
  persist_join pane main 0 0 1 /proj nvim >"${SAVE}/last.txt"
  _has_session() { return 1; }
  _file_exists() { return 1; }
  tmux set-option -gq "@persist_revamped_vim_sessions" "on"
  persist_restore >"${BATS_TEST_TMPDIR}/v2.txt"
  run cat "${BATS_TEST_TMPDIR}/v2.txt"
  [[ "${output}" == *"send-keys -t main:0 nvim Enter"* ]]
  [[ "${output}" != *"nvim -S"* ]]
}

# --- selective merge restore -----------------------------------------------

@test "features - merge restores only the requested session" {
  mkdir -p "${SAVE}"
  {
    persist_join window work 0 e 1 lay0 0
    persist_join window play 0 e 1 lay0 0
  } >"${SAVE}/last.txt"
  _has_session() { return 1; }
  persist_merge work >"${BATS_TEST_TMPDIR}/m.txt"
  run cat "${BATS_TEST_TMPDIR}/m.txt"
  [[ "${output}" == *"new-session -d -s work"* ]]
  [[ "${output}" != *"-s play"* ]]
}

@test "features - merge does not clobber an existing session" {
  mkdir -p "${SAVE}"
  persist_join window work 0 e 1 lay0 0 >"${SAVE}/last.txt"
  _has_session() { return 0; }
  run persist_merge work
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "features - merge requires a session name" {
  run persist_merge
  [ "${status}" -eq 2 ]
}

# --- preview, verify, doctor -----------------------------------------------

@test "features - preview summarizes a save" {
  mkdir -p "${SAVE}"
  {
    persist_join window main 0 e 1 lay0 0
    persist_join pane main 0 0 1 /h bash
    persist_join header 1 /home/old 1000
  } >"${SAVE}/last.txt"
  run persist_preview
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"windows: 1"* ]]
  [[ "${output}" == *"panes:   1"* ]]
  [[ "${output}" == *"schema:  1"* ]]
}

@test "features - preview fails when the save is missing" {
  run persist_preview ghost
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no save"* ]]
}

@test "features - verify passes a healthy save" {
  mkdir -p "${SAVE}"
  {
    persist_join window main 0 e 1 lay0 0
    persist_join pane main 0 0 1 /h bash
    persist_join header 1 /home/old 1000
  } >"${SAVE}/last.txt"
  run persist_verify
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"schema version 1"* ]]
}

@test "features - verify fails on a missing save" {
  run persist_verify ghost
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL no save file"* ]]
}

@test "features - verify warns on a legacy save without a header" {
  mkdir -p "${SAVE}"
  persist_join window main 0 e 1 lay0 0 >"${SAVE}/last.txt"
  run persist_verify
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no schema header"* ]]
}

@test "features - verify fails when there are no window records" {
  mkdir -p "${SAVE}"
  persist_join header 1 /home/old 1000 >"${SAVE}/last.txt"
  run persist_verify
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"no window records"* ]]
}

@test "features - verify warns on a stale save" {
  mkdir -p "${SAVE}"
  {
    persist_join window main 0 e 1 lay0 0
    persist_join header 1 /home/old 1
  } >"${SAVE}/last.txt"
  tmux set-option -gq "@persist_revamped_stale_secs" "10"
  export MOCK_EPOCH=1000000
  run persist_verify
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"stale"* ]]
}

@test "features - doctor prints a capability report" {
  run persist_doctor
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tmux-persist-revamped doctor"* ]]
  [[ "${output}" == *"save dir:"* ]]
  [[ "${output}" == *"replay list:"* ]]
}

@test "features - doctor reports a present save and missing tools" {
  mkdir -p "${SAVE}"
  : >"${SAVE}/last.txt"
  has_command() { return 1; }
  run persist_doctor
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tmux:         MISSING"* ]]
  [[ "${output}" == *"fzf:          missing"* ]]
  [[ "${output}" == *"default save: present"* ]]
}

@test "features - ps forest uses the BSD branch on Darwin" {
  uname() { echo Darwin; }
  run _read_ps_forest
  true
}

# --- event-based debounced saves -------------------------------------------

@test "features - event does nothing when debounce is disabled" {
  local saved=0
  persist_save() { saved=1; }
  persist_event
  [ "${saved}" -eq 0 ]
}

@test "features - event saves and stamps when the window elapsed" {
  tmux set-option -gq "@persist_revamped_event_debounce" "5"
  tmux set-option -gq "@persist_revamped_event_ts" "1000"
  export MOCK_EPOCH=1100
  local saved=0
  persist_save() { saved=1; return 0; }
  persist_event
  [ "${saved}" -eq 1 ]
  [[ "$(tmux show-option -gqv "@persist_revamped_event_ts")" == "1100" ]]
}

@test "features - event skips inside the debounce window" {
  tmux set-option -gq "@persist_revamped_event_debounce" "5"
  tmux set-option -gq "@persist_revamped_event_ts" "1099"
  export MOCK_EPOCH=1100
  local saved=0
  persist_save() { saved=1; }
  persist_event
  [ "${saved}" -eq 0 ]
}

@test "features - event skips inside the boot grace window" {
  tmux set-option -gq "@persist_revamped_event_debounce" "5"
  tmux set-option -gq "@persist_revamped_event_ts" "0"
  tmux set-option -gq "@persist_revamped_boot_ts" "1090"
  tmux set-option -gq "@persist_revamped_boot_grace" "60"
  export MOCK_EPOCH=1100
  local saved=0
  persist_save() { saved=1; }
  persist_event
  [ "${saved}" -eq 0 ]
}

# --- picker and seams ------------------------------------------------------

@test "features - pick restores the chosen slot" {
  _list_dir() { printf 'work.txt\n'; }
  _fzf() { cat >/dev/null; printf 'work\n'; }
  local got=""
  persist_restore() { got="$1"; }
  persist_pick
  [ "${got}" == "work" ]
}

@test "features - pick fails when there are no slots" {
  _list_dir() { :; }
  run persist_pick
  [ "${status}" -ne 0 ]
}

@test "features - pick fails when the picker is cancelled" {
  _list_dir() { printf 'work.txt\n'; }
  _fzf() { cat >/dev/null; return 1; }
  run persist_pick
  [ "${status}" -ne 0 ]
}

@test "features - fzf seam returns nonzero without fzf" {
  has_command() { return 1; }
  run _fzf </dev/null
  [ "${status}" -ne 0 ]
}

@test "features - fzf seam pipes through fzf when present" {
  has_command() { return 0; }
  fzf() { cat; }
  local result
  result="$(printf 'work\n' | _fzf)"
  [ "${result}" == "work" ]
}

@test "features - file_exists detects a real file" {
  : >"${BATS_TEST_TMPDIR}/probe"
  run _file_exists "${BATS_TEST_TMPDIR}/probe"
  [ "${status}" -eq 0 ]
  run _file_exists "${BATS_TEST_TMPDIR}/nope"
  [ "${status}" -ne 0 ]
}

@test "features - run_hook echoes under dry run and skips empty" {
  run _run_hook "echo x"
  [[ "${output}" == "hook echo x" ]]
  run _run_hook ""
  [ -z "${output}" ]
}

@test "features - run_hook executes the command without dry run" {
  unset PERSIST_DRY_RUN
  local marker="${BATS_TEST_TMPDIR}/hook.marker"
  _run_hook "touch '${marker}'"
  [ -f "${marker}" ]
}

@test "features - list_dir returns basenames and nothing on no match" {
  mkdir -p "${BATS_TEST_TMPDIR}/d"
  : >"${BATS_TEST_TMPDIR}/d/a.txt"
  : >"${BATS_TEST_TMPDIR}/d/b.txt"
  run _list_dir "${BATS_TEST_TMPDIR}/d" '*.txt'
  [ "${#lines[@]}" -eq 2 ]
  run _list_dir "${BATS_TEST_TMPDIR}/d" '*.nomatch'
  [ "${#lines[@]}" -eq 0 ]
}

# --- dispatch routing ------------------------------------------------------

@test "features - main routes the new subcommands" {
  persist_merge() { echo "MERGE $*"; }
  persist_event() { echo EVENT; }
  persist_slots() { echo SLOTS; }
  persist_pick() { echo PICK; }
  persist_preview() { echo "PREVIEW $*"; }
  persist_verify() { echo "VERIFY $*"; }
  persist_doctor() { echo DOCTOR; }
  [[ "$(persist_main merge work)" == "MERGE work" ]]
  [[ "$(persist_main event)" == "EVENT" ]]
  [[ "$(persist_main slots)" == "SLOTS" ]]
  [[ "$(persist_main pick)" == "PICK" ]]
  [[ "$(persist_main preview work)" == "PREVIEW work" ]]
  [[ "$(persist_main verify work)" == "VERIFY work" ]]
  [[ "$(persist_main doctor)" == "DOCTOR" ]]
}

@test "features - main passes a slot to save and restore" {
  persist_save() { echo "SAVE $*"; }
  persist_restore() { echo "RESTORE $*"; }
  [[ "$(persist_main save work)" == "SAVE work" ]]
  [[ "$(persist_main restore work)" == "RESTORE work" ]]
}
