<div align="center">

# tmux-persist-revamped

<strong>Save every tmux session, window and pane, auto-save on a timer, and restore it all after a reboot.</strong>

English | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | [繁體中文（香港）](README.zh-HK.md)

[![Tests](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml/badge.svg)](https://github.com/tmux-revamped/tmux-persist-revamped/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](CHANGELOG.md)

<p align="center">
  <a href="#what-it-does">What it does</a> |
  <a href="#installation">Installation</a> |
  <a href="#usage">Usage</a> |
  <a href="#configuration">Configuration</a> |
  <a href="#key-bindings">Key bindings</a> |
  <a href="#how-it-works">How it works</a>
</p>

</div>

**Auto-saves every 15 minutes. Keeps the last 5 saves of each slot. Replays 20 programs without configuration. Tested on macOS and Linux.**

---

## What it does

A save records every session, window and pane on the server: window names, indexes, layouts and zoom state, the active window and pane, each pane's working directory, and the program it runs. A restore rebuilds that tree, sends each shell pane back to its directory, and starts the program again when it is on the replay list.

The same plugin auto-saves on a timer, keeps a history of saves, parks whole environments in named slots, and can install a login agent so a tmux server, and your restored environment, exist before the first terminal opens.

## Requirements

| Requirement | Version or note |
|:------------|:----------------|
| tmux | 3.2 or later |
| bash | 3.2 or later, so the stock macOS `/bin/bash` works |
| Operating system | macOS on Apple Silicon and Intel, Linux on x86_64 and arm64 |
| Core tools | BSD, GNU or uutils coreutils |
| `fzf` | Optional, for the slot picker |
| `launchctl` or `systemctl --user` | Optional, for the login agent on macOS or Linux |

## Installation

With [TPM](https://github.com/tmux-plugins/tpm), add the plugin to `~/.tmux.conf` and press `prefix + I`:

```tmux
set -g @plugin 'tmux-revamped/tmux-persist-revamped'
```

Without TPM, clone the repository and run the entry point from `~/.tmux.conf`:

```sh
git clone https://github.com/tmux-revamped/tmux-persist-revamped ~/.tmux/plugins/tmux-persist-revamped
```

```tmux
run-shell ~/.tmux/plugins/tmux-persist-revamped/persist-revamped.tmux
```

## Usage

Press `prefix + C-s` to save and `prefix + C-r` to restore the last save. Auto-save is on from the moment the plugin loads.

To restore on server start and save more often:

```tmux
set -g @persist_revamped_restore_on_start 'on'
set -g @persist_revamped_interval '5'
set -g @persist_revamped_processes 'lazygit k9s'
```

Every action is also a command. Run it as `bash ~/.tmux/plugins/tmux-persist-revamped/src/persist.sh <command>`, or bind it to a key.

| Command | Action |
|:--------|:-------|
| `save [slot]` | Save now, into a named slot when one is given |
| `restore [slot]` | Restore the last save, or a named slot |
| `merge <session> [slot]` | Restore one session, only when no session of that name exists |
| `slots` | List the named slots |
| `pick` | Choose a named slot with fzf and restore it |
| `preview [slot]` | Print the save's path, schema, origin home, and window and pane counts |
| `verify [slot]` | Check the schema header, the record counts and the save's age |
| `doctor` | Report the save directory, the tools found, the halt file and the login agent |
| `event` | Save once per debounce period, for the close hooks |
| `boot-install` | Write and load the login agent |
| `boot-uninstall` | Unload and remove the login agent |
| `boot-sync` | Install or remove the login agent to match `@persist_revamped_boot` |

## Configuration

Set any option in `~/.tmux.conf` before the plugin loads.

| Option | Default | Meaning |
|:-------|:--------|:--------|
| `@persist_revamped_interval` | `15` | Minutes between auto-saves. `0` turns auto-save off |
| `@persist_revamped_dir` | `$XDG_STATE_HOME/tmux/persist` | Save directory, `~/.local/state/tmux/persist` when `XDG_STATE_HOME` is unset. A leading `~` is expanded, and so are `$HOME` and `$HOSTNAME` |
| `@persist_revamped_scope_socket` | `on` | Give every server other than the default socket its own save directory |
| `@persist_revamped_processes` | empty | Extra programs to replay, added to the built-in list. Each entry is a shell glob |
| `@persist_revamped_capture_panes` | `off` | `on` saves each pane's visible text and repaints it on restore, with trailing blank lines trimmed |
| `@persist_revamped_capture_args` | `off` | `on` saves each program's full command line, such as `vim src/app.ts`, and replays it. A line holding a shell metacharacter or a quote replays as the bare program name |
| `@persist_revamped_redact` | empty | Extra programs whose pane text is never captured, added to `ssh sudo su vault gpg pass op ssh-add openssl` |
| `@persist_revamped_restore_on_start` | `off` | `on` restores the last save when the server starts |
| `@persist_revamped_halt_file` | `<save dir>/no-restore` | While this file exists, restore on start is skipped |
| `@persist_revamped_boot` | `off` | `on` installs a login agent that starts a tmux server at login |
| `@persist_revamped_boot_command` | `new-session -d` | Arguments the login agent passes to tmux |
| `@persist_revamped_boot_label` | `tmux-persist-revamped` | The launchd label or systemd unit name |
| `@persist_revamped_boot_grace` | `60` | Seconds after a restore on start during which no auto-save or event save runs |
| `@persist_revamped_backups` | `5` | Saves kept in each slot's history, the current one included. The floor is `1` |
| `@persist_revamped_event_debounce` | `0` | Seconds. Above `0`, closing a session or a window triggers a save at most once per period |
| `@persist_revamped_stale_secs` | `0` | `verify` warns about a save older than this many seconds. `0` turns the check off |
| `@persist_revamped_vim_sessions` | `off` | `on` reopens vim, nvim, vi, gvim or mvim with `-S` when a `Session.vim` sits in the pane's directory |
| `@persist_revamped_rewrite_home` | `off` | `on` rewrites the home directory recorded in the save to the current one on restore, for a save moved between machines |
| `@persist_revamped_save_key` | `C-s` | Prefix key that saves |
| `@persist_revamped_restore_key` | `C-r` | Prefix key that restores |
| `@persist_revamped_pick_key` | empty | Prefix key that opens the slot picker in a popup. Unbound until set |
| `@persist_revamped_pre_save_hook` | empty | Shell command run before each save |
| `@persist_revamped_post_save_hook` | empty | Shell command run after each successful save |
| `@persist_revamped_pre_restore_hook` | empty | Shell command run before each restore |
| `@persist_revamped_post_restore_hook` | empty | Shell command run after each restore |

The built-in replay list is `vi vim nvim emacs nano man less more tail top htop btop watch ssh mosh irssi weechat mutt claude codex`. A pane running anything else comes back as a shell in the right directory.

### Internal state

The plugin manages these options itself. Do not set them.

| Option | Holds |
|:-------|:------|
| `@persist_revamped_booted` | `1` once restore on start has run, or was skipped by the halt file, so a config reload does not restore again |
| `@persist_revamped_boot_ts` | Epoch seconds when restore on start finished, the start of the grace period |
| `@persist_revamped_last_ts` | Epoch seconds of the last successful auto-save |
| `@persist_revamped_event_ts` | Epoch seconds of the last event save |
| `@persist_revamped_worker_pid` | Process id of the auto-save worker, so a reload stops the old one |

## Key bindings

| Key | Action | Option |
|:----|:-------|:-------|
| `prefix + C-s` | Save | `@persist_revamped_save_key` |
| `prefix + C-r` | Restore the last save | `@persist_revamped_restore_key` |
| unbound | Pick a named slot in a popup | `@persist_revamped_pick_key` |

`C-s` and `C-r` are the keys the tmux-revamped family allocates to this plugin. They use `C-` so that save and restore work without releasing the modifier.

## How it works

**Saving.** A save reads the server with `list-windows -a` and `list-panes -a`, writes one escaped record per window and pane to a temporary file, and moves the finished file into `history/` under a timestamped name. The slot's path, `last.txt` or `slots/<name>.txt`, is a symlink to the newest file. An interrupted save never leaves a partial file behind.

**History.** A save identical to the previous one is dropped, so an idle machine does not fill the history. Older files beyond `@persist_revamped_backups` are deleted. Rolling back is pointing the symlink at an older file.

**Safety.** A save never replaces a save that holds windows with one that holds none. A server holds no session while it starts and while it closes its last session, and a save taken then would erase the environment. One save runs at a time, behind a lock directory that a killed save cannot hold for more than two minutes.

**Restoring.** A restore recreates each session and puts every window back at its saved index. When that index is already taken, the window goes to a free one. Each pane that runs a shell gets a `cd` to its directory, and a program on the replay list is started again. Layouts, the active window, the active pane and zoom are applied last.

**Auto-save.** Unless the interval is `0`, loading the plugin starts one background worker per server. It wakes every 60 seconds and saves when the interval has passed. It never writes to `status-right`. It exits when the server stops answering or a newer worker takes over.

**Several servers.** Every tmux server on a machine reads the same `~/.tmux.conf`. Only the default socket, `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default`, saves at the top of the save directory. A server started with `-L name` saves under `servers/name/`, and one started with `-S path` under a directory named from that path.

**Login agent.** With `@persist_revamped_boot` on, the plugin writes a launchd agent to `~/Library/LaunchAgents/` on macOS or a systemd user unit to `~/.config/systemd/user/` on Linux. It starts a tmux server at login, so restore on start runs before any terminal opens. The agent is not restarted when the server exits.

**Halt file.** When a restore brings back something broken, create the halt file and start a clean server. Restore on start stays off until the file is deleted. Point `@persist_revamped_halt_file` at `/tmp` to make the halt last only until the next boot on Linux, which clears `/tmp` at boot.

Session groups are not recreated. A grouped session comes back as a separate session with its own windows.

## Development

| Command | What it does |
|:--------|:-------------|
| `make test` | Runs the bats suite |
| `make lint` | Runs shellcheck on every shell file |
| `make coverage` | Measures line coverage with kcov and fails below 95 percent, on Linux |

The suite needs `bats-core` and tmux.

## License

[MIT](LICENSE)

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
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | Pick a URL, path, hash or any other token off the screen with fzf and type it at the cursor, in pure shell |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | Switch to, kill, rename or create tmux sessions, windows and panes from fzf pickers in a popup |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | Show the active pane's git branch, changes and provider counts in the tmux status bar without blocking it |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | GPU load, temperature, clock, power and memory in the tmux status bar, from NVIDIA, AMD, Intel and Apple GPUs |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | Current Kubernetes context and namespace in the tmux status bar, parsed from kubeconfig without kubectl |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | Launch any TUI app in a popup or a window, scoped to the current pane's directory, with one configurable bindi |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | Capture any pane to a file: live logging, full scrollback, or a one-shot screenshot |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | Now playing in your tmux status bar, without ever blocking the status render |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | Network throughput in your tmux status bar, without ever blocking the render |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | Pane and window management bindings for tmux, version aware, vim friendly, every prefix key can be disabled |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | **this plugin**, Save every tmux session, window and pane, auto-save on a timer, and restore it all after a reboot |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | The starting point for a tmux-revamped plugin: shared library, bats harness, CI and family tooling |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | A Pomodoro timer in the tmux status bar that keeps all of its state in tmux options, with no temp files |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | RAM, swap and memory pressure in the tmux status bar, sampled in the background so the render never waits |
| [`tmux-reorder-revamped`](https://github.com/tmux-revamped/tmux-reorder-revamped) | Drag a window tab along the tmux status bar with the mouse to move that window |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | Send the mouse wheel to apps that scroll themselves and into tmux copy-mode everywhere else |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | Sensible tmux defaults, gated by tmux version and terminal, that leave the options you set alone |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | Tiling window management for tmux: eight layouts including BSP dwindle and spiral, with layout undo |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | Local and world clocks for the tmux status bar, colored by time of day, with countdowns and a DST warning |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | Weather for the tmux status bar from wttr.in, fetched in the background so the status line never waits |

### Checking an installation

With every member on disk, one command reports any conflict between them:

```sh
family/bin/doctor --live
```

It reads each member and the running tmux server, and reports duplicate keys,
duplicate status placeholders, options outside the naming grammar, and any
member whose contract version has fallen behind.

<!-- family:end -->
