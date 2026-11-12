# 비밀값·회사 정보 금지
- 이 저장소는 공개 저장소다. 비밀값과 회사 정보를 어떤 파일에도 절대 넣지 마라. 설정 파일뿐 아니라 `docs/`의 설계·계획 문서, 주석, 예시, 커밋 메시지도 포함한다
  - 비밀값: 비밀번호, 토큰, API 키, 인증서, 개인 키, 접속 정보
  - 회사 정보: 클라우드 계정 ID, 내부 도메인, 내부 저장소·서비스 이름, 회사 계정명, 인프라 구성
- 비밀값은 1Password Secrets vault에 두고 템플릿에서 `onepasswordRead`로 읽어라. 기존 값을 옮겨 적을 때도 실제 값 대신 `<REDACTED>` 같은 자리표시자를 써라
- 회사 정보는 private 저장소 `jo-minjun/dotfiles-work`(소스 `~/.local/share/chezmoi-work`)에 두어라
- 커밋 전에 `git diff --staged`로 위 항목이 섞여 있는지 확인하라. 섞여 있으면 커밋하지 말고 사용자에게 알려라

# 기기마다 값이 다른 설정 파일 (modify_)
- 아래 파일은 `modify_`로 관리한다. `chezmoi re-add`는 이 파일을 건너뛰므로, 대상 파일을 고친 뒤 `~/.claude/skills/chezmoi-sync/scripts/capture-modify-files.sh`로 본문에 반영하라
  - `~/.claude/settings.json`: 본문 `.chezmoitemplates/claude/settings.json`, 템플릿 `dot_claude/modify_settings.json`. 기기마다 따로 두는 키는 `.chezmoidata.toml`의 `claudeSettings.localKeys`에서 바꿔라. 본문에 그 키를 넣으면 apply 때 기기 값이 이긴다
  - `~/.codex/config.toml`: 본문 `.chezmoitemplates/codex/config.toml`, 스크립트 `dot_codex/modify_private_config.toml.tmpl`. `hooks.state.*` 표의 `trusted_hash`는 기기의 `~/.codex/hooks.json`으로 정해지므로 본문에 넣지 마라
- 본문 파일을 지우거나 옮기면 그 파일을 `include`하는 `.chezmoiscripts`도 같이 고쳐라. 고치지 않으면 apply가 템플릿 오류로 실패한다

# Brewfile
- `dot_Brewfile`에 서드파티 tap(homebrew/core·cask 외)의 formula/cask를 추가하거나 수정할 때는 tap 신뢰 선언을 확인하라
  - tap 줄과 해당 formula/cask 줄 모두에 `trusted: true`를 붙여라 (예: `tap "databricks/tap", trusted: true`, `brew "databricks/tap/databricks", trusted: true`)
  - 누락되면 `brew bundle`이 `Refusing to load formula ... from untrusted tap` 오류로 실패하고, chezmoi apply의 brew-bundle 스크립트가 중단되어 이후 스크립트도 실행되지 않는다
