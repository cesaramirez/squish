#compdef squish
# zsh completion for squish. Kept in sync with squish.sh's flags by
# tests/completions.bats. Self-contained — does not call the squish binary.
_squish() {
  _arguments -s \
    '(-w --width)'{-w,--width}'[resize to N px wide before compressing]:width:' \
    '(-r --retina)'{-r,--retina}'[with --display, target 2x that width]' \
    '--display[intended display width in px]:px:' \
    '(-c --colors)'{-c,--colors}'[PNG palette size (default 128)]:colors:' \
    '--jpeg-quality[JPEG output quality 1-100]:quality:' \
    '--webp[also emit a .webp sibling]' \
    '--avif[also emit an .avif sibling]' \
    '--dry-run[show what would happen without writing]' \
    '(-d --out-dir)'{-d,--out-dir}'[write all outputs into DIR]:dir:_files -/' \
    '(-o --output)'{-o,--output}'[output path (single input)]:file:_files' \
    '--name-as[output naming mode]:mode:(slug optimized plain retina width)' \
    '--rename[name the output yourself]:name:' \
    '(-R --recursive)'{-R,--recursive}'[descend into directory inputs]' \
    '--watch[optimize, then re-optimize on change]' \
    '--ai[analyze the image (vision AI or local heuristic)]' \
    '--apply[apply the AI-suggested name automatically]' \
    '--context[context for AI naming]:context:(auto general email-signature web hero icon avatar)' \
    '--ai-fields[comma list of fields to request]:fields:' \
    '--ai-provider[AI provider]:provider:(auto openai anthropic)' \
    '--ai-model[model override]:model:' \
    '--no-cache[bypass the AI result cache]' \
    '--no-color[disable colored output]' \
    '(-q --quiet)'{-q,--quiet}'[only print per-file result lines]' \
    '(-V --version)'{-V,--version}'[print the version and exit]' \
    '(-h --help)'{-h,--help}'[show help]' \
    '*:image:_files -g "*.(png|jpg|jpeg|PNG|JPG|JPEG)"'
}
_squish "$@"
