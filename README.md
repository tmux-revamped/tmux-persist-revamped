<div align="center">

<h1>tmux-persist-revamped</h1>

<strong>Save, auto-save, and restore your whole tmux environment, one plugin, no status-line tricks.</strong>

</div>

One plugin that captures every session, window, pane, layout, and working
directory, optionally replays the program each pane was running, and brings it all
back after a reboot. It is a single rewrite of the save/restore engine and the
auto-save automation that usually ship as two separate plugins.

## How it works

A save walks the live server through tmux format strings, writes each window and
pane as one escaped record, and renames the result over the previous save in a
single step, so an interrupted save never leaves a half-written file. Restore reads
that file back, recreates the session tree, returns each pane to its directory, and
replays an allow-listed program.

Auto-save runs from a small detached worker that ticks on a timer and asks the
plugin whether a save is due. It never writes into `status-right`, so your status
line stays yours and saving does not depend on how often the bar refreshes. After a
restore on server start, a short grace window holds auto-save off so it cannot
overwrite what was just brought back.

The save file uses an escaped field format read under a fixed locale, so an empty
pane title, a tab inside a value, or a path with spaces round-trips without
corrupting the record. Counting other tmux servers reads the socket directory
rather than scanning process arguments, which keeps it quiet on macOS after sleep.

## Keys

| Key | Action |
|-----|--------|
| `prefix + C-s` | save now |
| `prefix + C-r` | restore the last save |

Both keys are configurable.

## Commands

Run any of these as `bash <plugin>/src/persist.sh <command>`, or bind them to keys.

| Command | Action |
|---------|--------|
| `save [slot]` | save now, into a named slot when given |
| `restore [slot]` | restore a save, from a named slot when given |
| `merge <session> [slot]` | restore one session only, and never over a session that already exists |
| `slots` | list the named slots |
| `pick` | choose a slot through fzf and restore it |
| `preview [slot]` | print what a save holds without touching the server |
| `verify [slot]` | check a save's integrity, schema version, and staleness |
| `doctor` | report what the plugin found on this host |
| `event` | a debounced save for a tmux close hook |

## Configuration

| Option | Default | Meaning |
|--------|---------|---------|
| `@persist_revamped_save_key` | `C-s` | key that triggers a manual save |
| `@persist_revamped_restore_key` | `C-r` | key that triggers a restore |
| `@persist_revamped_interval` | `15` | auto-save interval in minutes; `0` turns auto-save off |
| `@persist_revamped_dir` | `$XDG_STATE_HOME/tmux/persist` | where saves are written |
| `@persist_revamped_processes` | empty | extra programs to replay on restore, appended to the built-in list |
| `@persist_revamped_capture_panes` | `off` | set to `on` to save each pane's visible text and repaint it on restore; trailing blank lines are trimmed so the real output stays on screen |
| `@persist_revamped_capture_args` | `off` | set to `on` to save the full command line of each restorable program and replay it with its arguments, for example `vim src/app.ts` instead of bare `vim`; falls back to the bare command when the arguments cannot be resolved |
| `@persist_revamped_restore_on_start` | `off` | restore automatically when the server starts |
| `@persist_revamped_boot_grace` | `60` | seconds after a boot restore during which auto-save stays off |
| `@persist_revamped_pick_key` | empty | key for the fzf slot-picker popup; unbound until set |
| `@persist_revamped_redact` | empty | extra commands whose scrollback is never captured, appended to the built-in `ssh`, `sudo`, and similar |
| `@persist_revamped_vim_sessions` | `off` | when `on`, reopen an editor with `-S` if a `Session.vim` sits in the pane's directory |
| `@persist_revamped_rewrite_home` | `off` | when `on`, rewrite a saved home prefix to the current home on restore, for moving a save between machines |
| `@persist_revamped_backups` | `0` | number of timestamped backups to keep per save; `0` keeps none |
| `@persist_revamped_event_debounce` | `0` | seconds; when above `0`, genuine close events trigger a debounced save |
| `@persist_revamped_stale_secs` | `0` | `verify` flags a save older than this many seconds; `0` disables the staleness check |
| `@persist_revamped_pre_save_hook` | empty | shell command run before each save |
| `@persist_revamped_post_save_hook` | empty | shell command run after a successful save |
| `@persist_revamped_pre_restore_hook` | empty | shell command run before each restore |
| `@persist_revamped_post_restore_hook` | empty | shell command run after each restore |

The built-in replay list covers common editors, pagers, and CLIs: `vim`, `nvim`,
`emacs`, `less`, `man`, `top`, `htop`, `ssh`, `claude`, `codex`, and more. Anything
not on the list is left as a plain shell.

