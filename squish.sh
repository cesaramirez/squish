#!/usr/bin/env bash
#
# squish.sh — Optimize images (PNG / JPG), with optional AI analysis.
#
# PNG  -> pngquant (palette) + oxipng (lossless), transparency preserved.
# JPEG -> ImageMagick (progressive, tuned quality).
# Optional WebP and AVIF siblings. Optionally uses vision AI (OpenAI or Claude)
# to suggest a semantic name, alt text, optimal params, and an HTML snippet.
# Cross-platform: uses sips on macOS, ImageMagick elsewhere.
#
# Usage:
#   ./squish.sh input.png [output.png]
#   ./squish.sh input.png --width 400              # resize to 400px wide, then compress
#   ./squish.sh input.png --retina --display 200   # 2x of a 200px display size -> 400px
#   ./squish.sh input.png --webp                   # also write input.optimized.webp
#   ./squish.sh *.png --width 400 --out-dir dist   # batch into ./dist/
#   ./squish.sh photo.jpg --ai                     # AI: suggest name/alt/params/html
#   ./squish.sh arc.png --ai --context email-signature --apply
#
# Options:
#   -w, --width N      Resize to N px wide (keeps aspect ratio) before compressing.
#                      Ship an image at ~2x its display size. Never upscales.
#   -r, --retina       With --display, targets 2x that width. Shorthand for --width.
#       --display N    Intended display width in px; with --retina resizes to 2*N.
#   -c, --colors N     PNG palette size (default: 128). Lower = smaller & more banding.
#                      128 ≈ no visible loss at display size. 64 = aggressive.
#       --jpeg-quality N  JPEG output quality 1-100 (default: 82).
#       --webp         Also emit a .webp sibling (~40% smaller; needs <picture> fallback).
#       --avif         Also emit a .avif sibling (~50% smaller; needs ImageMagick w/ AVIF).
#       --dry-run      Show what would happen (names, sizes) without writing files.
#   -d, --out-dir DIR  Write all outputs into DIR (created if missing).
#   -o, --output FILE  Output path (single input only; overrides all naming below).
#       --name-as WHAT How to name outputs (default: slug):
#                        slug       url-safe kebab-case  (spaces/accents cleaned) [default]
#                        optimized  name.optimized.png   (keeps original name + suffix)
#                        plain      name.png
#                        retina     slug + @2x           (needs a resize)
#                        width      slug + -400w         (needs a resize)
#                      Never overwrites the source: if names collide, appends -min.
#       --rename NAME  Replace the base name entirely (single input; slugified).
#                        e.g. --rename signature-arc --name-as retina -> signature-arc@2x.png
#
#   AI (vision — OpenAI or Anthropic; degrades gracefully if no key/tools):
#       --ai           Analyze the image and print suggestions (name, alt, params, html).
#       --ai-provider P  auto (default) | openai | anthropic.
#                        auto uses OPENAI_API_KEY, else ANTHROPIC_API_KEY.
#       --context WHAT What the image is for, so the AI calibrates its output:
#                        general (default) | email-signature | web | hero | icon | avatar
#       --ai-fields L  Comma list of fields to request (default: name,alt,params,html).
#                        Any of: name, alt, params, html.
#       --apply        Apply the AI's suggested name automatically (implies --ai).
#       --ai-model M   Model override (default: gpt-4o-mini / claude-haiku-4-5).
#
#       --no-color     Disable colored output (also respects NO_COLOR env var).
#   -q, --quiet        Only print the per-file result lines.
#   -h, --help         Show this help.
#
# Requires: pngquant, oxipng. Optional: sips (macOS) or imagemagick (resize, JPEG,
#           AVIF, cross-platform); cwebp (--webp); curl + jq (--ai).
# AI keys:  set OPENAI_API_KEY or ANTHROPIC_API_KEY for --ai (auto-detected).

set -euo pipefail

COLORS=128
WIDTH=0
DISPLAY=0
RETINA=0
WEBP=0
AVIF=0                # also emit an .avif sibling
JPEG_QUALITY=82       # quality for JPEG output (mozjpeg/magick)
DRY_RUN=0             # preview actions without writing files
OUT_DIR=""
OUTPUT=""
NAME_AS="slug"        # slug | optimized | plain | retina | width  (default: slug, URL-safe)
RENAME=""             # replace the base name entirely
AI=0                  # run vision analysis
APPLY=0               # apply the AI-suggested name automatically
CONTEXT="general"     # general | email-signature | web | hero | icon | avatar
AI_FIELDS="name,alt,params,html"
AI_PROVIDER="auto"    # auto | anthropic | openai
AI_MODEL=""           # empty = provider default (haiku / gpt-4o-mini)
QUIET=0
NO_COLOR=0
INPUTS=()

# --- colors -------------------------------------------------------------------
# Honor NO_COLOR, --no-color, and non-TTY output (pipes, CI) automatically.
setup_colors() {
  if [[ "$NO_COLOR" -eq 1 || -n "${NO_COLOR:-}" && "${NO_COLOR}" != "0" ]] || [[ ! -t 1 ]]; then
    BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' GRAY='' RESET=''
  else
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    CYAN=$'\033[36m'; GRAY=$'\033[90m'
  fi
}

