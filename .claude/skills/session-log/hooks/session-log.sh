#!/bin/sh
# Stop hook: keep one note per session under the Obsidian vault so that every
# session that completed at least one turn leaves its cwd, branch and title
# behind, even when nobody ran /handoff for it. Turns that end in an
# interrupt or an API error do not fire Stop and so do not refresh the note.
#
# Runs on Stop rather than SessionEnd: SessionEnd does not fire when the
# terminal is closed or the process is killed, and those are exactly the
# sessions that otherwise vanish without a trace.
set -eu

root="$HOME/vault/obsidian/claude"

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$sid" ] || exit 0

title=
started=
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # ai-title is an undocumented transcript entry, so a missing one only leaves
  # the title blank. grep first: running jq over the whole transcript on every
  # turn gets slow once it grows to several MB.
  title=$(grep -F '"type":"ai-title"' "$transcript" | tail -n 1 |
    jq -r '.aiTitle // empty' 2>/dev/null) || title=
  started=$(jq -rn '
    first(inputs | .timestamp? // empty)
    | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
    | strflocaltime("%Y-%m-%dT%H:%M:%S")' "$transcript" 2>/dev/null) || started=
fi

branch=$(git -C "$cwd" branch --show-current 2>/dev/null) || branch=

# /handoff and /pickup list the session id in the work note's frontmatter.
work=$(grep -rlF -- "$sid" "$root/work" 2>/dev/null | head -n 1) || work=
[ -z "$work" ] || work="[[$(basename "$work" .md)]]"

mkdir -p "$root/sessions"
note="$root/sessions/$sid.md"
# A leading dot keeps Obsidian from indexing the half-written file.
tmp="$root/sessions/.$sid.md.tmp"

# JSON strings are valid YAML double-quoted scalars, so @json does the escaping.
jq -rn \
  --arg sid "$sid" --arg title "$title" --arg cwd "$cwd" --arg branch "$branch" \
  --arg started "$started" --arg updated "$(date +%Y-%m-%dT%H:%M:%S)" \
  --arg work "$work" '
  "---",
  "session_id: \($sid | @json)",
  "title: \($title | @json)",
  "cwd: \($cwd | @json)",
  "branch: \($branch | @json)",
  "started: \($started | @json)",
  "updated: \($updated | @json)",
  "work: \($work | @json)",
  "---",
  "",
  "`cd \($cwd | @sh) && claude --resume \($sid)`"
' >"$tmp"
mv "$tmp" "$note"
