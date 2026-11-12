#!/bin/bash
# ~/.claude/settings.json 은 modify_ 템플릿으로 관리해서 chezmoi re-add 가 소스를 갱신하지 않고 조용히 건너뛴다.
# 그래서 기기별 키(.chezmoidata.toml 의 claudeSettings.localKeys)를 뺀 본문을 소스에 직접 쓴다.
set -euo pipefail

target="$HOME/.claude/settings.json"
body="$(chezmoi source-path)/.chezmoitemplates/claude/settings.json"

echo "=== Claude Code 설정 본문 반영 ==="
if [[ ! -f "$target" ]]; then
  echo "  [SKIP] $target 이 없다"
  exit 0
fi

# 키 목록을 못 읽으면 기기별 키가 본문에 섞이므로 여기서 실패시킨다.
keys=$(chezmoi data --format json | jq -ce '.claudeSettings.localKeys | arrays')

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --sort-keys --argjson keys "$keys" 'delpaths([$keys[] | [.]])' "$target" > "$tmp"
# mktemp 의 600 권한이 소스로 옮겨 가지 않도록 내용만 덮어쓴다.
cat "$tmp" > "$body"
echo "  [OK] ${body#"$HOME"/}"