die()  { printf '%s✗%s %s\n' "${RED:-}" "${RESET:-}" "$*" >&2; exit 1; }
log()  { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }
note() { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'; }

# --- parse args ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--width)    WIDTH="${2:?}"; shift 2 ;;
    -r|--retina)   RETINA=1; shift ;;
        --display) DISPLAY="${2:?}"; shift 2 ;;
    -c|--colors)   COLORS="${2:?}"; shift 2 ;;
        --webp)    WEBP=1; shift ;;
        --avif)    AVIF=1; shift ;;
        --jpeg-quality) JPEG_QUALITY="${2:?}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
    -d|--out-dir)  OUT_DIR="${2:?}"; shift 2 ;;
    -o|--output)   OUTPUT="${2:?}"; shift 2 ;;
        --name-as) NAME_AS="${2:?}"; shift 2 ;;
        --rename)  RENAME="${2:?}"; shift 2 ;;
        --ai)      AI=1; shift ;;
        --apply)   AI=1; APPLY=1; shift ;;
        --context) CONTEXT="${2:?}"; shift 2 ;;
        --ai-fields) AI_FIELDS="${2:?}"; shift 2 ;;
        --ai-model) AI_MODEL="${2:?}"; shift 2 ;;
        --ai-provider) AI_PROVIDER="${2:?}"; shift 2 ;;
        --no-color) NO_COLOR=1; shift ;;
    -q|--quiet)    QUIET=1; shift ;;
    -h|--help)     NO_COLOR=1; usage; exit 0 ;;
    -*)            NO_COLOR=1; die "unknown option: $1" ;;
    *)             INPUTS+=("$1"); shift ;;
  esac
done

setup_colors

# --retina --display N resolves to a concrete width (2x the display size).
if (( RETINA )); then
  (( DISPLAY > 0 )) || die "--retina needs --display N (the intended on-screen width)"
  WIDTH=$(( DISPLAY * 2 ))
elif (( DISPLAY > 0 )); then
  die "--display only makes sense with --retina (use --width for an explicit size)"
fi

