#!/bin/bash
# modify_ 로 관리하는 파일은 chezmoi re-add 가 소스를 갱신하지 않고 조용히 건너뛴다.
# 그래서 기기마다 다른 값을 뺀 본문을 소스의 .chezmoitemplates 에 직접 쓴다.
set -euo pipefail

source_dir="$(chezmoi source-path)"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# mktemp 의 600 권한이 소스로 옮겨 가지 않도록 내용만 덮어쓴다.
write_body() {
  mkdir -p "$(dirname "$1")"
  cat "$tmp" > "$1"
  echo "  [OK] ${1#"$HOME"/}"
}

echo "=== modify_ 파일 본문 반영 ==="

# ~/.claude/settings.json: .chezmoidata.toml 의 claudeSettings.localKeys 를 뺀다 (dot_claude/modify_settings.json)
claude_target="$HOME/.claude/settings.json"
if [[ -f "$claude_target" ]]; then
  # 키 목록을 못 읽으면 기기별 키가 본문에 섞이므로 여기서 실패시킨다.
  keys=$(chezmoi data --format json | jq -ce '.claudeSettings.localKeys | arrays')
  jq --sort-keys --argjson keys "$keys" 'delpaths([$keys[] | [.]])' "$claude_target" > "$tmp"
  write_body "$source_dir/.chezmoitemplates/claude/settings.json"
else
  echo "  [SKIP] $claude_target 이 없다"
fi

# ~/.codex/config.toml: hooks.state.* 표의 trusted_hash 줄을 빼고 홈 경로를 템플릿으로 바꾼다 (dot_codex/modify_private_config.toml.tmpl)
codex_target="$HOME/.codex/config.toml"
if [[ -f "$codex_target" ]]; then
  if grep -q '{{' "$codex_target"; then
    echo "  [FAIL] $codex_target 에 '{{' 가 있어 템플릿 본문으로 쓸 수 없다" >&2
    exit 1
  fi
  awk '/^\[/ { table = $0 } table ~ /^\[hooks\.state\./ && /^trusted_hash[[:space:]]*=/ { next } { print }' "$codex_target" |
    sed -E "s#${HOME}([/\"])#{{ .chezmoi.homeDir }}\\1#g" > "$tmp"
  write_body "$source_dir/.chezmoitemplates/codex/config.toml"
else
  echo "  [SKIP] $codex_target 이 없다"
fi

# ~/.paseo/config.json: daemon.auth(비밀번호 해시)를 빼고 홈 경로를 템플릿으로 바꾼다 (private_dot_paseo/modify_private_config.json)
# 터미널 프로필 인자 {{{prompt}}} 의 {{ 가 템플릿 문법으로 읽히면 chezmoi 전체가 실패하므로, 홈 경로를 넣기 전에 {{ 를 먼저 이스케이프한다.
paseo_target="$HOME/.paseo/config.json"
if [[ -f "$paseo_target" ]]; then
  jq --sort-keys 'del(.daemon.auth)' "$paseo_target" |
    sed -E -e 's#\{\{#{{ "{{" }}#g' -e "s#${HOME}([/\"])#{{ .chezmoi.homeDir }}\\1#g" > "$tmp"
  write_body "$source_dir/.chezmoitemplates/paseo/config.json"
else
  echo "  [SKIP] $paseo_target 이 없다"
fi
