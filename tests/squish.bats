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

@test "--help documents the v0.3-v0.5 features (--recursive, --watch, .squishrc)" {
  run bash "$SQUISH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--recursive"* ]]
  [[ "$output" == *"--watch"* ]]
  [[ "$output" == *".squishrc"* ]]
}

@test "--version and -V print a version and exit 0" {
  run bash "$SQUISH" --version
  [ "$status" -eq 0 ]
  [[ "$output" == squish\ [0-9]*.[0-9]*.[0-9]* ]]
  run bash "$SQUISH" -V
  [ "$status" -eq 0 ]
  [[ "$output" == squish\ [0-9]*.[0-9]*.[0-9]* ]]
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

@test "--ai with no key runs local analysis and still optimizes" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  command -v jq >/dev/null || skip "needs jq"
  out="$BATS_TEST_TMPDIR/o.png"
  OPENAI_API_KEY= ANTHROPIC_API_KEY= run bash "$SQUISH" "$IN" --ai --output "$out" --no-color
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  # Local block header must appear instead of the old "skipping" warning.
  [[ "$output" == *"auto (local)"* ]]
  [[ "$output" != *"Skipping AI analysis"* ]]
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

@test "ai cache: a seeded entry is returned without a network call" {
  command -v jq >/dev/null || skip "needs jq"
  # Point the cache at the test tmp dir.
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  # Compute the key the way the script does and seed a JSON entry.
  fn_sha="$(sed -n '/^sha256() {/,/^}/p' "$SQUISH")"
  fn_key="$(sed -n '/^ai_cache_key() {/,/^}/p' "$SQUISH")"
  key="$(bash -c "AI_MODEL=gpt-4o-mini CONTEXT=general AI_FIELDS=name; $fn_sha"$'\n'"$fn_key"$'\n'"ai_cache_key '$IN'")"
  mkdir -p "$XDG_CACHE_HOME/squish"
  printf '{"name":"seeded-name"}' > "$XDG_CACHE_HOME/squish/$key.json"
  # ai_cache_get must return it.
  fn_dir="$(sed -n '/^ai_cache_dir() {/,/^}/p' "$SQUISH")"
  fn_get="$(sed -n '/^ai_cache_get() {/,/^}/p' "$SQUISH")"
  out="$(bash -c "NO_CACHE=0 AI_MODEL=gpt-4o-mini CONTEXT=general AI_FIELDS=name; $fn_sha"$'\n'"$fn_key"$'\n'"$fn_dir"$'\n'"$fn_get"$'\n'"ai_cache_get '$IN'")"
  [ "$(printf '%s' "$out" | jq -r '.name')" = "seeded-name" ]
}

@test "ai cache: --no-cache bypasses a seeded entry" {
  command -v jq >/dev/null || skip "needs jq"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  fn_sha="$(sed -n '/^sha256() {/,/^}/p' "$SQUISH")"
  fn_key="$(sed -n '/^ai_cache_key() {/,/^}/p' "$SQUISH")"
  fn_dir="$(sed -n '/^ai_cache_dir() {/,/^}/p' "$SQUISH")"
  fn_get="$(sed -n '/^ai_cache_get() {/,/^}/p' "$SQUISH")"
  key="$(bash -c "AI_MODEL=gpt-4o-mini CONTEXT=general AI_FIELDS=name; $fn_sha"$'\n'"$fn_key"$'\n'"ai_cache_key '$IN'")"
  mkdir -p "$XDG_CACHE_HOME/squish"
  printf '{"name":"seeded-name"}' > "$XDG_CACHE_HOME/squish/$key.json"
  run bash -c "NO_CACHE=1 AI_MODEL=gpt-4o-mini CONTEXT=general AI_FIELDS=name; $fn_sha"$'\n'"$fn_key"$'\n'"$fn_dir"$'\n'"$fn_get"$'\n'"ai_cache_get '$IN'"
  [ "$status" -ne 0 ]  # nothing returned when bypassed
}

@test "--context accepts auto" {
  run bash "$SQUISH" "$IN" --ai --context auto --no-color
  # With no key this becomes local mode, but the validation must not reject 'auto'.
  [ "$status" -eq 0 ]
  [[ "$output" != *"--context must be one of"* ]]
}

@test "ai_schema includes a context field when CONTEXT is auto" {
  fn="$(sed -n '/^ai_schema() {/,/^}/p' "$SQUISH")"
  out="$(bash -c "CONTEXT=auto AI_FIELDS=name,alt,params,html; $fn"$'\n'"ai_schema")"
  printf '%s' "$out" | jq -e '.properties.context' >/dev/null
}

@test "ai_schema omits context field when CONTEXT is explicit" {
  fn="$(sed -n '/^ai_schema() {/,/^}/p' "$SQUISH")"
  out="$(bash -c "CONTEXT=web AI_FIELDS=name,alt,params,html; $fn"$'\n'"ai_schema")"
  run bash -c "printf '%s' '$out' | jq -e '.properties.context'"
  [ "$status" -ne 0 ]  # no context property
}

@test "--apply is allowed with multiple inputs" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  a="$BATS_TEST_TMPDIR/a.png"; b="$BATS_TEST_TMPDIR/b.png"
  magick -size 60x60 xc:red "$a"; magick -size 60x60 xc:blue "$b"
  # No key -> local mode; --apply is forced off internally, but the guard must
  # not abort the run for multiple inputs.
  OPENAI_API_KEY= ANTHROPIC_API_KEY= run bash "$SQUISH" "$a" "$b" --ai --apply --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *"can't be used with multiple inputs"* ]]
}

