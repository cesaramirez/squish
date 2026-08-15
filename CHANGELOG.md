# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Recursive traversal: pass a directory with `-R`/`--recursive` to optimize every
  supported image inside it (any depth). Skips hidden dirs and non-images, never
  follows symlinks. With `--out-dir`, the source tree is mirrored into the target.

## [0.4.0] - 2026-08-15

### Added

- Project config: an optional `./.squishrc` (`key=value`) persists default flags
  per project. Precedence is CLI flags > `.squishrc` > built-in defaults. Parsed
  safely (never sourced); unknown keys and invalid values are warned and skipped.

## [0.3.0] - 2026-08-15

### Added

- `--ai` now works without an API key — local ImageMagick heuristic detects image kind (photo/logo/gradient/icon) and suggests optimal `--colors`, `--webp`, and `--avif` flags.
- Automatic context inference via `--context auto` (the default under `--ai`) — the model infers whether the image is an avatar, hero, icon, web image, email signature, or general.
- AI result caching by content hash (stored in `~/.cache/squish/`); `--no-cache` to bypass.
- `--apply` now works on batches; colliding output names get numeric suffixes (`name.png`, `name-2.png`, etc.).

### Fixed

- `--apply` batch collisions: when the AI suggests the same name for two images,
  the second no longer silently overwrites the first — it gets a numeric suffix.
- Local `--ai` (no key) now requires ImageMagick and warns instead of silently
  misclassifying every image when `magick` is absent (e.g. sips-only macOS).
- AI cache key now includes the provider, so switching providers with the same
  model name no longer returns a stale cross-provider result.

## [0.2.0] - 2026-08-15

### Added

- JPEG input and output support, optimized with ImageMagick (progressive, tuned quality).
- AVIF output via `--avif` (~50% smaller sibling; needs ImageMagick with AVIF support).
- `--dry-run` mode: show what would happen (names, sizes) without writing any files.
- `--jpeg-quality N` to set JPEG output quality (1–100, default 82).
- GitHub Actions CI (ShellCheck + bats), a reusable composite Action, a Homebrew
  formula, and contributor docs.

### Changed

- Resizing is now cross-platform: uses `sips` on macOS and ImageMagick elsewhere
  (previously `--width` / `--retina` were macOS-only).

### Fixed

- File size is read cross-platform (`stat -c%s` fallback for Linux).
- Divide-by-zero in the summary when nothing was written (e.g. `--dry-run`).

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

[Unreleased]: https://github.com/cesaramirez/squish/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/cesaramirez/squish/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/cesaramirez/squish/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cesaramirez/squish/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cesaramirez/squish/releases/tag/v0.1.0