## Examples

```tmux
# save every 5 minutes and restore on start
set -g @persist_revamped_interval '5'
set -g @persist_revamped_restore_on_start 'on'

# also replay these programs
set -g @persist_revamped_processes 'lazygit k9s weechat'

# keep saves under a project directory instead of XDG state
set -g @persist_revamped_dir '~/.tmux/persist'
```

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf`:

```tmux
set -g @plugin 'tmux-revamped/tmux-persist-revamped'
```

Press `prefix + I` to install.

## Compatibility

Runs on every tmux version TPM supports, with a floor of tmux 1.9, on Linux,
macOS on Intel and Apple Silicon, and WSL. Shell helpers work the same under BSD
and GNU userlands.

## Not yet restored

Deferred to a later release, deliberately rather than dropped:

- Pane contents, the scrollback. The repaint methods in common use leave artifacts
  in the shell history, so this needs a dedicated, tested approach.
- A program's full command line with arguments. Capturing it reliably means
  reading per-pane process state, which reintroduces the cost this rewrite avoids.
- Grouped sessions.

## Development

```bash
make test    # bats suite
make lint    # shellcheck
```

The save-file codec, the timing logic, the program-restore matcher, and the
server count are pure functions with fixture tests; every tmux call is a seam the
suite drives, so the save and restore flow is verified without a live server.

## License

MIT

<!-- family:begin -->

## The tmux-revamped family

This plugin is one member of the tmux-revamped family. Every member carries the
same contract in [`FAMILY.md`](FAMILY.md), the same tooling under `family/`, and
the same shared library, all held byte-identical by a checksum manifest. They are
built to be installed together: no member claims a key or a tmux option that
another member claims.

A defect found in one member is hunted across all of them before the fix is
called done. That obligation is written into the contract rather than left to
memory, and `family/bin/sweep` is how it is discharged.

| Member | What it does |
|---|---|
| [`tmux-autoreload-revamped`](https://github.com/tmux-revamped/tmux-autoreload-revamped) | Edit your tmux config, save, and watch it reload itself, no key, no command |
| [`tmux-battery-revamped`](https://github.com/tmux-revamped/tmux-battery-revamped) | Battery status for your tmux status bar, without ever blocking the status render |
| [`tmux-bluetooth-revamped`](https://github.com/tmux-revamped/tmux-bluetooth-revamped) | Every connected Bluetooth device and its battery in your tmux status bar, without blocking the render |
| [`tmux-cpu-revamped`](https://github.com/tmux-revamped/tmux-cpu-revamped) | CPU load, temperature, and frequency in your tmux status bar, without ever blocking the render |
| [`tmux-disk-revamped`](https://github.com/tmux-revamped/tmux-disk-revamped) | Disk usage for your tmux status bar, without ever blocking the status render |
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | Fuzzy-grab any URL, path, or word off the screen and paste it, pure shell, no Python |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | Jump to any session, window, or pane, or kill it, from one fzf popup |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | Git repository status in your tmux status bar, without ever blocking the render |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | GPU load, temperature, frequency, and memory for your tmux status bar |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | Current Kubernetes context and namespace in your tmux status bar, async, kubectl-free, never blocking |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | Launch any TUI app in a popup or a window, scoped to the current pane's directory, with one configurable bindi |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | Capture any pane to a file: live logging, full scrollback, or a one-shot screenshot |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | Now playing in your tmux status bar, without ever blocking the status render |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | Network throughput in your tmux status bar, without ever blocking the render |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | Standard pane and window management bindings for tmux, version aware, vim friendly, and fully configurable |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | **this plugin**, One plugin that captures every session, window, pane, layout, and working |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | A template for building non-blocking tmux status plugins |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | A Pomodoro timer in your tmux status bar, with zero temp files: all state lives in tmux options |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | RAM usage for your tmux status bar, without ever blocking the status render |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | Mouse wheel that does the right thing: scroll the app directly, copy-mode everywhere else. No app names to con |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | Sensible tmux defaults that normalize behavior across every tmux version, OS, and terminal, without clobbering |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | --- |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | Local clock and world clocks in your tmux status bar, without ever blocking the render |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | Weather in your tmux status bar, fetched in the background so the render never waits on the network |

### Checking an installation

With every member on disk, one command reports any conflict between them:

```sh
family/bin/doctor --live
```

It reads each member and the running tmux server, and reports duplicate keys,
duplicate status placeholders, options outside the naming grammar, and any
member whose contract version has fallen behind.

<!-- family:end -->
