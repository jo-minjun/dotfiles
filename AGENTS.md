# Brewfile
- `dot_Brewfile`에 서드파티 tap(homebrew/core·cask 외)의 formula/cask를 추가하거나 수정할 때는 tap 신뢰 선언을 확인하라
  - tap 줄과 해당 formula/cask 줄 모두에 `trusted: true`를 붙여라 (예: `tap "databricks/tap", trusted: true`, `brew "databricks/tap/databricks", trusted: true`)
  - 누락되면 `brew bundle`이 `Refusing to load formula ... from untrusted tap` 오류로 실패하고, chezmoi apply의 brew-bundle 스크립트가 중단되어 이후 스크립트도 실행되지 않는다
