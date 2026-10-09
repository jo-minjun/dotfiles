#!/bin/bash
# chezmoi 관리 대상 BTT 프리셋을 현재 BTT 설정으로 다시 내보낸다
set -euo pipefail

BTT_CLI="/Applications/BetterTouchTool.app/Contents/SharedSupport/bin/bttcli"
EXPORT_WAIT_SECONDS=5
POLL_INTERVAL_SECONDS=0.1

# bttcli는 파일 쓰기를 끝내기 전에 반환하는 경우가 있어, 내보낸 파일에서 프리셋 이름이 읽힐 때까지 기다린다
wait_for_export() {
  local file="$1" name="$2"
  local deadline=$((SECONDS + EXPORT_WAIT_SECONDS))
  until [[ "$(jq -r '.BTTPresetName' "$file" 2>/dev/null)" == "$name" ]]; do
    ((SECONDS < deadline)) || return 1
    sleep "$POLL_INTERVAL_SECONDS"
  done
}

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

  if ! wait_for_export "$exported" "$name"; then
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
