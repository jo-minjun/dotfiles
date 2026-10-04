#!/bin/bash
# Claude Code status line: model | directory | git branch | context usage | 5h/7d rate limits
input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)

format_tokens() {
  local n="$1"
  case "$n" in ''|*[!0-9]*) return ;; esac
  if [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN { v = n / 1000000; if (v == int(v)) printf "%dM", v; else printf "%.1fM", v }'
  elif [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN { printf "%dK", n / 1000 }'
  else
    printf '%s' "$n"
  fi
}

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
  [ -n "$effort" ] && out="${out} ${YELLOW}(${effort})${RESET}"
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
    size_label=$(format_tokens "$ctx_size")
    ctx_text="ctx ${pct}%"
    [ -n "$size_label" ] && ctx_text="${ctx_text} / ${size_label}"
    out="${out}${color}${ctx_text}${RESET}"
  fi
fi

usage_segment() {
  local label="$1" value="$2" p c
  [ -z "$value" ] && return
  p=$(printf '%.0f' "$value" 2>/dev/null) || return
  if [ "$p" -ge 80 ]; then
    c="$RED"
  elif [ "$p" -ge 50 ]; then
    c="$YELLOW"
  else
    c="$GREEN"
  fi
  printf '%s%s %s%%%s' "$c" "$label" "$p" "$RESET"
}

five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)

for seg in "$(usage_segment "5h" "$five")" "$(usage_segment "7d" "$week")"; do
  if [ -n "$seg" ]; then
    [ -n "$out" ] && out="${out}${SEP}"
    out="${out}${seg}"
  fi
done

printf '%s\n' "$out"
