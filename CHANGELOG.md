# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `decaf version` / `--version`.
- Man page and bash completion.
- `Makefile` with `install` / `uninstall` (honours `PREFIX` and `DESTDIR`).
- `LICENSE` file (MIT), installed by the AUR package.

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
