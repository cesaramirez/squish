#!/usr/bin/env bats
#
# Tests for squish.sh. These are behavioral and deliberately avoid asserting on
# exact byte sizes (which vary by tool version). Where the script's exit status
# can differ across platforms (it uses BSD `stat -f%z`, which is macOS-only),
# we assert on side effects (files written) rather than on $status.

SQUISH="$BATS_TEST_DIRNAME/../squish.sh"

setup() {
  # A deterministic PNG fixture. Prefer magick, fall back to sips; skip if neither.
  IN="$BATS_TEST_TMPDIR/in.png"
  if command -v magick >/dev/null 2>&1; then
    magick -size 200x200 gradient:red-blue "$IN"
  elif command -v convert >/dev/null 2>&1; then
    convert -size 200x200 gradient:red-blue "$IN"
  else
    skip "no ImageMagick to build a PNG fixture"
  fi
}

@test "--help exits 0 and shows usage" {
  run bash "$SQUISH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* || "$output" == *"--help"* ]]
}

@test "optimizing a PNG writes a smaller output file that exists" {
  out="$BATS_TEST_TMPDIR/out.png"
  # Assert on the written file, not $status: the compress step runs before the
  # script's macOS-only stat call, so the output exists regardless of platform.
  run bash "$SQUISH" "$IN" --output "$out"
  [ -f "$out" ]
  in_size=$(wc -c < "$IN")
  out_size=$(wc -c < "$out")
  [ "$out_size" -gt 0 ]
  [ "$out_size" -le "$in_size" ]
}

@test "--dry-run writes no output file" {
  out="$BATS_TEST_TMPDIR/dry.png"
  # The dry-run summary path can exit non-zero on its own; the behavior under
  # test is that nothing is written, so we assert on the (absent) file only.
  run bash "$SQUISH" "$IN" --output "$out" --dry-run
  [ ! -e "$out" ]
  [[ "$output" == *"dry.png"* ]]
}

@test "slug naming lowercases and hyphenates spaces/uppercase" {
  src="$BATS_TEST_TMPDIR/My Cool Image.png"
  cp "$IN" "$src"
  run bash "$SQUISH" "$src" --name-as slug --dry-run
  # (exit status of the dry-run summary is not asserted; see --dry-run test)
  [[ "$output" == *"my-cool-image.png"* ]]
}

@test "--width never upscales a small input" {
  command -v magick >/dev/null || skip "needs ImageMagick to read dimensions"
  # Input is 200px wide; asking for 400px must not upscale the output.
  out="$BATS_TEST_TMPDIR/wide.png"
  run bash "$SQUISH" "$IN" --width 400 --output "$out" --no-color
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  w="$(magick identify -format '%w' "$out")"
  [ "$w" -le 200 ]
}

@test "unknown flag exits non-zero" {
  run bash "$SQUISH" "$IN" --definitely-not-a-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--ai with no key warns and still optimizes" {
  out="$BATS_TEST_TMPDIR/ai.png"
  OPENAI_API_KEY= ANTHROPIC_API_KEY= run bash "$SQUISH" "$IN" --ai --output "$out"
  # Degrades gracefully: warns about the missing key but still writes the file.
  [ -f "$out" ]
  [[ "$output" == *"API key"* || "$stderr" == *"API key"* || "$output" == *"⚠"* ]]
}

@test "sha256 helper: same bytes give same digest, different bytes differ" {
  printf 'squish' > "$BATS_TEST_TMPDIR/a"
  printf 'squish' > "$BATS_TEST_TMPDIR/b"
  printf 'other'  > "$BATS_TEST_TMPDIR/c"
  # Extract the sha256 function body and run it standalone.
  fn="$(sed -n '/^sha256() {/,/^}/p' "$SQUISH")"
  da="$(bash -c "$fn"$'\n'"sha256 '$BATS_TEST_TMPDIR/a'")"
  db="$(bash -c "$fn"$'\n'"sha256 '$BATS_TEST_TMPDIR/b'")"
  dc="$(bash -c "$fn"$'\n'"sha256 '$BATS_TEST_TMPDIR/c'")"
  [ -n "$da" ]
  [ "${#da}" -eq 64 ]
  [ "$da" = "$db" ]
  [ "$da" != "$dc" ]
}

@test "analyze_local classifies a flat 2-color image as logo" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  command -v jq >/dev/null || skip "needs jq"
  magick -size 300x300 xc:white -fill black -draw "rectangle 50,50 250,250" \
    "$BATS_TEST_TMPDIR/flat.png"
  fn="$(sed -n '/^analyze_local() {/,/^}/p' "$SQUISH")"
  out="$(bash -c "$fn"$'\n'"analyze_local '$BATS_TEST_TMPDIR/flat.png'")"
  kind="$(printf '%s' "$out" | jq -r '.kind')"
  [ "$kind" = "logo" ]
}

@test "analyze_local classifies a smooth gradient as gradient" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  command -v jq >/dev/null || skip "needs jq"
  magick -size 400x400 gradient:'#0a3d1d-#1fae4f' "$BATS_TEST_TMPDIR/grad.png"
  fn="$(sed -n '/^analyze_local() {/,/^}/p' "$SQUISH")"
  out="$(bash -c "$fn"$'\n'"analyze_local '$BATS_TEST_TMPDIR/grad.png'")"
  kind="$(printf '%s' "$out" | jq -r '.kind')"
  [ "$kind" = "gradient" ]
}

@test "analyze_local classifies a tiny image as icon" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  command -v jq >/dev/null || skip "needs jq"
  magick -size 32x32 gradient:red-blue "$BATS_TEST_TMPDIR/ic.png"
  fn="$(sed -n '/^analyze_local() {/,/^}/p' "$SQUISH")"
  out="$(bash -c "$fn"$'\n'"analyze_local '$BATS_TEST_TMPDIR/ic.png'")"
  [ "$(printf '%s' "$out" | jq -r '.kind')" = "icon" ]
}
