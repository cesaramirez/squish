# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- JPEG input and output support, optimized with ImageMagick (progressive, tuned quality).
- AVIF output via `--avif` (~50% smaller sibling; needs ImageMagick with AVIF support).
- `--dry-run` mode: show what would happen (names, sizes) without writing any files.
- `--jpeg-quality N` to set JPEG output quality (1–100, default 82).

### Changed

- Resizing is now cross-platform: uses `sips` on macOS and ImageMagick elsewhere
  (previously `--width` / `--retina` were macOS-only).

## [0.1.0] - 2026-08-14

### Added

- PNG optimization: lossy palette quantization with `pngquant` followed by
  lossless recompression with `oxipng -o max`, transparency preserved.
- Resize with retina awareness (`--width`, `--retina`, `--display`); never upscales.
- Optional WebP sibling output via `--webp`.
- URL-safe slug naming (spaces, accents, and uppercase cleaned) with several
  naming modes via `--name-as`.
- Vision-AI analysis via `--ai` (OpenAI and Anthropic) suggesting a semantic
  filename, alt text, optimal parameters, and a ready-to-paste HTML snippet.

[Unreleased]: https://github.com/cesaramirez/squish/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cesaramirez/squish/releases/tag/v0.1.0
