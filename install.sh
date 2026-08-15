#!/usr/bin/env bash
#
# install.sh — installer for squish.
#
#   curl -fsSL https://raw.githubusercontent.com/heycesar/squish/main/install.sh | bash
#
# Copies squish.sh to a bin dir on your PATH and checks dependencies.
# Override the target with:  PREFIX=~/.local/bin bash install.sh

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/heycesar/squish/main/squish.sh"

bold=$'\033[1m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s⚠%s %s\n' "$yellow" "$reset" "$*"; }
die()  { printf '%s✗%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

# --- pick an install dir on PATH ----------------------------------------------
pick_prefix() {
  [[ -n "${PREFIX:-}" ]] && { printf '%s' "$PREFIX"; return; }
  local d
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in *":$d:"*) [[ -d "$d" && -w "$d" ]] && { printf '%s' "$d"; return; } ;; esac
  done
  # fall back to ~/.local/bin, creating it
  printf '%s' "$HOME/.local/bin"
}

PREFIX="$(pick_prefix)"
mkdir -p "$PREFIX"

# --- fetch the script (or use a local copy) -----------------------------------
tmp="$(mktemp)"
if [[ -f "$(dirname "$0")/squish.sh" ]]; then
  cp "$(dirname "$0")/squish.sh" "$tmp"           # running from a clone
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_RAW" -o "$tmp" || die "download failed: $REPO_RAW"
else
  die "need curl (or run this from a cloned repo)"
fi

install -m 0755 "$tmp" "$PREFIX/squish"
rm -f "$tmp"
ok "installed ${bold}squish${reset} to $PREFIX/squish"

# --- dependency check ---------------------------------------------------------
say ""
say "${bold}Dependencies${reset}"
have() { command -v "$1" >/dev/null 2>&1; }
req_missing=0
for t in pngquant oxipng; do
  if have "$t"; then ok "$t"; else warn "$t (required) — missing"; req_missing=1; fi
done
for t in sips cwebp jq; do
  if have "$t"; then ok "$t"; else say "  $t (optional) — not found"; fi
done

if (( req_missing )); then
  say ""
  if have brew; then warn "install required tools: ${bold}brew install pngquant oxipng${reset}"
  else warn "install pngquant and oxipng, then re-run"; fi
fi

# --- PATH hint ----------------------------------------------------------------
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) say ""; warn "$PREFIX is not on your PATH. Add to your shell rc:"
     say "     export PATH=\"$PREFIX:\$PATH\"" ;;
esac

say ""
ok "Done. Try: ${bold}squish --help${reset}"
