#!/bin/sh
# PostToolUse hook: run the global textlint (preset-ai-words-ja) over Markdown
# that Claude just wrote, and hand the findings back to Claude to fix.
set -eu

file=$(jq -r '.tool_input.file_path // empty')

case "$file" in
  *.md) ;;
  *) exit 0 ;;
esac

# textlint prints its help instead of linting when the input is empty.
[ -s "$file" ] || exit 0

if [ ! -x "$HOME/.config/textlint/node_modules/.bin/textlint" ]; then
  # Exit 1 is non-blocking: warn the user instead of stopping every edit.
  echo "textlint-ai-words: not installed yet. Run: mise run textlint-global" >&2
  exit 1
fi

# --stdin keeps textlint from expanding the path as a glob: a name containing
# [ ] would miss the file, and one containing * would pull in unrelated ones.
out=$("$HOME/.local/bin/textlint-ja" --stdin --stdin-filename "$file" --format json <"$file" 2>&1) \
  && status=0 || status=$?

[ "$status" -eq 0 ] && exit 0

# textlint exits 1 both for lint findings and for its own failures (an
# unloadable config, no rules, ...), so tell them apart by whether the output
# parses as a lint result rather than by the exit code.
findings=$(printf '%s' "$out" | jq -r '
  .[]?.messages[]? | "  \(.line):\(.column)  \(.message)  [\(.ruleId)]"' 2>/dev/null) || findings=

if [ -n "$findings" ]; then
  printf '%s\n%s\n' "$file" "$findings" >&2
  exit 2
fi

# Not findings: the setup is broken, which is not Claude's to fix.
printf '%s\n' "$out" >&2
exit 1
