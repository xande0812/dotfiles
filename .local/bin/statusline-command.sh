#!/bin/bash

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$cwd")

branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
fi

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

DIM='\033[2m'
RESET='\033[0m'

location="$dir_name"
if [ -n "$branch" ]; then
  location="$dir_name / $branch"
fi

ctx=""
if [ -n "$used" ]; then
  ctx=$(printf 'ctx %.0f%%' "$used")
fi

out=$(printf '%s | %s' "$model" "$location")
if [ -n "$ctx" ]; then
  out=$(printf '%s | %s' "$out" "$ctx")
fi

printf "${DIM}%s${RESET}" "$out"
