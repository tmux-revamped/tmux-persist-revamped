<div align="center">

<h1>tmux-plugin-template</h1>

**A template for building non-blocking tmux status plugins.**

[![Tests](https://github.com/gufranco/tmux-plugin-template/actions/workflows/tests.yml/badge.svg)](https://github.com/gufranco/tmux-plugin-template/actions/workflows/tests.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

**54** tests · **95%+** coverage · **2** platforms · **0** temp files

This is the shared foundation for the `tmux-*-revamped` status plugins. It provides an async, temp-file-free cache that keeps all state in tmux server user-options, so the status bar reads a cached value instantly while a detached worker recomputes stale values in the background. It also ships platform helpers, a bats test harness that runs on bash 3.2, kcov coverage tooling, and CI.

<table>
<tr>
<td width="50%">

### Non-blocking cache

The hot path reads a cached tmux user-option and returns at once; a detached worker recomputes the value when it goes stale.

</td>
<td width="50%">

### No temp files

All state lives in tmux server options, so nothing touches the filesystem.

</td>
</tr>
<tr>
<td width="50%">

### bash 3.2 compatible

The test harness runs on the macOS system bash without a newer interpreter.

</td>
<td width="50%">

### Coverage enforced

CI runs a kcov gate that fails below 95%.

</td>
</tr>
</table>

## Use this template

On GitHub, click "Use this template" to generate a new repository from this one, or run `gh repo create <owner>/tmux-<metric>-revamped --template <owner>/tmux-plugin-template`.

A plugin built from the template follows the layout the shared core expects: source the cache from [`src/lib/utils/cache.sh`](src/lib/utils/cache.sh), set a `CACHE_PREFIX` to namespace its options, add per-platform parsers under [`src/lib`](src/lib), and add one bats file per module under [`test/`](test) at 95%+ coverage. See [`examples/`](examples) for a worked dispatcher and worker.

## Structure

The shared shell modules live under [`src/`](src) and their tests under [`test/`](test).

```
src/
  lib/
    tmux/
      tmux-ops.sh        tmux option get, set, and unset
    utils/
      cache.sh           async, temp-file-free cache
      platform.sh        memoized OS detection
      has-command.sh     command availability probe
      error-logger.sh    opt-in logging, off by default
      constants.sh       shared defaults
test/                    bats suites, helpers, and tmux mock
examples/                worked dispatcher and worker
.github/                 Tests workflow and CI
Makefile                 test, lint, and coverage targets
```

## Development

| Command | Description |
|---------|-------------|
| `make test` | Run the full test suite |
| `make test-unit` | Run unit tests only |
| `make coverage` | Measure line coverage with kcov and enforce the minimum, Linux only |
| `make lint` | Run shellcheck on all shell files |
| `make clean` | Remove coverage and temp artifacts |
| `make help` | Show available targets |

## License

[MIT](LICENSE), copyright Gustavo Franco.
