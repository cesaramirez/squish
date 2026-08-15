# Using the squish GitHub Action

`squish` ships a reusable **composite GitHub Action** so you can optimize images
(resize + compress, with optional WebP/AVIF output) directly in your CI. Point a
workflow at `cesaramirez/squish@v0.2.0` and it will install the needed tools on
the runner (`pngquant`, `imagemagick`, `webp`, `oxipng`) and run squish over the
images you select.

## Quick start

Add the following to **your** repository at
`.github/workflows/optimize-images.yml`:

```yaml
name: Optimize images

on:
  pull_request:
    paths:
      - "assets/**/*.png"

permissions:
  contents: write

jobs:
  squish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Optimize images
        uses: cesaramirez/squish@v0.2.0
        with:
          files: "assets/**/*.png"
          webp: "true"

      - name: Commit optimized images
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "chore: optimize images with squish"
```

On every PR that touches `assets/**/*.png`, this:

1. Checks out the PR branch.
2. Installs the image tooling and runs squish, resizing/compressing each matched
   PNG and emitting a `.webp` sibling next to it.
3. Commits any resulting changes back to the PR branch via
   [`git-auto-commit-action`](https://github.com/stefanzweifel/git-auto-commit-action).

> **Tip:** `permissions: contents: write` is required for the auto-commit step to
> push back to the branch. If you'd rather run squish as a **read-only check**
> (fail nothing, just optimize in the workflow without committing), drop the
> `permissions` block and the `git-auto-commit-action` step.

## Example: resize + WebP + AVIF

```yaml
      - name: Optimize hero images
        uses: cesaramirez/squish@v0.2.0
        with:
          files: "assets/heroes/**/*.png"
          width: "1200"
          webp: "true"
          avif: "true"
```

## Example: pass extra raw args

Anything squish accepts can be forwarded via `args`:

```yaml
      - name: Optimize with a custom output dir
        uses: cesaramirez/squish@v0.2.0
        with:
          files: "src/img/**/*.png"
          args: "--out-dir dist"
```

## Inputs

| Input   | Default      | Description                                                                 |
| ------- | ------------ | --------------------------------------------------------------------------- |
| `files` | `**/*.png`   | Glob of images to optimize. Expanded with bash `globstar` + `nullglob`.     |
| `width` | `""`         | Optional resize width in px. Passed as `-w <width>` only when non-empty.    |
| `webp`  | `"false"`    | When `"true"`, emit a `.webp` sibling for each image (`--webp`).            |
| `avif`  | `"false"`    | When `"true"`, emit an `.avif` sibling for each image (`--avif`).           |
| `args`  | `""`         | Extra raw args passed straight through to `squish.sh`.                       |

## Notes

- The action runs on **Linux runners** (`ubuntu-latest`); the dependency install
  step uses `apt` and downloads the Linux `oxipng` binary.
- `webp` and `avif` inputs are strings — quote them as `"true"` / `"false"`.
- If the `files` glob matches nothing, the action exits successfully without
  doing any work.
