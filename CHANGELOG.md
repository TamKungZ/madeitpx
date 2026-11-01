# Changelog

Notable changes to `madeitpx` are documented here.

## [0.2.1] - 2026-11-02

### Added

- Added version 2 of the `pixelart` preset, which recovers the real pixel grid of scaled-up
  pixel art, and `madeitpx_convert_pixelart_rgba8` with detailed settings and per-field reset.
  Version 1 stays available (`version = 1`) and remains what `preset = 3` runs in `madeitpx_convert_rgba8`.

## [0.2.0] - 2026-10-31

### Added

- Added the `pixelart` preset for structure-first conversion that preserves dark
  outlines, bridges short line gaps, and removes isolated or one-cell regions.
- Added a Python reference prototype and documentation for the pixel-art
  conversion pipeline.

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
