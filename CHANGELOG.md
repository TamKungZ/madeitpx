# Changelog

Notable changes to `madeitpx` are documented here.

## [0.1.2] - 2026-10-30

### Fixed

- Corrected the Node.js binding's native package names.

### Changed

- Added binding tests to release verification and stopped waiting for Maven Central publication to finish.

## [0.1.1] - 2026-10-17

### Fixed

- Fixed the release workflow getting stuck in `release.yml`.
- Added a GPG detached signature for `SHA256SUMS.txt` release checksums.

## [0.1.0] - 2026-10-17

### Added

- RGBA8 image conversion through a C-compatible API.
- Nearest-neighbor and area sampling modes.
- Configurable palette limits, background compositing, and optional cluster cleanup.
- Official image-pattern regression tests and generated previews.
