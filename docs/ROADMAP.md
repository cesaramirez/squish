# Roadmap / deferred work

Items surfaced but intentionally deferred, mostly from the v0.5.1 cross-cutting
audit. None are release-blocking; grouped by theme.

## v0.6 — testing & CI hardening (the structural gap)

The audit's biggest finding: **macOS/BSD code paths have never run in CI** across
6 releases (CI is `ubuntu-latest` only), and several shipped features have zero
test coverage. This is where real bugs hide (C1/C2 in v0.5.1 lived here).

- [ ] **macOS CI job.** Add a `macos-latest` leg to `.github/workflows/ci.yml` so
      the `sips` / BSD `stat -f` / `shasum` paths are exercised on every push.
- [ ] **doctest the `--help` examples.** Execute every command in the Usage block
      of `squish.sh` as a real user would (in both bash AND zsh) and assert none
      error. This class of bug — a documented example that breaks when copy-pasted
      (`[output.png]` was a zsh glob) or was never even supported — is invisible
      to "does the help mention the right flags?" review. Only running each
      snippet catches it. The audit checked presence/accuracy, not executability.
- [ ] **JPEG / AVIF coverage.** No `.jpg`/`.jpeg` fixture exists; the `compress_to`
      JPEG branch, `--jpeg-quality`, and `make_avif` are untested by any real
      invocation.
- [ ] **AI HTTP paths.** `ai_openai` / `ai_anthropic` (request build, response
      parse, error handling, provider/model resolution) have no test — not even a
      mocked `curl`/local stub. Highest-risk shipped code with zero coverage.
- [ ] **`--retina`/`--display`, `--name-as` variants, `--rename` (real flag),
      dependency-missing `die` paths** — all untested.
- [ ] **install.sh executed in CI** (currently only shellchecked), and the
      Homebrew formula / GitHub Action referenced by CI at all.

## Security hardening (minor, from the audit)

- [ ] **API key off curl argv.** Keys are passed as `-H "authorization: Bearer
      $AI_KEY"` (visible in `ps` on multi-user hosts). Move to `curl --config`
      via stdin. (Near-zero risk on a single-user laptop; matters on shared CI.)
- [ ] **`sed SRC` substitution** in the AI `html` field uses an un-slugified
      basename; a `|` in a `--name-as plain` filename garbles the HTML (not RCE —
      the trailing `.png|g` breaks any exec payload). Escape it or use `${v//…}`.

## Correctness (minor)

- [ ] **`mktemp -t` literal `XXXXXX` on BSD.** `mktemp -t squish.XXXXXX` treats
      `XXXXXX` as a prefix on BSD (not a placeholder), littering `$TMPDIR`. Use
      `mktemp "${TMPDIR:-/tmp}/squish.XXXXXX"`.
- [ ] **`set -e` footgun at the "not a file" branch** (`(( FAIL_COUNT++ ))` returns
      falsy at 0). Safe today only because the call site uses `|| true`; fragile.
      Use `FAIL_COUNT=$(( FAIL_COUNT + 1 ))`.
- [ ] **JPEG that grows** still reports "optimized" with a negative percentage.
      Consider keeping the original when the result is larger.
- [ ] **`--out-dir` inside a watched `-R` tree** has no guard (the GENERATED filter
      handles the common case; an unusual nesting is an untested corner).

## Features (from the original brainstorm, never built)

- [ ] **Batch (B): coherent cross-image naming** — let the AI see the whole set at
      once so names are consistent across a batch, not per-file.

---

Last updated after the v0.5.1 audit. See CHANGELOG.md for shipped work.
