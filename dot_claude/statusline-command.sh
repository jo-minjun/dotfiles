#!/bin/bash
# Claude Code status line: model | directory | git branch | context usage
input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)

[ -z "$dir" ] && dir=$(pwd)

RESET=$'\033[0m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
SEP=" ${RESET}|${RESET} "

out=""

if [ -n "$model" ]; then
  out="${CYAN}${model}${RESET}"
fi

if [ -n "$dir" ]; then
  base=$(basename "$dir")
  [ -n "$out" ] && out="${out}${SEP}"
  out="${out}${BLUE}${base}${RESET}"

  branch=$(git --no-optional-locks -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    out="${out}${SEP}${MAGENTA}${branch}${RESET}"
  fi
fi

if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used" 2>/dev/null)
  if [ -n "$pct" ]; then
    if [ "$pct" -ge 80 ]; then
      color="$RED"
    elif [ "$pct" -ge 50 ]; then
      color="$YELLOW"
    else
      color="$GREEN"
    fi
    [ -n "$out" ] && out="${out}${SEP}"
    out="${out}${color}ctx ${pct}%${RESET}"
  fi
fi

printf '%s\n' "$out"