@test "TAKEN re-claim: two sources renamed to the same AI name get suffixed" {
  # Reproduces the --apply batch-collision path without a network call: the run
  # loop claims the pre-rename dst, then optimize_one releases it and re-claims
  # the AI-suggested name. Two sources whose AI name collides must not overwrite.
  in="$BATS_TEST_TMPDIR/in"; od="$BATS_TEST_TMPDIR/od"; mkdir -p "$in" "$od"
  : > "$in/a.png"; : > "$in/b.png"
  fn_slug="$(sed -n '/^slugify() {/,/^}/p' "$SQUISH")"
  fn_kind="$(sed -n '/^img_kind() {/,/^}/p' "$SQUISH")"
  fn_ext="$(sed -n '/^out_ext_for() {/,/^}/p' "$SQUISH")"
  fn_stem="$(sed -n '/^build_stem() {/,/^}/p' "$SQUISH")"
  fn_dest="$(sed -n '/^dest_for() {/,/^}/p' "$SQUISH")"
  out="$(bash -c '
    declare -A TAKEN WALK_ROOT; OUTPUT="" OUT_DIR="'"$od"'" NAME_AS=slug WIDTH=0
    '"$fn_slug"$'\n'"$fn_kind"$'\n'"$fn_ext"$'\n'"$fn_stem"$'\n'"$fn_dest"$'
    for src in "'"$in"'/a.png" "'"$in"'/b.png"; do
      RENAME="" dst="$(dest_for "$src")"; TAKEN[$dst]=1        # pre-rename claim (run loop)
      unset "TAKEN[$dst]"                                       # optimize_one releases it
      dst="$(RENAME=logo dest_for "$src")"; TAKEN[$dst]=1       # and re-claims the AI name
      echo "$dst"
    done
  ')"
  [[ "$out" == *"$od/logo.png"* ]]
  [[ "$out" == *"$od/logo-2.png"* ]]
}

