# squish

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Shell](https://img.shields.io/badge/shell-bash-121011.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)

A tiny, fast image optimizer for the terminal — resize, compress, and rename
images while keeping transparency. Output stays **PNG** for maximum
compatibility (Outlook desktop, older webmails, everything), with an optional
**WebP** sibling. Optionally uses **vision AI** (OpenAI or Claude) to suggest a
semantic filename, alt text, optimal parameters, and a ready-to-paste HTML
snippet — tuned per context (email signature, web, hero, icon, avatar).

![squish in action](demo.png)

No banding on gradients, no bloated files, no `%20` in your URLs.

## Why

Most "optimize this image" advice stops at compression. The biggest win is
almost always **shipping the image at its display size** — a 1000px asset shown
at 200px is wasting 96% of its bytes no matter how well you compress it. `squish`
does both, keeps the file email/web-safe, and gives it a clean URL-safe name.

## Install

One-liner (copies `squish` to a bin dir on your `PATH` and checks deps):

```bash
curl -fsSL https://raw.githubusercontent.com/cesaramirez/squish/main/install.sh | bash
```

Or do it by hand. Requires **pngquant** and **oxipng**; optional tools unlock
extra flags.

**macOS** (with [Homebrew](https://brew.sh)):

```bash
brew install pngquant oxipng
brew install webp jq        # optional: --webp and --ai
```

**Linux** (Debian/Ubuntu):

```bash
sudo apt install pngquant webp jq
# oxipng: cargo install oxipng   (or grab a release binary)
```

Then put `squish.sh` on your `PATH`:

```bash
chmod +x squish.sh
ln -sf "$(pwd)/squish.sh" /opt/homebrew/bin/squish   # macOS (Apple Silicon)
# or
ln -sf "$(pwd)/squish.sh" /usr/local/bin/squish      # macOS Intel / Linux

squish --help
```

| Tool | Needed for | Required? |
|------|-----------|:---------:|
| `pngquant` | palette compression | ✅ |
| `oxipng` | lossless recompression | ✅ |
| `sips` | `--width` / `--retina` (ships with macOS) | optional |
| `cwebp` | `--webp` (`brew install webp`) | optional |
| `curl` + `jq` | `--ai` (vision analysis) | optional |

> On Linux, `sips` doesn't exist, so `--width`/`--retina` are macOS-only for now.
> Everything else is cross-platform.

## Usage

```bash
squish image.png                          # → image.png (URL-safe slug name)
squish image.png -w 400                    # resize to 400px wide, then compress
squish image.png --retina --display 200    # 2× of a 200px display size → 400px
squish image.png --webp                    # also write a .webp sibling
squish *.png -w 400 --out-dir dist         # batch into ./dist/
squish photo.jpg --ai                      # AI: suggest name / alt / params / html
squish arc.png --ai --context email-signature --apply
```

The output shows, per file: before→after dimensions, a savings bar, the byte
sizes, the `.webp` if any, and a final total. Color turns off automatically when
piped or in CI.

### Options

| Flag | What it does |
|------|--------------|
| `-w, --width N`     | Resize to N px wide (keeps aspect ratio). **The biggest win** — ship at ~2× display size. Never upscales past the source. |
| `-r, --retina`      | With `--display`, targets 2× that width. Shorthand for `--width`. |
| `--display N`       | Intended on-screen width (px). With `--retina`, resizes to `2×N`. |
| `-c, --colors N`    | Palette size (default 128). Lower = smaller & more banding. 128 ≈ no visible loss; 64 = aggressive. |
| `--webp`            | Also emit a `.webp` (~40% smaller). Needs a `<picture>` fallback — Outlook can't read WebP. |
| `-d, --out-dir DIR` | Write all outputs into DIR (created if missing). |
| `-o, --output F`    | Explicit output path (single input; overrides naming). |
| `--name-as WHAT`    | How to name outputs (see below). Default: `slug`. |
| `--rename NAME`     | Replace the base name entirely (single input; slugified). |
| `--ai`              | Analyze the image with vision AI and print suggestions (see AI section). |
| `--ai-provider P`   | `auto` (default) / `openai` / `anthropic`. `auto` uses whichever key is set. |
| `--context WHAT`    | What the image is for: `general` (default) / `email-signature` / `web` / `hero` / `icon` / `avatar`. |
| `--ai-fields L`     | Comma list of fields to request (default `name,alt,params,html`). |
| `--apply`           | Apply the AI-suggested name automatically (implies `--ai`). |
| `--ai-model M`      | Model override (default `gpt-4o-mini` / `claude-haiku-4-5`). |
| `--no-color`        | Disable color (also respects `NO_COLOR`). |
| `-q, --quiet`       | Only print the per-file result lines. |
| `-h, --help`        | Help. |

### Output naming (`--name-as`)

With `"forma_derecha 1.png"` and `-w 400`:

| Value | Result | Use |
|-------|--------|-----|
| `slug` (default) | `forma-derecha-1.png` | **URL-safe** (no spaces/accents/uppercase) |
| `optimized` | `forma_derecha 1.optimized.png` | keeps the original name + suffix |
| `plain` | `forma_derecha 1.png` | original name as-is |
| `retina` | `forma-derecha-1@2x.png` | for `srcset` / retina |
| `width` | `forma-derecha-1-400w.png` | multiple widths |

> Never overwrites the source: if the output name collides with the input in the
> same folder, it appends `-min` (e.g. `logo.png` → `logo-min.png`).

`--rename` replaces the base name completely:

```bash
squish "forma_derecha 1.png" --retina --display 200 \
  --rename signature-arc-right --name-as retina
#   → signature-arc-right@2x.png
```

> `slug`/`retina`/`width` clean the name for bucket/URL use: `Árbol Décor.png`
> becomes `arbol-decor.png`. Recommended whenever the image is served over HTTP —
> a space becomes `%20` and causes problems.

## AI analysis (`--ai`)

With `--ai`, after optimizing, the image is sent to a vision model that returns
structured JSON and prints it as suggestions:

```bash
squish arc.png -w 400 --ai --context email-signature
```

### Providers & keys

| Provider | Env var | Default model |
|----------|---------|---------------|
| OpenAI | `OPENAI_API_KEY` | `gpt-4o-mini` |
| Anthropic | `ANTHROPIC_API_KEY` | `claude-haiku-4-5` |

By default (`--ai-provider auto`) it uses **OpenAI if `OPENAI_API_KEY` is set**,
otherwise Anthropic. Force one with `--ai-provider openai|anthropic`. Both are
cheap for this task (classifying one small image). If no key or tools are
present, `--ai` warns and skips — **the optimization still runs**.

```bash
export OPENAI_API_KEY="sk-..."        # or ANTHROPIC_API_KEY
squish photo.jpg --ai                 # suggest only
squish photo.jpg --ai --apply         # apply the suggested name
squish arc.png --ai --context web     # HTML tuned for web (<picture> + webp)
squish icon.png --ai --ai-fields name,alt
```

### What it returns (`--ai-fields`)

| Field | What it is |
|-------|------------|
| `name` | URL-safe semantic slug. With `--apply`, becomes the output name. |
| `alt` | Alt text for the `<img>` (accessibility). |
| `params` | Classifies the image (photo/logo/gradient/…) and suggests `--colors` and whether `--webp` helps. |
| `html` | Ready-to-paste HTML snippet, tuned to `--context`. |

> **Security**: keys are read from the environment, never stored in the script or
> printed. Don't commit keys — use a git-ignored `.env`/`.dev.vars`, or export
> them in your shell.

## Recommended for email signatures

- Export the image at **~2× its on-screen width** (shown at 200px → `-w 400`).
- Put the display width in the HTML: `<img src="..." width="200">` — crisp on
  retina.
- Serve it with a long cache: `Cache-Control: public, max-age=31536000, immutable`.
- Keep the output PNG — Outlook desktop and several webmails don't render WebP.

Real example: a 1016 KB / 1154px asset → **40 KB** at `-w 400` (−96%).

## How it works

1. Optional resize with `sips` (never upscales).
2. Lossy palette quantization with `pngquant` (keeps alpha, strips metadata).
3. Lossless recompression with `oxipng -o max`.
4. Optional WebP sibling with `cwebp`.
5. Optional AI pass: sends the resized image to the vision model with a strict
   JSON schema and prints the suggestions.

## License

[MIT](LICENSE) © César
