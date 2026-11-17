# tmux-persist-revamped

Guidance for anyone, human or agent, changing tmux-persist-revamped. What it is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything this plugin shares with the rest of the tmux-revamped family, and it is the same in every member. This file holds only what is exclusive to tmux-persist-revamped, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into [`FAMILY.md`](FAMILY.md) instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`persist-revamped.tmux`](persist-revamped.tmux) | The entry point TPM runs |
| [`src/persist.sh`](src/persist.sh) | The script the keys, popups and the auto-save worker call. It sources the three below |
| [`src/persist-boot.sh`](src/persist-boot.sh) | The login agent: install, uninstall and sync |
| [`src/persist-report.sh`](src/persist-report.sh) | Slots, the picker, preview, verify and doctor |
| [`src/persist-restore.sh`](src/persist-restore.sh) | Restore and merge |
| [`src/lib/persist/`](src/lib/persist) | This member's modules |
| [`src/lib/utils/constants.sh`](src/lib/utils/constants.sh) | This member's constants, including its version |
| [`src/lib/utils/`](src/lib/utils), [`src/lib/tmux/`](src/lib/tmux) | The shared library. Every file there except `constants.sh` is identical in every member |
| [`test/`](test) | The bats suite. `helpers.bash` and `tmux_helpers.bash` are identical in every member; this member's own mocks go in the `_local` files |

## Names

- Settings are tmux options named `@persist_revamped_<setting>`.
- It has no status placeholders.
- Public functions carry `persist_`; private ones start with `_`.
- The version constant is `PERSIST_REVAMPED_VERSION`.
- Its command-line tool, once it exists, is `persist-revamped`.

## Behaviour

- Saves every session, window and pane, saves on a timer, and restores it all after a reboot.
- `C-s` saves and `C-r` restores.
- A save reads the server with `list-windows -a` and `list-panes -a`, writes one escaped record per window and pane to a temporary file, and moves it into `history/` under a timestamped name; the slot is a symlink to the newest file.
- Unless the interval is `0`, loading the plugin starts one background worker per server that wakes every 60 seconds and saves when the interval has passed.

## Domain rules

- A save never replaces a save that holds windows with one that holds none, because a server holds no session while it starts and while it closes its last one.
- A save identical to the previous one is dropped, and files beyond `@persist_revamped_backups` are deleted.
- A restore puts every window back at its saved index, or a free one when it is taken, and creates every pane in its saved directory, so no `cd` is typed into a pane.
- Only the default socket saves at the top of the save directory; a server started with `-L name` saves under `servers/name/`.
- The halt file stops restore on start until it is deleted.

## Release

- `PERSIST_REVAMPED_VERSION` in [`src/lib/utils/constants.sh`](src/lib/utils/constants.sh) holds the version. It must equal the newest versioned heading in [`CHANGELOG.md`](CHANGELOG.md) and the README's version badge, which the `version` job in `tests.yml` checks.
- A push to `main` whose version has no tag yet makes the `release` job in `tests.yml` tag `vX.Y.Z` and publish a GitHub release with that changelog section.
- Unreleased changes sit under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md) until a release is cut.

## Gaps against FAMILY.md

As of 2026-11-16:

- Every script is bash, under `#!/usr/bin/env bash`, not POSIX `sh`, so it is untested under `dash`, `zsh` and BusyBox `sh`.
- The code lives in [`src/`](src) and [`src/lib/`](src/lib); there is no `bin/persist-revamped`, `lib/state.sh` or `lib/core.sh`.
- No `persist-revamped` command with `help`, `version` and `doctor` in the family's form, no man page, no completions and no `manifest.json`.
- No gum interface: no `lib/ui.sh`, `lib/table.awk`, themes or `test/bin/gum`.
- No `screens/`: no VHS recording of each feature, no on-screen caption of the keys each recording presses, and no recordings in the README.
- The README sections are not the family's order of Quick start, Usage, topic sections, Portability, Development and License.
- Coverage is kcov with a 95 percent floor on Linux, not bashcov at 100 percent merged from macOS and Linux.
- CI tests GNU, BSD and uutils tools in `tests.yml`, but not the six toolsets through `.github/scripts/toolset.sh`, and no shell matrix under `sh`, `dash`, `bash` and `zsh`.
- No golden transcripts, `call.sh`, `run-matrix.sh` or `linux-container.sh`.
- The version is written by hand and released by `tests.yml`; there is no semantic-release, `package.json`, `release.yml` with `recover`, `bot-merge.yml` or Renovate.
- CI is `tests.yml` and `security.yml`, not `ci.yml`, and no job starts with `step-security/harden-runner`.
- No `.editorconfig`, `.yamllint.yml` or shfmt; the Makefile has `help`, `test`, `test-unit`, `coverage`, `lint` and `clean`, not the family's targets.
- Saves are serialized by a lock directory, where FAMILY.md requires a `set -C` lock file.
- No `@persist_revamped_notify` for a failed save yet.
- No test presses its keys through a real client attached from a second tmux.
- The picker key's popup command names the dispatcher path in plain single quotes, which leaves a `#` in a popup's command when the checkout path holds one; that runs on tmux 3.6 and 3.8, which expand no format there, and is not the hash-free form.
