# bash completion for squish. Kept in sync with squish.sh's flags by
# tests/completions.bats. Self-contained — does not call the squish binary.
_squish() {
  local cur prev flags
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  flags="--ai --ai-fields --ai-model --ai-provider --apply --avif --colors \
--context --display --dry-run --help --jpeg-quality --name-as --no-cache \
--no-color --out-dir --output --quiet --recursive --rename --retina --version \
--watch --webp --width"

  case "$prev" in
    --name-as)     COMPREPLY=($(compgen -W "slug optimized plain retina width" -- "$cur")); return ;;
    --context)     COMPREPLY=($(compgen -W "auto general email-signature web hero icon avatar" -- "$cur")); return ;;
    --ai-provider) COMPREPLY=($(compgen -W "auto openai anthropic" -- "$cur")); return ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "$flags" -- "$cur"))
  else
    COMPREPLY=($(compgen -f -X '!*.@(png|jpg|jpeg|PNG|JPG|JPEG)' -- "$cur"))
  fi
}
complete -F _squish squish
