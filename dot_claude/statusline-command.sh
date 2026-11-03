#!/bin/bash
# Claude Code status line
#   line 1: directory | git branch
#   line 2: registry name | renamed session name
#   line 3: model | context usage | 5h/7d rate limits
input=$(cat)
# WorkLog: 사용량(rate_limits)을 저장한다. 출력이 없고 항상 0으로 끝나 상태 줄에 영향이 없다
printf '%s' "$input" | ~/.claude/skills/work-log/scripts/save_rate_limits.sh

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
session_name=$(printf '%s' "$input" | jq -r '.session_name // empty' 2>/dev/null)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)

# SendMessage는 UUID가 아니라 세션 레지스트리의 이름으로 세션을 찾는다
if [ -n "$session_id" ]; then
  registry_file=$(grep -l "\"$session_id\"" ~/.claude/sessions/*.json 2>/dev/null | head -n 1)
  if [ -n "$registry_file" ]; then
    registry_name=$(jq -r '.name // empty' "$registry_file" 2>/dev/null)
  fi
fi

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
BOLD=$'\033[1m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
SEP=" ${RESET}|${RESET} "

line1=""
line2=""
line3=""

if [ -n "$dir" ]; then
  case "$dir" in
    "$HOME") display_dir="~" ;;
    "$HOME"/*) display_dir="~${dir#"$HOME"}" ;;
    *) display_dir="$dir" ;;
  esac
  line1="${BLUE}${display_dir}${RESET}"

  branch=$(git --no-optional-locks -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    line1="${line1}${SEP}${MAGENTA}${branch}${RESET}"
  fi
fi

[ -n "$registry_name" ] && line2="${BOLD}${registry_name}${RESET}"

if [ -n "$session_name" ] && [ "$session_name" != "$registry_name" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}"
  line2="${line2}${BOLD}${session_name}${RESET}"
fi

if [ -n "$model" ]; then
  line3="${CYAN}${model}${RESET}"
  [ -n "$effort" ] && line3="${line3} ${YELLOW}(${effort})${RESET}"
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
    [ -n "$line3" ] && line3="${line3}${SEP}"
    size_label=$(format_tokens "$ctx_size")
    ctx_text="ctx ${pct}%"
    [ -n "$size_label" ] && ctx_text="${ctx_text} / ${size_label}"
    line3="${line3}${color}${ctx_text}${RESET}"
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
    [ -n "$line3" ] && line3="${line3}${SEP}"
    line3="${line3}${seg}"
  fi
done

[ -n "$line1" ] && printf '%s\n' "$line1"
[ -n "$line2" ] && printf '%s\n' "$line2"
[ -n "$line3" ] && printf '%s\n' "$line3"
exit 0