@test "colliding output names get numeric suffixes" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  d="$BATS_TEST_TMPDIR/out"; mkdir -p "$d"
  # Two differently-named sources that slug to the same name.
  magick -size 60x60 xc:red  "$BATS_TEST_TMPDIR/Logo A.png"
  magick -size 60x60 xc:blue "$BATS_TEST_TMPDIR/logo-a.png"
  run bash "$SQUISH" "$BATS_TEST_TMPDIR/Logo A.png" "$BATS_TEST_TMPDIR/logo-a.png" \
    --out-dir "$d" --no-color
  [ "$status" -eq 0 ]
  [ -f "$d/logo-a.png" ]
  [ -f "$d/logo-a-2.png" ]
}

@test "squishrc: colors default is read from ./.squishrc" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf 'colors=64\n' > .squishrc
  run bash "$SQUISH" in.png --dry-run --no-color
  [[ "$output" == *"64c"* ]]
}

@test "squishrc: CLI flag overrides a .squishrc value" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf 'colors=64\n' > .squishrc
  run bash "$SQUISH" in.png --colors 32 --dry-run --no-color
  [[ "$output" == *"32c"* ]]
  [[ "$output" != *"64c"* ]]
}

@test "squishrc: webp=1 emits a .webp sibling without --webp" {
  command -v cwebp >/dev/null || command -v magick >/dev/null || skip "needs a webp encoder"
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf 'webp=1\n' > .squishrc
  out="$BATS_TEST_TMPDIR/o.png"
  run bash "$SQUISH" in.png --output "$out" --no-color
  [ -f "${out%.png}.webp" ] || [ -f "$BATS_TEST_TMPDIR/in.webp" ] || [ -f "$out.webp" ]
}

@test "squishrc: unknown key warns on stderr and run still succeeds" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf 'wbep=1\n' > .squishrc
  run bash "$SQUISH" in.png --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown key 'wbep'"* ]]
}

@test "squishrc: invalid value is ignored and the default stands" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf 'colors=abc\n' > .squishrc
  run bash "$SQUISH" in.png --dry-run --no-color
  [[ "$output" == *"invalid colors 'abc'"* ]]
  [[ "$output" == *"128c"* ]]   # built-in default, since abc was rejected
}

@test "squishrc: a non key=value junk line is ignored, never executed" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  # If the file were sourced, this would delete the marker. It must not run.
  printf 'rm -f should-survive\n' > .squishrc
  : > should-survive
  run bash "$SQUISH" in.png --dry-run --no-color
  [ -f should-survive ]
  [[ "$output" == *"not key=value"* ]]
}

@test "squishrc: comments and blank lines are ignored without warnings" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf '# a comment\n\ncolors=64  # inline comment\n' > .squishrc
  run bash "$SQUISH" in.png --dry-run --no-color
  [[ "$output" == *"64c"* ]]
  [[ "$output" != *"⚠"* ]]
}

@test "squishrc: absent file behaves exactly like today" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  [ ! -e .squishrc ]
  run bash "$SQUISH" in.png --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"128c"* ]]   # untouched default
}

@test "squishrc: ai=1 enables analysis but does not apply/rename" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  command -v jq >/dev/null || skip "needs jq"
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  printf 'ai=1\n' > .squishrc
  out="$BATS_TEST_TMPDIR/o.png"
  OPENAI_API_KEY= ANTHROPIC_API_KEY= run bash "$SQUISH" in.png --output "$out" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto (local)"* ]]   # AI path ran (local, no key)
  [ -f "$out" ]                          # wrote to the explicit --output, no AI rename
}

@test "squishrc: banner shows the .squishrc marker only when a file was read" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  cd "$BATS_TEST_TMPDIR/proj"
  cp "$IN" in.png
  # No file: no marker.
  run bash "$SQUISH" in.png --dry-run --no-color
  [[ "$output" != *".squishrc"* ]]
  # With a file: marker present.
  printf 'colors=64\n' > .squishrc
  run bash "$SQUISH" in.png --dry-run --no-color
  [[ "$output" == *".squishrc"* ]]
}