[[ ${#INPUTS[@]} -gt 0 ]] || die "no input file. See --help."
[[ "$COLORS" =~ ^[0-9]+$ ]] && (( COLORS >= 2 && COLORS <= 256 )) || die "--colors must be 2..256"
[[ "$WIDTH" =~ ^[0-9]+$ ]] || die "--width must be a positive integer"
[[ -n "$OUTPUT" && ${#INPUTS[@]} -gt 1 ]] && die "--output can't be used with multiple inputs"
[[ -n "$OUTPUT" && -n "$OUT_DIR" ]] && die "use either --output or --out-dir, not both"
case "$NAME_AS" in optimized|plain|slug|retina|width) ;; *) die "--name-as must be one of: optimized, plain, slug, retina, width" ;; esac
[[ -n "$RENAME" && ${#INPUTS[@]} -gt 1 ]] && die "--rename can't be used with multiple inputs (each would collide)"
if [[ "$NAME_AS" == "width" || "$NAME_AS" == "retina" ]] && (( WIDTH == 0 )); then
  die "--name-as $NAME_AS needs a resize (--width or --retina --display)"
fi
case "$CONTEXT" in general|email-signature|web|hero|icon|avatar) ;; *) die "--context must be one of: general, email-signature, web, hero, icon, avatar" ;; esac
(( APPLY )) && [[ ${#INPUTS[@]} -gt 1 ]] && die "--apply can't be used with multiple inputs (each name would collide)"

# --- deps ---------------------------------------------------------------------
# Image engines: sips (macOS, no deps) and/or ImageMagick (cross-platform).
HAVE_SIPS=0;   command -v sips  >/dev/null 2>&1 && HAVE_SIPS=1
HAVE_MAGICK=0; command -v magick >/dev/null 2>&1 && HAVE_MAGICK=1
# Optional per-feature tools.
HAVE_PNGQUANT=0; command -v pngquant >/dev/null 2>&1 && HAVE_PNGQUANT=1
HAVE_OXIPNG=0;   command -v oxipng   >/dev/null 2>&1 && HAVE_OXIPNG=1
HAVE_CWEBP=0;    command -v cwebp    >/dev/null 2>&1 && HAVE_CWEBP=1

# PNG optimization needs pngquant + oxipng (the sharpest PNG path). Everything
# else (JPEG in/out, WebP/AVIF, cross-platform resize) can lean on ImageMagick.
(( HAVE_PNGQUANT )) || die "pngquant not found. Run: ${BOLD}brew install pngquant${RESET}"
(( HAVE_OXIPNG ))   || die "oxipng not found. Run: ${BOLD}brew install oxipng${RESET}"

# Resizing: need at least one engine.
if (( WIDTH > 0 )) && (( ! HAVE_SIPS )) && (( ! HAVE_MAGICK )); then
  die "resizing (--width/--retina) needs sips (macOS) or ImageMagick. Run: ${BOLD}brew install imagemagick${RESET}"
fi
# WebP: cwebp preferred, else ImageMagick.
if (( WEBP )) && (( ! HAVE_CWEBP )) && (( ! HAVE_MAGICK )); then
  die "--webp needs cwebp or ImageMagick. Run: ${BOLD}brew install webp${RESET}"
fi
# AVIF: ImageMagick only (must be built with libaom/libheif).
if (( AVIF )) && (( ! HAVE_MAGICK )); then
  die "--avif needs ImageMagick (with AVIF support). Run: ${BOLD}brew install imagemagick${RESET}"
fi
[[ "$JPEG_QUALITY" =~ ^[0-9]+$ ]] && (( JPEG_QUALITY >= 1 && JPEG_QUALITY <= 100 )) || die "--jpeg-quality must be 1..100"

# --ai degrades gracefully: warn once and disable rather than aborting the run.
# Resolves provider + key + default model. Sets AI_KEY for ai_analyze to use.
AI_KEY=""
if (( AI )); then
  case "$AI_PROVIDER" in auto|anthropic|openai) ;; *) die "--ai-provider must be one of: auto, anthropic, openai" ;; esac
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf '%s⚠%s --ai needs curl and jq; skipping AI analysis.\n' "${YELLOW}" "${RESET}" >&2
    AI=0; APPLY=0
  else
    # auto: prefer whichever key is present (OpenAI first, then Anthropic).
    if [[ "$AI_PROVIDER" == "auto" ]]; then
      if   [[ -n "${OPENAI_API_KEY:-}" ]];    then AI_PROVIDER="openai"
      elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then AI_PROVIDER="anthropic"
      else AI_PROVIDER="none"; fi
    fi
    case "$AI_PROVIDER" in
      openai)    AI_KEY="${OPENAI_API_KEY:-}";    [[ -z "$AI_MODEL" ]] && AI_MODEL="gpt-4o-mini" ;;
      anthropic) AI_KEY="${ANTHROPIC_API_KEY:-}"; [[ -z "$AI_MODEL" ]] && AI_MODEL="claude-haiku-4-5" ;;
      none)      AI_KEY="" ;;
    esac
    if [[ -z "$AI_KEY" ]]; then
      printf '%s⚠%s --ai needs an API key: set %sOPENAI_API_KEY%s or %sANTHROPIC_API_KEY%s (or pick one with --ai-provider). Skipping AI analysis.\n' \
        "${YELLOW}" "${RESET}" "${BOLD}" "${RESET}" "${BOLD}" "${RESET}" >&2
      AI=0; APPLY=0
    fi
  fi
fi

[[ -n "$OUT_DIR" ]] && mkdir -p "$OUT_DIR"

# --- helpers ------------------------------------------------------------------
# Cross-platform file size in bytes (BSD/macOS `stat -f%z` vs GNU/Linux `stat -c%s`).
filesize() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

# Cross-platform sha256 of a file's bytes (macOS shasum vs Linux sha256sum).
sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  fi
}

human() { # bytes -> human readable, fixed width
  local b=$1
  if   (( b >= 1048576 )); then printf '%.1f MB' "$(echo "$b/1048576" | bc -l)"
  elif (( b >= 1024 ));    then printf '%.1f KB' "$(echo "$b/1024" | bc -l)"
  else printf '%d B' "$b"; fi
}

pct_saved() { # in out -> integer percent saved (rounded). Guards divide-by-zero.
  local in="$1" out="$2"
  (( in == 0 )) && { echo 0; return; }
  echo "scale=4; r=(1 - $out/$in) * 100; scale=0; (r+0.5)/1" | bc -l
}

# --- image engine (cross-platform) --------------------------------------------
# Prefer sips on macOS (fast, no deps); fall back to ImageMagick everywhere else.
# HAVE_SIPS / HAVE_MAGICK are resolved once at startup (see deps section).
dims_of() { # file -> "WxH" or ""
  if (( HAVE_SIPS )); then
    sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd'x' - 2>/dev/null
  elif (( HAVE_MAGICK )); then
    magick identify -format '%wx%h' "$1[0]" 2>/dev/null
  fi
}

# resize_to WIDTH SRC DST -> 0 on success. Never called when WIDTH >= source width.
resize_to() {
  local w="$1" src="$2" dst="$3"
  if (( HAVE_SIPS )); then
    sips --resampleWidth "$w" "$src" --out "$dst" >/dev/null 2>&1
  elif (( HAVE_MAGICK )); then
    magick "$src" -resize "${w}x" "$dst" 2>/dev/null
  else
    return 1
  fi
}

# 12-wide bar; more green = more saved. Uses gradient thresholds.
savings_bar() {
  local pct=$1 width=12 filled i out=""
  (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  filled=$(( pct * width / 100 ))
  local color="$GREEN"
  (( pct < 40 )) && color="$YELLOW"
  (( pct < 15 )) && color="$RED"
  for ((i=0;i<width;i++)); do
    if (( i < filled )); then out+="${color}█${RESET}"; else out+="${GRAY}░${RESET}"; fi
  done
  printf '%s' "$out"
}

# --- format helpers -----------------------------------------------------------
# lowercased extension of a path
ext_of() { printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'; }

# Logical kind of an image by extension: png | jpeg | webp | other.
img_kind() {
  case "$(ext_of "$1")" in
    png)      printf 'png' ;;
    jpg|jpeg) printf 'jpeg' ;;
    webp)     printf 'webp' ;;
    gif)      printf 'gif' ;;
    avif)     printf 'avif' ;;
    *)        printf 'other' ;;
  esac
}

