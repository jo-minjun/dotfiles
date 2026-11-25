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

# Orca 앱이 settings.json·hooks.json 에 넣는 훅은 앱이 다시 쓰는 값이라 본문에서 뺀다.
# modify_ 템플릿은 apply 때 현재 파일의 Orca 훅을 그대로 유지한다.
CLAUDE_ORCA_HOOK_MARKER=".orca/agent-hooks/"
CODEX_ORCA_HOOK_MARKER="orca-agent-hook"

# ~/.claude/settings.json: .chezmoidata.toml 의 claudeSettings.localKeys 와 Orca 훅을 뺀다 (dot_claude/modify_settings.json)
claude_target="$HOME/.claude/settings.json"
if [[ -f "$claude_target" ]]; then
  # 키 목록을 못 읽으면 기기별 키가 본문에 섞이므로 여기서 실패시킨다.
  keys=$(chezmoi data --format json | jq -ce '.claudeSettings.localKeys | arrays')
  jq --sort-keys --argjson keys "$keys" --arg marker "$CLAUDE_ORCA_HOOK_MARKER" '
    delpaths([$keys[] | [.]])
    | if has("hooks") then
        .hooks |= (map_values(map(select(tojson | contains($marker) | not)))
                   | with_entries(select(.value | length > 0)))
      else . end
  ' "$claude_target" > "$tmp"
  write_body "$source_dir/.chezmoitemplates/claude/settings.json"
else
  echo "  [SKIP] $claude_target 이 없다"
fi

# ~/.agents/.skill-lock.json: 스킬마다 .chezmoidata.toml 의 skillLock.localFields 를 뺀다 (dot_agents/modify_private_dot_skill-lock.json)
lock_target="$HOME/.agents/.skill-lock.json"
if [[ -f "$lock_target" ]]; then
  # 필드 목록을 못 읽으면 기기별 값이 본문에 섞이므로 여기서 실패시킨다.
  fields=$(chezmoi data --format json | jq -ce '.skillLock.localFields | arrays')
  jq --sort-keys --argjson fields "$fields" '.skills |= map_values(delpaths([$fields[] | [.]]))' "$lock_target" > "$tmp"
  write_body "$source_dir/.chezmoitemplates/agents/skill-lock.json"
else
  echo "  [SKIP] $lock_target 이 없다"
fi

# ~/.codex/config.toml: Orca 훅의 hooks.state.* 표와 trusted_hash 줄을 빼고 홈 경로를 템플릿으로 바꾼다 (dot_codex/modify_private_config.toml.tmpl)
codex_target="$HOME/.codex/config.toml"
codex_hooks="$HOME/.codex/hooks.json"
if [[ -f "$codex_target" ]]; then
  if grep -q '{{' "$codex_target"; then
    echo "  [FAIL] $codex_target 에 '{{' 가 있어 템플릿 본문으로 쓸 수 없다" >&2
    exit 1
  fi
  # hooks.state 표 이름은 "<hooks.json 경로>:<snake_case 이벤트>:<항목 번호>:<훅 번호>" 이다.
  orca_tables=""
  if [[ -f "$codex_hooks" ]]; then
    orca_tables=$(jq -r --arg file "$codex_hooks" --arg marker "$CODEX_ORCA_HOOK_MARKER" '
      (.hooks // {}) | to_entries[]
      | (.key | gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; "\(.a)_\(.b)") | ascii_downcase) as $event
      | .value | to_entries[] | .key as $entry
      | (.value.hooks // []) | to_entries[]
      | select((.value.command // "") | contains($marker))
      | "[hooks.state.\"\($file):\($event):\($entry):\(.key)\"]"
    ' "$codex_hooks")
  fi
  # 뺀 표 앞의 빈 줄이 겹치거나 파일 끝에 남지 않도록 빈 줄은 다음 출력 줄 앞에서만 쓴다.
  # BSD awk 는 -v 값에 줄바꿈을 받지 않아 환경 변수로 넘긴다.
  ORCA_TABLES="$orca_tables" awk '
    BEGIN { n = split(ENVIRON["ORCA_TABLES"], names, "\n"); for (i = 1; i <= n; i++) if (names[i] != "") skip[names[i]] = 1 }
    /^\[/ { table = $0; skipping = (table in skip) }
    skipping { next }
    table ~ /^\[hooks\.state\./ && /^trusted_hash[[:space:]]*=/ { next }
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    { printf "%s", blanks; blanks = ""; print }
  ' "$codex_target" |
    sed -E "s#${HOME}([/\"])#{{ .chezmoi.homeDir }}\\1#g" > "$tmp"
  write_body "$source_dir/.chezmoitemplates/codex/config.toml"
else
  echo "  [SKIP] $codex_target 이 없다"
fi
