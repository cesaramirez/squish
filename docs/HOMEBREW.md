# Installing `squish` via Homebrew

`squish` is distributed through a Homebrew **tap** (a third-party formula repo).

## For users

Install in one line:

```sh
brew install heycesar/tap/squish
```

That shorthand implicitly taps `heycesar/homebrew-tap` and installs the
`squish` formula from it. If you prefer the explicit two-step form:

```sh
brew tap heycesar/tap
brew install squish
```

Upgrade later with:

```sh
brew upgrade squish
```

### Dependencies

Homebrew pulls in the required optimizers automatically (`pngquant`,
`oxipng`). `imagemagick` is installed by default as a recommended dependency;
`webp` and `jq` are optional. To install without the recommended extras:

```sh
brew install --without-imagemagick heycesar/tap/squish
```

## For the maintainer (César)

The live formula lives in a **separate public repo** named `homebrew-tap`
under the `heycesar` account. Homebrew requires the repo to be named
`homebrew-<tap>`, so `heycesar/tap` resolves to
`github.com/heycesar/homebrew-tap`.

### 1. Create the tap repo

Create a public repo `heycesar/homebrew-tap` on GitHub (empty), then:

```sh
git clone https://github.com/heycesar/homebrew-tap.git
cd homebrew-tap
mkdir -p Formula
```

### 2. Copy the formula and fill in the checksum

Copy `Formula/squish.rb` from this repo into the tap, then compute the real
`sha256` for the release tarball and replace the `REPLACE_WITH_SHA256`
placeholder:

```sh
curl -sL https://github.com/heycesar/squish/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
```

Paste the resulting hash into the `sha256 "..."` line of `Formula/squish.rb`.

### 3. Commit and push

```sh
git add Formula/squish.rb
git commit -m "feat: add squish formula v0.1.0"
git push origin main
```

### 4. Verify

```sh
brew install heycesar/tap/squish
brew test squish
brew audit --strict --online heycesar/tap/squish
```

### Releasing a new version

1. Tag and publish a new release in the `squish` repo (e.g. `v0.2.0`).
2. In `homebrew-tap`, bump `url`/`version` in `Formula/squish.rb` and
   recompute the `sha256` with the command above.
3. Commit and push.

## Source of truth

The `Formula/squish.rb` in **this** repo (`squish`) is a template / source of
truth kept alongside the code. The formula Homebrew actually installs from is
the copy in the `heycesar/homebrew-tap` repo. When you change the template
here, mirror the change into the tap repo (and vice versa).