# Output extension for a source: JPEG stays .jpg, everything else normalizes to
# .png (our lossless-with-alpha default). WebP/AVIF are emitted as siblings.
out_ext_for() {
  case "$(img_kind "$1")" in
    jpeg) printf 'jpg' ;;
    *)    printf 'png' ;;
  esac
}

# --- AI (Claude vision) -------------------------------------------------------
# media_type from a file, for the base64 image block.
media_type_of() {
  case "$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')" in
    png)        printf 'image/png' ;;
    jpg|jpeg)   printf 'image/jpeg' ;;
    gif)        printf 'image/gif' ;;
    webp)       printf 'image/webp' ;;
    *)          printf 'image/png' ;;
  esac
}

# Guidance per --context, injected into the prompt so name/alt/html fit the use.
# Each note states a sensible DISPLAY width (CSS px) so the HTML width attribute
# is a display size, not the file's pixel dimensions.
context_hint() {
  case "$CONTEXT" in
    email-signature) printf 'Context: a decorative element in an email signature. HTML must be email-safe: a plain <img> with an explicit width attribute and alt text — no <picture>, no CSS classes, no style attribute. Use a display width around 180-240 CSS px (a signature accent is small).' ;;
    web)      printf 'Context: a general website image. HTML may use <picture> with a WebP <source> and PNG fallback, plus width and alt. Use a display width around 320-480 CSS px unless it is clearly a small inline element.' ;;
    hero)     printf 'Context: a large hero/banner. Suggest a wide responsive <img> with descriptive alt and width="100%%" (or 1200 CSS px).' ;;
    icon)     printf 'Context: a small UI icon. Keep the name short; alt terse or empty (alt="") if purely decorative. Use a display width of 16-48 CSS px.' ;;
    avatar)   printf 'Context: a profile avatar. Name/alt should reflect that (alt like "Profile photo"). Use a display width of 40-96 CSS px, typically square.' ;;
    *)        printf 'Context: a general-purpose image. Use a display width around 320 CSS px in the HTML unless the image is clearly small.' ;;
  esac
}

# Heuristic image classification using ImageMagick only (no API). Emits JSON:
#   {kind, suggested_colors, suggest_webp, suggest_avif}
# Order of checks matters: icon (by size) before gradient/photo (by colors).
analyze_local() {
  local src="$1" w h colors kind
  # Dimensions and unique color count. %k can be large; keep it an integer.
  w="$(magick identify -format '%w' "${src}[0]" 2>/dev/null || echo 0)"
  h="$(magick identify -format '%h' "${src}[0]" 2>/dev/null || echo 0)"
  colors="$(magick identify -format '%k' "${src}[0]" 2>/dev/null || echo 0)"
  [[ "$w" =~ ^[0-9]+$ ]] || w=0
  [[ "$h" =~ ^[0-9]+$ ]] || h=0
  [[ "$colors" =~ ^[0-9]+$ ]] || colors=0

  local maxdim=$(( w > h ? w : h ))
  if (( maxdim > 0 && maxdim <= 64 )); then
    kind="icon"
  elif (( colors > 0 && colors <= 16 )); then
    kind="logo"
  elif (( colors >= 4096 )); then
    # Many distinct colors. Smooth blends (gradients/renders) vs photos: use a
    # cheap edge-density proxy. Photos have high edge energy; gradients low.
    local edges
    edges="$(magick "${src}[0]" -colorspace Gray -edge 1 /tmp/edge_temp_$$.png 2>/dev/null && magick identify -format '%[fx:mean]' /tmp/edge_temp_$$.png 2>/dev/null ; rm -f /tmp/edge_temp_$$.png)"
    [[ -z "$edges" || ! "$edges" =~ ^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$ ]] && edges="0"
    # mean edge magnitude in [0,1]; photos ~>0.06, smooth gradients ~<0.03.
    if awk "BEGIN{exit !($edges < 0.015)}"; then
      kind="gradient"
    else
      kind="photo"
    fi
  else
    # 16 < colors < 4096: illustrations, logos with anti-aliasing, or gradients.
    # Use edge-density to distinguish smooth blends from textured/detailed images.
    local edges
    edges="$(magick "${src}[0]" -colorspace Gray -edge 1 /tmp/edge_temp_$$.png 2>/dev/null && magick identify -format '%[fx:mean]' /tmp/edge_temp_$$.png 2>/dev/null ; rm -f /tmp/edge_temp_$$.png)"
    [[ -z "$edges" || ! "$edges" =~ ^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$ ]] && edges="0"
    if awk "BEGIN{exit !($edges < 0.015)}"; then
      kind="gradient"
    else
      kind="illustration"
    fi
  fi

  local sc webp avif
  case "$kind" in
    photo|gradient) sc=256; webp=true;  avif=true ;;
    illustration)   sc=128; webp=true;  avif=false ;;
    logo)           sc=64;  webp=false; avif=false ;;
    icon)           sc=32;  webp=false; avif=false ;;
  esac
  # Map illustration onto the photo/logo/gradient/icon enum the schema allows.
  [[ "$kind" == "illustration" ]] && kind="logo"

  jq -n --arg kind "$kind" --argjson sc "$sc" --argjson webp "$webp" --argjson avif "$avif" \
    '{kind:$kind, suggested_colors:$sc, suggest_webp:$webp, suggest_avif:$avif}'
}

