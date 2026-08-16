#!/usr/bin/env bats
# Keeps completions/ in sync with squish.sh's real flags and enumerated values.

SQUISH="$BATS_TEST_DIRNAME/../squish.sh"
ZSH_COMP="$BATS_TEST_DIRNAME/../completions/squish.zsh"
BASH_COMP="$BATS_TEST_DIRNAME/../completions/squish.bash"

@test "every long flag in squish.sh appears in both completion scripts" {
  # Canonical set: long flags from the arg-parse case (strip trailing ')').
  local flags
  flags="$(grep -oE '\-\-[a-z-]+\)' "$SQUISH" | sed 's/)//' | sort -u)"
  [ -n "$flags" ]
  local missing=0 f
  while IFS= read -r f; do
    grep -qE -- "${f}([^a-z-]|$)" "$ZSH_COMP"  || { echo "zsh completion missing: $f"  >&2; missing=1; }
    grep -qE -- "${f}([^a-z-]|$)" "$BASH_COMP" || { echo "bash completion missing: $f" >&2; missing=1; }
  done <<< "$flags"
  [ "$missing" -eq 0 ]
}

@test "enumerated values match squish.sh (name-as, context, ai-provider)" {
  # Extract each case's alternatives and assert each value is present in both scripts.
  check_values() {
    local values="$1"; shift
    local v
    for v in $values; do
      grep -qE -- "${v}([^a-z-]|$)" "$ZSH_COMP"  || { echo "zsh missing value: $v"  >&2; return 1; }
      grep -qE -- "${v}([^a-z-]|$)" "$BASH_COMP" || { echo "bash missing value: $v" >&2; return 1; }
    done
  }
  check_values "slug optimized plain retina width"
  check_values "auto general email-signature web hero icon avatar"
  check_values "openai anthropic"   # 'auto' already covered above
}

@test "bash completion parses" {
  bash -n "$BASH_COMP"
}

@test "zsh completion parses" {
  command -v zsh >/dev/null || skip "zsh not installed on this runner"
  zsh -n "$ZSH_COMP"
}