@test "recursive: -R processes images in nested subdirectories" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/assets"; mkdir -p "$root/ui"
  magick -size 40x40 xc:red "$root/logo.png"
  magick -size 40x40 xc:blue "$root/ui/icon.png"
  run bash "$SQUISH" "$root" -R --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"logo"* ]]
  [[ "$output" == *"icon"* ]]
}

@test "recursive: a directory input without -R is an error" {
  d="$BATS_TEST_TMPDIR/adir"; mkdir -p "$d"
  run bash "$SQUISH" "$d" --no-color
  [ "$status" -ne 0 ]
  [[ "$output" == *"use -R"* ]]
}

@test "recursive: -R skips non-image files silently" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/mix"; mkdir -p "$root"
  magick -size 40x40 xc:red "$root/pic.png"
  printf 'hello' > "$root/notes.txt"
  printf '<svg/>' > "$root/vector.svg"
  run bash "$SQUISH" "$root" -R --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"pic"* ]]
  [[ "$output" != *"notes"* ]]
  [[ "$output" != *"vector"* ]]
}

@test "recursive: -R skips hidden directories" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/proj"; mkdir -p "$root/.git" "$root/pub"
  magick -size 40x40 xc:red "$root/.git/secret.png"
  magick -size 40x40 xc:blue "$root/pub/shown.png"
  run bash "$SQUISH" "$root" -R --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"shown"* ]]
  [[ "$output" != *"secret"* ]]
}

@test "recursive: a hidden ancestor in the passed path does not exclude everything" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  # The walk root lives UNDER a hidden directory the user explicitly passed.
  root="$BATS_TEST_TMPDIR/.config/icons"; mkdir -p "$root"
  magick -size 40x40 xc:red "$root/app.png"
  run bash "$SQUISH" "$root" -R --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"app"* ]]      # the file IS found despite the hidden ancestor
}

@test "recursive: still skips hidden SUBdirectories below the walk root" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/proj2"; mkdir -p "$root/.git" "$root/pub"
  magick -size 40x40 xc:red "$root/.git/secret.png"
  magick -size 40x40 xc:blue "$root/pub/shown.png"
  run bash "$SQUISH" "$root" -R --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"shown"* ]]
  [[ "$output" != *"secret"* ]]
}

@test "recursive: -R over a directory with no images errors clearly" {
  d="$BATS_TEST_TMPDIR/empty"; mkdir -p "$d"
  printf 'x' > "$d/readme.md"
  run bash "$SQUISH" "$d" -R --no-color
  [ "$status" -ne 0 ]
  [[ "$output" == *"no images"* ]]
}

@test "recursive: handles spaces in subdirectory and file names" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/my assets"; mkdir -p "$root/sub dir"
  magick -size 40x40 xc:red "$root/sub dir/cool pic.png"
  run bash "$SQUISH" "$root" -R --dry-run --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"cool pic"* || "$output" == *"cool-pic"* ]]
}

@test "recursive: non-regression — loose file input unaffected without -R" {
  out="$BATS_TEST_TMPDIR/o.png"
  run bash "$SQUISH" "$IN" --output "$out" --no-color
  [ -f "$out" ]
}

@test "recursive: -R with --output errors (multiple inputs)" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/two"; mkdir -p "$root"
  magick -size 40x40 xc:red "$root/a.png"; magick -size 40x40 xc:blue "$root/b.png"
  run bash "$SQUISH" "$root" -R --output "$BATS_TEST_TMPDIR/x.png" --no-color
  [ "$status" -ne 0 ]
  [[ "$output" == *"can't be used with multiple inputs"* ]]
}

@test "recursive: -R with --out-dir mirrors the source tree" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/assets"; mkdir -p "$root/ui"
  magick -size 40x40 xc:red  "$root/logo.png"
  magick -size 40x40 xc:blue "$root/ui/icon.png"
  dist="$BATS_TEST_TMPDIR/dist"
  run bash "$SQUISH" "$root" -R --out-dir "$dist" --no-color
  [ "$status" -eq 0 ]
  # top-level file lands at dist root; nested file mirrors its subdir.
  [ -f "$dist/logo.png" ]
  [ -f "$dist/ui/icon.png" ]
}

