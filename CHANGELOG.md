# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
