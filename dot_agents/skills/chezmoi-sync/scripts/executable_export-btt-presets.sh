#!/bin/bash
# chezmoi 관리 대상 BTT 프리셋을 현재 BTT 설정으로 다시 내보낸다
set -euo pipefail

BTT_CLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"

[[ -x "$BTT_CLI" ]] || { echo "BetterTouchTool CLI 없음. 건너뜀."; exit 0; }
pgrep -x BetterTouchTool >/dev/null || { echo "BetterTouchTool 미실행. 건너뜀."; exit 0; }

echo "=== BTT 프리셋 내보내기 ==="

while IFS= read -r managed_path; do
  preset_file="$HOME/$managed_path"
  [[ -f "$preset_file" ]] || continue

  name=$(jq -r '.BTTPresetName' "$preset_file")
  uuid=$(jq -r '.BTTPresetUUID' "$preset_file")
  exported=$(mktemp)
  normalized=$(mktemp)

  "$BTT_CLI" export_preset name="$name" outputPath="$exported" compress=false includeSettings=true >/dev/null

  if [[ "$(jq -r '.BTTPresetName' "$exported" 2>/dev/null)" != "$name" ]]; then
    echo "  [!] $name 내보내기 실패. 기존 파일 유지."
    rm -f "$exported" "$normalized"
    continue
  fi

  # BTT가 내보낼 때마다 BTTPresetUUID를 새로 만들어 설정 변경 없이도 diff가 생기므로 기존 값을 유지한다
  jq --arg uuid "$uuid" '.BTTPresetUUID = $uuid' "$exported" > "$normalized"
  cat "$normalized" > "$preset_file"
  rm -f "$exported" "$normalized"
  echo "  [OK] $name"
done < <(chezmoi managed --include=files | grep '\.bttpreset$')

echo "=== 내보내기 완료 ==="
