# Contributing to squish

Thanks for helping out. `squish` is a single bash script, so contributing is
low-ceremony: clone, edit `squish.sh`, run the checks, open a PR.

## Local setup

```bash
git clone https://github.com/cesaramirez/squish.git
cd squish
chmod +x squish.sh
ln -sf "$(pwd)/squish.sh" /opt/homebrew/bin/squish   # macOS (Apple Silicon)
# or
ln -sf "$(pwd)/squish.sh" /usr/local/bin/squish      # macOS Intel / Linux

squish --help
```

## Development dependencies

The runtime only needs `pngquant` and `oxipng`; optional tools unlock extra
flags. For development you'll also want the linter and test runner.

**macOS** (with [Homebrew](https://brew.sh)):

```bash
brew install pngquant oxipng imagemagick jq   # runtime + optional
brew install shellcheck bats-core             # dev tooling
```

**Linux** (Debian/Ubuntu):

```bash
sudo apt install pngquant imagemagick jq shellcheck bats
# oxipng: cargo install oxipng   (or grab a release binary)
```

| Tool | Needed for |
|------|-----------|
| `pngquant`, `oxipng` | core PNG pipeline (required) |
| `imagemagick` | resize (cross-platform), JPEG, AVIF |
| `jq` | `--ai` (parsing the model's JSON) |
| `shellcheck` | linting |
| `bats` | the test suite |

## Running the checks

Before you push, run the same checks CI does:

```bash
shellcheck -S warning squish.sh   # lint
bash -n squish.sh                 # syntax-only parse
bats tests/                       # test suite
```

## Code style

`squish` is one bash script — keep it that way.

- Stay POSIX-ish bash. Keep the `set -euo pipefail` at the top intact.
- Functions are `lowercase_with_underscores`.
- Match the surrounding style: the existing indentation, quoting, and the
  header comment block that documents every flag (keep it in sync when you add
  or change a flag).
- **Degrade gracefully.** Optional tools that are missing should warn and skip,
  never abort — the core optimization must still run. `--webp`, `--avif`, and
  `--ai` all follow this rule; new optional features should too.

## Submitting a change

1. Fork the repo and create a branch off `main`.
2. Make your change; keep the header comment and `--help` output accurate.
3. Run the checks above.
4. Open a PR against `main` with a clear description.

CI runs `shellcheck` and `bats` on every PR, so a green local run means a green
PR.

## A note on AI features

The `--ai` flags require an API key (`OPENAI_API_KEY` or `ANTHROPIC_API_KEY`),
read from the environment only. **Never commit keys** — use a git-ignored
`.env` / `.dev.vars` or export them in your shell. Keys must never be written
into the script, tests, fixtures, or logs.
