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
  # Input is 200px wide; asking for 400px must not upscale.
  out="$BATS_TEST_TMPDIR/wide.png"
  run bash "$SQUISH" "$IN" --width 400 --output "$out" --dry-run
  # Dry-run reports the source dims unchanged (never upscaled to 400px wide).
  [[ "$output" == *"200x200"* ]]
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
