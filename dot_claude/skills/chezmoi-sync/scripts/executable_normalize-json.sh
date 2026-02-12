#!/bin/bash
# chezmoi re-add 전에 JSON 파일의 키를 정렬하여 불필요한 diff 방지
set -euo pipefail

normalize() {
  local file="$1"
  if [[ -f "$file" ]] && jq empty "$file" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    jq --sort-keys '.' "$file" > "$tmp" && mv "$tmp" "$file"
    echo "  [OK] $(basename "$file")"
  fi
}

echo "=== JSON 키 정렬 ==="

# chezmoi 관리 대상 중 JSON 파일 정규화
while IFS= read -r managed_path; do
  full_path="$HOME/$managed_path"
  if [[ "$full_path" == *.json && -f "$full_path" ]]; then
    normalize "$full_path"
  fi
done < <(chezmoi managed)

echo "=== 정규화 완료 ==="