# Build the JSON schema (properties + required) from --ai-fields.
ai_schema() {
  local props='' req='' want_name=0 want_alt=0 want_params=0 want_html=0 f
  IFS=',' read -ra _f <<< "$AI_FIELDS"
  for f in "${_f[@]}"; do case "$(printf '%s' "$f" | tr -d '[:space:]')" in
    name) want_name=1 ;; alt) want_alt=1 ;; params) want_params=1 ;; html) want_html=1 ;;
  esac; done
  (( want_name )) && { props+='"name":{"type":"string","description":"url-safe kebab-case slug describing the image content, no extension"},'; req+='"name",'; }
  (( want_alt )) &&  { props+='"alt":{"type":"string","description":"concise alt text for accessibility"},'; req+='"alt",'; }
  (( want_params )) && { props+='"kind":{"type":"string","enum":["photo","logo","illustration","gradient","icon","screenshot","other"],"description":"photo=camera photograph of real subjects; logo=brand mark, often flat colors; illustration=drawn/vector artwork; gradient=smooth color blends, 3D renders, glossy/metallic surfaces, abstract backgrounds; icon=tiny UI glyph; screenshot=UI capture. A metallic or glossy 3D render is gradient, NOT photo."},"suggested_colors":{"type":"integer","enum":[32,64,128,256],"description":"palette size: 256 for photos and smooth gradients (avoid banding); 128 for most illustrations/renders; 64 for flat logos; 32 for simple icons"},"suggest_webp":{"type":"boolean","description":"true if the image has smooth gradients or many colors where WebP saves meaningful bytes"},'; req+='"kind","suggested_colors","suggest_webp",'; }
  (( want_html )) && { props+='"html":{"type":"string","description":"ready-to-paste HTML snippet using SRC as the URL placeholder. Set the width attribute to a sensible DISPLAY width in CSS pixels for the given context (see the context note), NOT the file pixel dimensions."},'; req+='"html",'; }
  printf '{"type":"object","properties":{%s},"required":[%s],"additionalProperties":false}' "${props%,}" "${req%,}"
}

ai_prompt() {
  local dims="${1:-}"
  printf 'You are analyzing an image to help optimize and label it. %s' "$(context_hint)"
  [[ -n "$dims" ]] && printf ' The file is %s px (width x height) — but the HTML width attribute must be a DISPLAY size per the context note, not these file dimensions.' "$dims"
  printf ' Rules: (1) name = url-safe kebab-case slug describing the visible content (lowercase, hyphens, no spaces, no accents, no file extension); prefer 2-4 descriptive words. (2) Classify kind by what the surface actually looks like: a glossy, metallic, or 3D-rendered surface with smooth color blends is "gradient", never "photo"; "photo" is only a real-world camera photograph. (3) alt = concise, describes the image for a screen reader. Return only the requested fields.'
}

# --- Anthropic backend: base64 image block + output_config.format (json_schema).
ai_anthropic() {
  local mt="$1" b64="$2" schema="$3" dims="${4:-}" body resp
  body="$(jq -n --arg model "$AI_MODEL" --arg mt "$mt" --arg data "$b64" \
    --arg prompt "$(ai_prompt "$dims")" --argjson schema "$schema" '{
      model: $model, max_tokens: 1024,
      output_config: { format: { type: "json_schema", schema: $schema } },
      messages: [{ role: "user", content: [
        { type: "image", source: { type: "base64", media_type: $mt, data: $data } },
        { type: "text", text: $prompt }
      ]}]
    }')"
  resp="$(curl -sS https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" -H "x-api-key: $AI_KEY" \
    -H "anthropic-version: 2023-06-01" -d "$body" 2>/dev/null)" || return 1
  if printf '%s' "$resp" | jq -e '.type == "error"' >/dev/null 2>&1; then
    printf '%s⚠%s AI: %s\n' "$YELLOW" "$RESET" "$(printf '%s' "$resp" | jq -r '.error.message // "unknown error"')" >&2
    return 1
  fi
  printf '%s' "$resp" | jq -e -c '.content[] | select(.type=="text") | .text | fromjson' 2>/dev/null
}