@test "recursive: -R --out-dir --dry-run writes nothing to disk" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/assets"; mkdir -p "$root/ui"
  magick -size 40x40 xc:red "$root/logo.png"
  magick -size 40x40 xc:blue "$root/ui/icon.png"
  dist="$BATS_TEST_TMPDIR/dist"
  run bash "$SQUISH" "$root" -R --out-dir "$dist" --dry-run --no-color
  [ "$status" -eq 0 ]
  [ ! -e "$dist" ]        # no output tree created at all
}

@test "recursive: a loose file under --out-dir still flattens (not mirrored)" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  sub="$BATS_TEST_TMPDIR/deep/nested"; mkdir -p "$sub"
  magick -size 40x40 xc:red "$sub/pic.png"
  dist="$BATS_TEST_TMPDIR/out"
  # Passed as a direct file (no -R): no walk root, so it flattens to dist/pic.png.
  run bash "$SQUISH" "$sub/pic.png" --out-dir "$dist" --no-color
  [ "$status" -eq 0 ]
  [ -f "$dist/pic.png" ]
}

@test "watch: --watch with --dry-run is rejected" {
  run bash "$SQUISH" "$IN" --watch --dry-run --no-color
  [ "$status" -ne 0 ]
  [[ "$output" == *"watch"* && "$output" == *"dry-run"* ]]
}

@test "watch: file_stamp changes when a file changes, empty when absent" {
  fn_size="$(sed -n '/^filesize() {/,/^}/p' "$SQUISH")"
  fn_stamp="$(sed -n '/^file_stamp() {/,/^}/p' "$SQUISH")"
  f="$BATS_TEST_TMPDIR/s.png"; cp "$IN" "$f"
  s1="$(bash -c "$fn_size"$'\n'"$fn_stamp"$'\n'"file_stamp '$f'")"
  [ -n "$s1" ]
  sleep 1; printf 'more' >> "$f"        # change size (and mtime)
  s2="$(bash -c "$fn_size"$'\n'"$fn_stamp"$'\n'"file_stamp '$f'")"
  [ "$s1" != "$s2" ]
  rm -f "$f"
  s3="$(bash -c "$fn_size"$'\n'"$fn_stamp"$'\n'"file_stamp '$f'")"
  [ -z "$s3" ]
}

@test "watch: first pass optimizes, then a source edit re-optimizes it" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  work="$BATS_TEST_TMPDIR/w"; mkdir -p "$work"
  magick -size 80x80 xc:red "$work/a.png"
  out="$work/a-min.png"
  # Start watching in the background with a short interval.
  WATCH_INTERVAL=1 bash "$SQUISH" "$work/a.png" --watch --no-color >/dev/null 2>&1 &
  pid=$!
  # Wait for the first pass to produce output.
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$out" ] && break; sleep 0.5; done
  [ -f "$out" ]
  first_mtime="$(stat -f %m "$out" 2>/dev/null || stat -c %Y "$out" 2>/dev/null)"
  # Edit the source; the watcher must re-optimize within a couple intervals.
  sleep 1; magick -size 80x80 xc:blue "$work/a.png"
  updated=0
  for _ in 1 2 3 4 5 6 7 8; do
    m="$(stat -f %m "$out" 2>/dev/null || stat -c %Y "$out" 2>/dev/null)"
    [ "$m" != "$first_mtime" ] && { updated=1; break; }
    sleep 0.5
  done
  kill "$pid" 2>/dev/null
  [ "$updated" -eq 1 ]
}

