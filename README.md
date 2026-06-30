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