# --- OpenAI backend: data: URL image + response_format json_schema (strict).
ai_openai() {
  local mt="$1" b64="$2" schema="$3" dims="${4:-}" body resp
  # OpenAI strict json_schema needs the schema wrapped and strict:true.
  body="$(jq -n --arg model "$AI_MODEL" --arg url "data:$mt;base64,$b64" \
    --arg prompt "$(ai_prompt "$dims")" --argjson schema "$schema" '{
      model: $model, max_tokens: 1024,
      response_format: { type: "json_schema", json_schema: { name: "image_analysis", strict: true, schema: $schema } },
      messages: [{ role: "user", content: [
        { type: "text", text: $prompt },
        { type: "image_url", image_url: { url: $url } }
      ]}]
    }')"
  resp="$(curl -sS https://api.openai.com/v1/chat/completions \
    -H "content-type: application/json" -H "authorization: Bearer $AI_KEY" \
    -d "$body" 2>/dev/null)" || return 1
  if printf '%s' "$resp" | jq -e 'has("error")' >/dev/null 2>&1; then
    printf '%s⚠%s AI: %s\n' "$YELLOW" "$RESET" "$(printf '%s' "$resp" | jq -r '.error.message // "unknown error"')" >&2
    return 1
  fi
  printf '%s' "$resp" | jq -e -c '.choices[0].message.content | fromjson' 2>/dev/null
}

# Analyze an image. Echoes validated JSON to stdout, or nothing on failure.
ai_analyze() {
  local src="$1" b64 mt schema dims
  b64="$(base64 < "$src" | tr -d '\n')" || return 1
  mt="$(media_type_of "$src")"
  schema="$(ai_schema)"
  dims="$(dims_of "$src")"   # WxH of the analyzed (resized) image, for the prompt
  case "$AI_PROVIDER" in
    openai)    ai_openai    "$mt" "$b64" "$schema" "$dims" ;;
    anthropic) ai_anthropic "$mt" "$b64" "$schema" "$dims" ;;
    *) return 1 ;;
  esac
}

# --- state --------------------------------------------------------------------
TOTAL_IN=0 TOTAL_OUT=0 OK_COUNT=0 FAIL_COUNT=0
AI_JSON=""   # per-file AI result, consumed by dest_for/reporting

# Compress WORK into DST, picking the path by output extension.
#   PNG  -> pngquant (palette) + oxipng (lossless)
#   JPEG -> ImageMagick with mozjpeg-style settings at $JPEG_QUALITY
compress_to() {
  local work="$1" dst="$2" tmp="$3"
  case "$(ext_of "$dst")" in
    jpg|jpeg)
      # ImageMagick: strip metadata, progressive, quality-controlled JPEG.
      magick "$work" -strip -interlace Plane -sampling-factor 4:2:0 \
        -quality "$JPEG_QUALITY" "$dst" 2>/dev/null
      ;;
    *)
      # PNG path: lossy palette then lossless recompress.
      if ! pngquant --strip --skip-if-larger --force \
            --quality=70-95 --output "$tmp" "$COLORS" -- "$work" 2>/dev/null; then
        cp -- "$work" "$tmp"
      fi
      oxipng -o max --strip all --quiet "$tmp" --out "$dst" 2>/dev/null
      ;;
  esac
}

# Emit a WebP sibling of DST from WORK. Prefers cwebp, falls back to magick.
make_webp() {
  local work="$1" out="$2"
  if (( HAVE_CWEBP )); then
    cwebp -quiet -q 90 -alpha_q 100 "$work" -o "$out" 2>/dev/null
  else
    magick "$work" -quality 90 "$out" 2>/dev/null
  fi
}

# Emit an AVIF sibling of DST from WORK (ImageMagick only).
make_avif() {
  local work="$1" out="$2"
  magick "$work" -quality 55 "$out" 2>/dev/null
}