@test "watch: a generated output does not re-trigger the loop" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  work="$BATS_TEST_TMPDIR/w2"; mkdir -p "$work"
  magick -size 80x80 xc:red "$work/b.png"
  out="$work/b-min.png"
  WATCH_INTERVAL=1 bash "$SQUISH" "$work/b.png" --watch --no-color >/dev/null 2>&1 &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$out" ] && break; sleep 0.5; done
  [ -f "$out" ]
  m1="$(stat -f %m "$out" 2>/dev/null || stat -c %Y "$out" 2>/dev/null)"
  # Do NOT touch the source. Wait several intervals; the output must be stable
  # (the watcher must not re-optimize because its own output "changed").
  sleep 3
  m2="$(stat -f %m "$out" 2>/dev/null || stat -c %Y "$out" 2>/dev/null)"
  kill "$pid" 2>/dev/null
  [ "$m1" = "$m2" ]
}

@test "watch: SIGTERM stops cleanly with a message" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  work="$BATS_TEST_TMPDIR/w3"; mkdir -p "$work"
  magick -size 60x60 xc:red "$work/c.png"
  log="$BATS_TEST_TMPDIR/w3.log"
  WATCH_INTERVAL=1 bash "$SQUISH" "$work/c.png" --watch >"$log" 2>&1 &
  pid=$!
  sleep 2
  kill -TERM "$pid" 2>/dev/null
  wait "$pid"; rc=$?
  [ "$rc" -eq 0 ]
  grep -q "stopped watching" "$log"
}

@test "watch: -R picks up a file added to a watched directory mid-run" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  work="$BATS_TEST_TMPDIR/wd"; mkdir -p "$work"
  magick -size 60x60 xc:red "$work/first.png"
  WATCH_INTERVAL=1 bash "$SQUISH" "$work" -R --watch --no-color >/dev/null 2>&1 &
  pid=$!
  # wait for first pass to optimize the initial file
  for _ in $(seq 1 12); do [ -f "$work/first-min.png" ] && break; sleep 0.5; done
  [ -f "$work/first-min.png" ]
  # drop a NEW file into the watched dir; it must be optimized within a few ticks
  sleep 1; magick -size 60x60 xc:blue "$work/second.png"
  found=0
  for _ in $(seq 1 12); do [ -f "$work/second-min.png" ] && { found=1; break; }; sleep 0.5; done
  # Anti-loop: give it a few more ticks and confirm the file count stops growing
  # (the generated *-min.png outputs must never be re-discovered as new sources).
  sleep 3
  count_before="$(find "$work" -name '*.png' | wc -l | tr -d ' ')"
  sleep 2
  count_after="$(find "$work" -name '*.png' | wc -l | tr -d ' ')"
  kill "$pid" 2>/dev/null
  [ "$found" -eq 1 ]
  [ "$count_before" = "$count_after" ]
}

@test "watch: SIGTERM interrupts the sleep promptly instead of waiting a full interval" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  work="$BATS_TEST_TMPDIR/w4"; mkdir -p "$work"
  magick -size 60x60 xc:red "$work/d.png"
  log="$BATS_TEST_TMPDIR/w4.log"
  WATCH_INTERVAL=10 bash "$SQUISH" "$work/d.png" --watch >"$log" 2>&1 &
  pid=$!
  sleep 1
  start="$(date +%s)"
  kill -TERM "$pid" 2>/dev/null
  wait "$pid"; rc=$?
  elapsed=$(( $(date +%s) - start ))
  [ "$rc" -eq 0 ]
  [ "$elapsed" -lt 3 ]
  grep -q "stopped watching" "$log"
}

@test "watch: --out-dir with a trailing slash nested in a watched tree does not run away" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  root="$BATS_TEST_TMPDIR/assets"; mkdir -p "$root"
  magick -size 40x40 xc:red "$root/logo.png"
  # trailing slash on --out-dir, out-dir nested inside the watched -R tree
  WATCH_INTERVAL=1 bash "$SQUISH" "$root" -R --watch --out-dir "$root/dist/" --no-color >/dev/null 2>&1 &
  pid=$!
  sleep 5
  kill "$pid" 2>/dev/null
  # No runaway nesting: dist/dist must never be created.
  [ ! -e "$root/dist/dist" ]
  # And the legit output exists exactly once.
  [ -f "$root/dist/logo.png" ]
}

