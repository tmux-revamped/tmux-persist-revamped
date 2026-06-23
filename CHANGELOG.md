# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-19

### Added

- Async, temp-file-free value cache backed by tmux server user-options. The hot
  path reads a cached option and returns instantly; a detached worker recomputes
  stale values in the background, so the status render never blocks.
- Stampede-guarded background refresh with a dead-worker timeout.
- Platform detection with memoized `uname` and macOS, Linux, and BSD predicates.
- tmux option get, set, and unset helpers.
- Opt-in structured logging under `~/.tmux`, off by default.
- Command availability probe.
- bats test harness with an in-memory tmux mock for unit tests and a real-socket
  harness for integration tests.
- Makefile targets for `test`, `test-unit`, `coverage`, and `lint`.
- CI matrix across Ubuntu and macOS, a shellcheck lint job, and a kcov coverage
  job that enforces a 95% line-coverage floor.