optimize_one() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    printf '%s✗%s %s %s(not a file)%s\n' "$RED" "$RESET" "$(basename "$src")" "$DIM" "$RESET"
    (( FAIL_COUNT++ )); return 1
  fi

  local ext; ext="$(ext_of "$dst")"
  local tmp resized; tmp="$(mktemp -t squish.XXXXXX).${ext}"; resized="$(mktemp -t squish.XXXXXX).${ext}"
  trap 'rm -f "$tmp" "$resized"' RETURN

  local in_dims out_dims resize_note=""
  in_dims="$(dims_of "$src")"

  # 0) optional resize. Never upscales past source width.
  local work="$src"
  if (( WIDTH > 0 )); then
    local srcw="${in_dims%%x*}"
    if [[ -n "$srcw" ]] && (( WIDTH < srcw )); then
      resize_to "$WIDTH" "$src" "$resized" && work="$resized"
    else
      resize_note=" ${DIM}(already ≤ ${WIDTH}px, kept)${RESET}"
    fi
  fi

  # 0.5) AI analysis (on the resized image, so we send few bytes). Runs before
  #      the final name is chosen so --apply can rename from the suggestion.
  AI_JSON=""
  if (( AI )); then
    AI_JSON="$(ai_analyze "$work")" || AI_JSON=""
    if (( APPLY )) && [[ -n "$AI_JSON" ]]; then
      local ai_name; ai_name="$(printf '%s' "$AI_JSON" | jq -r '.name // empty')"
      [[ -n "$ai_name" ]] && dst="$(RENAME="$ai_name" dest_for "$src")"
    fi
  fi

  # --- dry-run: report what WOULD happen, write nothing. ----------------------
  if (( DRY_RUN )); then
    local extras=""
    (( WEBP )) && extras+=" +webp"
    (( AVIF )) && extras+=" +avif"
    printf '%s◐%s %s%s%s %s→%s %s%s%s  %s%s%s%s\n' \
      "$YELLOW" "$RESET" "$DIM" "$(basename "$src")" "$RESET" \
      "$GRAY" "$RESET" "$BOLD" "$(basename "$dst")" "$RESET" \
      "$GRAY" "${in_dims}px${extras}" "$RESET" "$resize_note"
    (( OK_COUNT++ )); note ""; return 0
  fi

  # 1+2) compress into the final file (format-aware).
  compress_to "$work" "$dst" "$tmp"

  local in_b out_b pct; in_b=$(filesize "$src"); out_b=$(filesize "$dst")
  out_dims="$(dims_of "$dst")"
  pct=$(pct_saved "$in_b" "$out_b")

  TOTAL_IN=$(( TOTAL_IN + in_b )); TOTAL_OUT=$(( TOTAL_OUT + out_b )); (( OK_COUNT++ ))

  # header line: ✓ in-name → out-name  dims→dims
  local dimline=""
  [[ -n "$in_dims" ]] && dimline="${GRAY}${in_dims}"
  [[ -n "$out_dims" && "$out_dims" != "$in_dims" ]] && dimline="${dimline} → ${out_dims}"
  [[ -n "$dimline" ]] && dimline="${dimline}px${RESET}"
  local nameline; nameline="${DIM}$(basename "$src")${RESET} ${GRAY}→${RESET} ${BOLD}$(basename "$dst")${RESET}"
  printf '%s✓%s %s  %s%s\n' \
    "$GREEN" "$RESET" "$nameline" "$dimline" "$resize_note"

  # detail line: bar  in → out  (-NN%)  — the out column starts at a fixed offset
  # so the webp line below aligns its size under the PNG's output size.
  printf '   %s  %s%9s%s → %s%-9s%s  %s−%s%%%s\n' \
    "$(savings_bar "$pct")" \
    "$DIM" "$(human "$in_b")" "$RESET" \
    "$BOLD$GREEN" "$(human "$out_b")" "$RESET" \
    "$GREEN" "$pct" "$RESET"

  # 3) optional modern-format siblings (WebP / AVIF), size aligned under the output column
  if (( WEBP )); then
    local webp="${dst%.*}.webp" w_b wpct
    make_webp "$work" "$webp"
    w_b=$(filesize "$webp"); wpct=$(pct_saved "$in_b" "$w_b")
    printf '   %s└─ also .webp%s   %s→ %s%-9s%s  %s−%s%%%s\n' \
      "$GRAY" "$RESET" "$DIM" "$BOLD$CYAN" "$(human "$w_b")" "$RESET" "$CYAN" "$wpct" "$RESET"
  fi
  if (( AVIF )); then
    local avif="${dst%.*}.avif" a_b apct
    make_avif "$work" "$avif"
    a_b=$(filesize "$avif"); apct=$(pct_saved "$in_b" "$a_b")
    printf '   %s└─ also .avif%s   %s→ %s%-9s%s  %s−%s%%%s\n' \
      "$GRAY" "$RESET" "$DIM" "$BOLD$CYAN" "$(human "$a_b")" "$RESET" "$CYAN" "$apct" "$RESET"
  fi

  # 4) AI suggestions block
  if (( AI )) && [[ -n "$AI_JSON" ]] && [[ "$QUIET" -ne 1 ]]; then
    printf '   %s🧠 AI%s %s(%s · %s)%s\n' "$CYAN" "$RESET" "$DIM" "$AI_MODEL" "$CONTEXT" "$RESET"
    local v
    v="$(printf '%s' "$AI_JSON" | jq -r '.name   // empty')"; [[ -n "$v" ]] && printf '      %sname%s   %s%s\n' "$GRAY" "$RESET" "$BOLD" "$v"
    printf '%s' "$RESET"
    v="$(printf '%s' "$AI_JSON" | jq -r '.alt    // empty')"; [[ -n "$v" ]] && printf '      %salt%s    "%s"\n' "$GRAY" "$RESET" "$v"
    if printf '%s' "$AI_JSON" | jq -e '.kind' >/dev/null 2>&1; then
      printf '      %sparams%s %s → --colors %s%s\n' "$GRAY" "$RESET" \
        "$(printf '%s' "$AI_JSON" | jq -r '.kind')" \
        "$(printf '%s' "$AI_JSON" | jq -r '.suggested_colors')" \
        "$(printf '%s' "$AI_JSON" | jq -r 'if .suggest_webp then " --webp" else "" end')"
    fi
    v="$(printf '%s' "$AI_JSON" | jq -r '.html   // empty')"
    if [[ -n "$v" ]]; then
      printf '      %shtml%s\n' "$GRAY" "$RESET"
      printf '%s' "$v" | sed "s|SRC|$(basename "$dst")|g; s/^/        /"
      printf '\n'
    fi
    # If not applied, offer the ready command to apply the suggested name.
    if (( ! APPLY )); then
      local ai_name; ai_name="$(printf '%s' "$AI_JSON" | jq -r '.name // empty')"
      [[ -n "$ai_name" ]] && printf '      %sapply%s  squish "%s" --rename %s\n' "$GRAY" "$RESET" "$(basename "$src")" "$ai_name"
    fi
  fi
  note ""
}

