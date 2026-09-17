#!/bin/sh
# PostToolUse hook: run the global textlint (preset-ai-words-ja) over the
# Japanese prose Claude just wrote — Markdown documents and source code
# comments alike — and hand the findings back to Claude to fix.
set -eu

file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0

# textlint prints its help instead of linting when the input is empty.
[ -s "$file" ] || exit 0

case "$file" in
  *.md)
    # --stdin keeps textlint from expanding the path as a glob: a name
    # containing [ ] would miss the file, and one containing * would pull in
    # unrelated ones.
    out=$("$HOME/.local/bin/textlint-ja" \
      --stdin --stdin-filename "$file" --format json <"$file" 2>&1) \
      && status=0 || status=$?
    ;;
  *)
    # Which files carry comments is textlint-comments' business; it exits 0
    # for the ones it does not handle.
    out=$("$HOME/.local/bin/textlint-comments" "$file" --format json 2>&1) \
      && status=0 || status=$?
    ;;
esac

[ "$status" -eq 0 ] && exit 0

# textlint exits 1 both for lint findings and for its own failures (an
# unloadable config, a toolchain that is not installed yet, ...), so tell them
# apart by whether the output parses as a lint result rather than by the code.
findings=$(printf '%s' "$out" | jq -r '
  .[]?.messages[]? | "  \(.line):\(.column)  \(.message)  [\(.ruleId)]"' 2>/dev/null) || findings=

if [ -n "$findings" ]; then
  printf '%s\n%s\n' "$file" "$findings" >&2
  exit 2
fi

# Not findings: the setup is broken, which is not Claude's to fix.
printf '%s\n' "$out" >&2
exit 1