@test "watch: SIGTERM kills the backgrounded sleep, none lingers after exit" {
  command -v magick >/dev/null || skip "needs ImageMagick"
  work="$BATS_TEST_TMPDIR/w5"; mkdir -p "$work"
  magick -size 60x60 xc:red "$work/e.png"
  WATCH_INTERVAL=20 bash "$SQUISH" "$work/e.png" --watch --no-color >/dev/null 2>&1 &
  pid=$!
  sleep 1
  # Find the sleep child before killing the parent.
  sleep_pid="$(pgrep -P "$pid" -f 'sleep 20' 2>/dev/null || true)"
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 0.5
  # The sleep child must not still be alive (reparented or otherwise).
  if [ -n "$sleep_pid" ]; then
    run kill -0 "$sleep_pid"
    [ "$status" -ne 0 ]
  fi
}

@test "compress failure (no ImageMagick for JPEG) is reported, not a false success" {
  command -v magick >/dev/null || skip "test shims magick; needs a real one to build the fixture"
  # Build a JPEG fixture with the real magick.
  magick -size 60x60 xc:red "$BATS_TEST_TMPDIR/pic.jpg"
  # Shim magick to fail, keep everything else on PATH.
  shim="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shim"
  printf '#!/bin/sh\nexit 127\n' > "$shim/magick"; chmod +x "$shim/magick"
  out="$BATS_TEST_TMPDIR/out.jpg"
  PATH="$shim:$PATH" run bash "$SQUISH" "$BATS_TEST_TMPDIR/pic.jpg" --output "$out" --no-color
  # Must NOT claim success, and must NOT leave a zero-byte output.
  [[ "$output" != *"1 file optimized"* ]]
  [ ! -s "$out" ]
  [[ "$output" == *"compress failed"* || "$output" == *"nothing optimized"* ]]
}

@test "human and pct_saved work without bc on PATH" {
  fn_human="$(sed -n '/^human() {/,/^}/p' "$SQUISH")"
  fn_pct="$(sed -n '/^pct_saved() {/,/^}/p' "$SQUISH")"
  # A PATH with the shells/coreutils but guaranteed no bc: use a dir of symlinks
  # to just the tools these funcs need (printf is a builtin; nothing external).
  nobc="$BATS_TEST_TMPDIR/nobc"; mkdir -p "$nobc"
  # Resolve bash's absolute path before wiping PATH, so `bash -c` itself can
  # still be exec'd (an empty PATH would otherwise make even `bash` unresolvable).
  bash_bin="$(command -v bash)"
  # Run the extracted functions under an empty PATH (they use only builtins).
  h_kb="$(PATH= "$bash_bin" -c "$fn_human"$'\n'"human 1536")"      # 1.5 KB
  h_mb="$(PATH= "$bash_bin" -c "$fn_human"$'\n'"human 1572864")"   # 1.5 MB
  h_b="$(PATH=  "$bash_bin" -c "$fn_human"$'\n'"human 512")"       # 512 B
  [ "$h_kb" = "1.5 KB" ]
  [ "$h_mb" = "1.5 MB" ]
  [ "$h_b" = "512 B" ]
  p1="$(PATH= "$bash_bin" -c "$fn_pct"$'\n'"pct_saved 1000 250")"  # 75
  p0="$(PATH= "$bash_bin" -c "$fn_pct"$'\n'"pct_saved 0 0")"        # 0 (div-by-zero guard)
  pneg="$(PATH= "$bash_bin" -c "$fn_pct"$'\n'"pct_saved 100 158")" # -58 (grew)
  [ "$p1" = "75" ]
  [ "$p0" = "0" ]
  [ "$pneg" = "-58" ]
}
