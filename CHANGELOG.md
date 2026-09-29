# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

A ground-up rewrite. **Not compatible with 1.x**: commands, arguments and
output all changed.

### Changed

- Commands are now `on DURATION`, `off` and `status` (were `start`, `stop`,
  `status`).
- `DURATION` is whole seconds, from 1 (was minutes by default, with units).
- `status` prints `key=value` lines (`state`, `duration`, `started`, `until`,
  `remaining`) and exits 0 when a timer is on, 1 when not.
- Every outcome has its own exit status: 1 no timer, 2 usage error,
  3 timer already on, 4 system error. Errors go to stderr.
- `on` refuses to replace a running timer; `off` fails when there is none.
- A timer is one transient user unit, `app-decaf.service`, whose process waits
  for the deadline and suspends; the separate systemd timer unit is gone.
- The deadline is noticed within milliseconds, also right after a resume.
  A timer whose deadline passed while the system was asleep is skipped
  (was: skipped only when noticed more than 30 s late).
- Notifications come from the timer unit: set, skipped, turned off, failed.
  Commands send none themselves.
- Overriding another program's blocking lock at the deadline asks for your
  password (polkit); unanswered, the timer fails after 25 s.
- Dependencies: adds `glib2` (for `gdbus`); drops `rofi`.

### Added

- "Suspending soon" notification a minute before the deadline, or at once when
  resuming within that last minute.
- `--version`.
- Man page and bash completion.
- `Makefile` with `install` / `uninstall` (honours `PREFIX` and `DESTDIR`).
- `LICENSE` file (MIT), installed by the AUR package.

### Removed

- The `menu` command (rofi). A redesigned menu is planned for a later release.
- `help` command: use `--help`.

### Fixed

- `status` misreported the time left, depending on locale and date format.
- `stop` announced "Decaf Off" even when no timer was running.
- Errors from `systemd-run` were hidden.
- Durations like `5x` were silently taken as 5 minutes.

## [1.0.5] - 2026-07-25

### Fixed

- No longer suspends right after waking up when the timer expired while the
  system was asleep.

## [1.0.4] - 2026-07-25

### Fixed

- Timers use an absolute wall-clock time (#1).

## [1.0.3] - 2026-06-23

### Changed

- Renamed to decaf.

## [1.0.2] - 2026-06-23

### Changed

- The menu accepts any time format.

## [1.0.1] - 2026-06-23

### Changed

- Updated texts.

## [1.0.0] - 2026-06-23

- Initial release.
