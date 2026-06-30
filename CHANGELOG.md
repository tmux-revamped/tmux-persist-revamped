# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-06-30

### Added

- Named save slots. `save <slot>` and `restore <slot>` park and swap whole
  environments under their own files; the unnamed slot stays the legacy
  `last.txt`. `slots` lists them and `pick` restores one through an fzf popup,
  bound only when `@persist_revamped_pick_key` is set.
- Full layout fidelity. The window zoom state is now saved and reapplied on
  restore alongside the exact layout, active window, and active pane.
- Vim and Neovim session restore. With `@persist_revamped_vim_sessions` on, a
  pane whose editor left a `Session.vim` reopens with `nvim -S` into a fresh
  shell pane instead of a bare editor.
- Selective merge restore. `merge <session>` restores a single session and never
  when it already exists, so a running environment is never clobbered.
- Sensitive-pane redaction. Capture skips the scrollback of panes running `ssh`,
  `sudo`, and similar; extend the list with `@persist_revamped_redact`.
- Event-based saves. With `@persist_revamped_event_debounce` set, genuine close
  events trigger a debounced save; the boot grace window still suppresses it.
- Host-portable saves. With `@persist_revamped_rewrite_home` on, a directory
  saved under one home is replayed under the current home.
- Save and restore hooks: `@persist_revamped_pre_save_hook`,
  `_post_save_hook`, `_pre_restore_hook`, and `_post_restore_hook`.
- Rolling backups. `@persist_revamped_backups` keeps that many timestamped
  copies of a save, pruning the oldest.
- Inspection commands: `preview` summarizes a save, `verify` checks its
  integrity and staleness, and `doctor` reports what was found on the host. Save
  files now carry a schema-version header.

## [1.2.1] - 2026-06-24

### Fixed

- Restore now runs only once per server lifetime instead of on every config
  reload. The entry point calls `boot` on each plugin load, so a `source-file`
  used to re-run a full restore against the live session. A server-scoped marker
  now tells a genuine server start apart from a reload.
- Restore never sends keystrokes to a pane that is not a shell. A restore against
  a live server could resolve to a window already running a program and inject a
  `cd`, a repaint, or a replayed command into it. Each pane's current command is
  checked, and the directory, repaint, and program replay are skipped for any
  pane that is not an interactive shell.

## [1.2.0] - 2026-06-24

### Added

- Optional full command-line restore. With `@persist_revamped_capture_args` set
  to `on`, a restorable program is replayed with its arguments (`vim src/app.ts`
  rather than bare `vim`). The argument capture reads the pane shell's foreground
  child from `ps`, picking the correct flags per userland, and falls back to the
  bare command whenever the arguments cannot be resolved, so a restore never
  replays a wrong command.

## [1.1.0] - 2026-06-24

### Added

- Optional pane-content repaint. With `@persist_revamped_capture_panes` set to
  `on`, each pane's visible text is saved and redrawn on restore. The content is
  catted from a temporary file rather than typed, so it can never run as
  commands, and trailing blank lines are trimmed so the restored screen is not
  scrolled away (upstream resurrect #549, #503).

## [1.0.0] - 2026-06-23

### Added

- Save the full tmux environment: sessions, windows, panes, layouts, and working
  directories, with `prefix + C-s`.
- Restore it with `prefix + C-r`, replaying an allow-listed foreground program in
  each pane, reapplying each window's saved layout, and returning focus to the
  window and pane that were active.
- Auto-save on a configurable interval from a detached worker that never writes
  into `status-right`.
- Restore on server start, guarded by a boot grace window so the first auto-save
  cannot overwrite what was just restored.
- An escaped, fixed-locale save format that round-trips empty fields, embedded
  tabs, backslashes, and spaces without corruption.
- Atomic, exit-gated saves: a temp file renamed into place, and the auto-save
  timestamp advanced only when the save succeeds.
- Server counting from the socket directory instead of scanning process
  arguments, which stays quiet on macOS after sleep.
- Configurable keys, interval, save directory, replay list, restore-on-start, and
  boot grace.