# Normalize a string into a URL/bucket-safe kebab-case slug:
# lowercase, strip accents, spaces/underscores -> '-', drop other junk, squeeze dashes.
slugify() {
  printf '%s' "$1" \
    | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E "s/['\`^~\"]//g" \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

# Build the output file name (without extension) for a source, per --name-as/--rename.
build_stem() {
  local src="$1" base
  base="$(basename "$src")"; base="${base%.*}"      # original name, no extension

  # --rename replaces the base name outright (then still slugified for safety).
  [[ -n "$RENAME" ]] && base="$RENAME"

  case "$NAME_AS" in
    optimized) printf '%s.optimized' "$base" ;;
    plain)     printf '%s'            "$base" ;;
    slug)      printf '%s'            "$(slugify "$base")" ;;
    retina)    printf '%s@2x'         "$(slugify "$base")" ;;
    width)     printf '%s-%sw'        "$(slugify "$base")" "$WIDTH" ;;
  esac
}

dest_for() {
  local src="$1"
  # --output wins outright (explicit single path).
  [[ -n "$OUTPUT" ]] && { printf '%s' "$OUTPUT"; return; }
  local stem dir dst ext; stem="$(build_stem "$src")"; ext="$(out_ext_for "$src")"
  if [[ -n "$OUT_DIR" ]]; then dir="$OUT_DIR"; else dir="$(dirname "$src")"; fi
  dst="$dir/$stem.$ext"
  # Safety: never overwrite the source in place. If names collide (e.g. slug of an
  # already-clean name in the same dir), append -min so the original survives.
  if [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == "$(cd "$dir" 2>/dev/null && pwd)/$stem.$ext" ]]; then
    dst="$dir/$stem-min.$ext"
  fi
  printf '%s' "$dst"
}

# --- run ----------------------------------------------------------------------
# banner
note "${BOLD}${GREEN}▚ squish${RESET} ${DIM}image optimizer${RESET}"
{
  cfg="${GRAY}"
  cfg+="pngquant ${COLORS}c · oxipng max"
  (( WIDTH > 0 )) && cfg+=" · resize ${WIDTH}px"
  (( WEBP  > 0 )) && cfg+=" · +webp"
  (( AVIF  > 0 )) && cfg+=" · +avif"
  (( AI    > 0 )) && cfg+=" · 🧠 ai ${AI_PROVIDER}/${CONTEXT}"
  (( DRY_RUN > 0 )) && cfg+=" · ${YELLOW}dry-run${GRAY}"
  cfg+="${RESET}"
  note "  $cfg"
  note ""
}

for src in "${INPUTS[@]}"; do
  optimize_one "$src" "$(dest_for "$src")" || true
done

# --- summary ------------------------------------------------------------------
if [[ "$QUIET" -ne 1 && $(( OK_COUNT + FAIL_COUNT )) -gt 0 ]]; then
  if (( OK_COUNT > 0 )); then
    total_pct=$(pct_saved "$TOTAL_IN" "$TOTAL_OUT")
    saved=$(( TOTAL_IN - TOTAL_OUT ))
    printf '%s────────────────────────────────────────────%s\n' "$GRAY" "$RESET"
    printf '%s%d file%s optimized%s' "$BOLD" "$OK_COUNT" "$([[ $OK_COUNT -ne 1 ]] && echo s)" "$RESET"
    (( FAIL_COUNT > 0 )) && printf '%s, %d skipped%s' "$YELLOW" "$FAIL_COUNT" "$RESET"
    printf '  %s·%s  %s%s%s saved  %s(−%s%% total)%s\n' \
      "$GRAY" "$RESET" "$BOLD$GREEN" "$(human "$saved")" "$RESET" "$GREEN" "$total_pct" "$RESET"
    [[ -n "$OUT_DIR" ]] && printf '%s→ %s%s\n' "$DIM" "$OUT_DIR/" "$RESET"
  else
    printf '%s✗ nothing optimized (%d skipped)%s\n' "$RED" "$FAIL_COUNT" "$RESET"
  fi
fi

# Exit 0 if at least one file was optimized; 1 only if everything failed.
(( OK_COUNT > 0 )) && exit 0 || exit 1
