# Dotfiles

chezmoi로 관리하는 macOS 개발 환경. 명령어 하나로 새 머신 설정 완료.

## 사전 요구사항

- 1Password 계정: 시크릿과 라이선스를 1Password에서 자동으로 가져옵니다.
- GitHub 개인 계정 `jo-minjun`: private 저장소인 업무 설정(dotfiles-work)을 이 계정 토큰으로 클론합니다.
- GitHub 회사 계정: `~/Projects/work/` 하위 저장소에서 사용합니다.

## 설치

1. 설치 명령을 실행합니다. 이름, 개인 이메일, 회사 이메일을 입력합니다.
   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jo-minjun
   ```
   1Password 앱과 CLI가 설치된 뒤 "1Password CLI에 로그인되지 않았습니다" 메시지와 함께 apply가 멈춥니다. 정상 동작입니다.
2. 1Password 앱을 실행하고 로그인합니다.
3. 1Password 설정 > 개발자 > "CLI와의 생체 인증 잠금 해제"를 활성화합니다.
4. `chezmoi apply`를 다시 실행합니다. 다음 순서로 진행됩니다.
   1. brew bundle로 CLI 도구와 앱 설치
   2. `gh auth login` 실행: **개인 계정 `jo-minjun`으로 로그인**합니다
   3. 외부 에이전트 스킬 설치
   4. 업무 설정(dotfiles-work)을 `~/.local/share/chezmoi-work`에 클론하고 적용
5. 회사 GitHub 계정을 추가로 로그인합니다. `~/Projects/work/` 하위에서 이 계정으로 자동 전환됩니다.
   ```bash
   gh auth login
   ```

> 4-2에서 회사 계정으로 먼저 로그인하면 업무 설정은 건너뜁니다. `gh auth login`으로 `jo-minjun`을 추가하고 `chezmoi apply`를 다시 실행합니다.

## 설치되는 것들

### CLI 도구

| 카테고리 | 패키지 |
|----------|--------|
| 개발 | node, bun, pnpm, maven, mise, rustup |
| 언어 서버 | jdtls, kotlin-language-server, python-lsp-server, typescript-language-server, intelephense (npm) |
| 클라우드/인프라 | awscli, aws-iam-authenticator, kubernetes-cli, kubectx, k9s, helm, argocd, kafkactl, terraform, databricks |
| API | bruno-cli, @modelcontextprotocol/inspector (npm) |
| DB | libpq, mysql-client, dbvr (DBeaver Community CLI, GitHub 릴리스) |
| AI | Claude Code (설치 스크립트), codex |
| 배포 | vercel (npm) |
| 네트워크 | tailscale |
| 유틸리티 | chezmoi, gh, jq, bat, delta, ripgrep, fd, fzf, zoxide, tree, ouch, yazi, lazygit, mermaid-cli, 1password-cli |
| 파일 미리보기 | ffmpeg, imagemagick, poppler, resvg, sevenzip |

### 앱

| 카테고리 | 앱 | 설명 |
|----------|----|------|
| AI | Claude | AI 어시스턴트 |
|  | Orca | AI 에이전트 워크트리 관리 |
|  | ego lite | AI 에이전트용 브라우저 (공식 설치 스크립트, 온보딩은 수동) |
| 개발 | Ghostty | 터미널 |
|  | JetBrains Toolbox | IDE 관리 |
|  | Docker Desktop | 컨테이너 |
|  | DBeaver Community | DB 클라이언트 |
|  | Bruno | API 테스트 |
|  | Postman | API 테스트 |
| 생산성 | 1Password | 패스워드 관리 |
|  | BetterTouchTool | 제스처/단축키 |
|  | Lockpaw | 화면 잠금 (BTT Cmd+Ctrl+Q, 에이전트 알림) |
|  | Ice | 메뉴 막대 정리 |
|  | Notion | 노트 |
|  | Obsidian | 노트 |
|  | Plaud | 회의 녹음·요약 |
| 커뮤니케이션 | Slack | 메신저 |
|  | Discord | 메신저 |
| 미디어 | IINA | 동영상 플레이어 |
| 네트워크 | Tailscale | VPN |

## 설정되는 것들

| 항목 | 내용 |
|------|------|
| Touch ID sudo | 터미널에서 sudo 시 Touch ID 사용 (`/etc/pam.d/sudo_local`, macOS 업데이트 후에도 유지) |
| oh-my-zsh + Powerlevel10k | 쉘 테마 |
| Git 이메일 분리 | `~/Projects/work/` → 회사 이메일, 그 외 → 개인 이메일 |
| Ghostty | JetBrains Mono, Idea 테마 |
| Claude Code | LSP, statusline, 권한 설정, 서브에이전트, 스킬 |
| 에이전트 스킬 | 직접 만든 스킬만 저장소에 둔다. 외부 스킬은 `~/.agents/.skill-lock.json`의 출처에서 `npx skills`로 설치하고, 업데이트는 `npx skills update -g`로 한다 |
| 업무 설정 | private 저장소 [dotfiles-work](https://github.com/jo-minjun/dotfiles-work)를 별도 chezmoi 소스로 적용 (아래 참고) |
| mise | 기본 도구(node lts, java corretto-25, python 3.15, kotlin 2.4), `~/Projects`·`~/orca/workspaces` 하위 설정 자동 신뢰 |
| BetterTouchTool | 라이선스 자동 설치, 프리셋 자동 임포트 (bttcli Socket Server·스크립트 임포트 확인 생략 설정 활성화) |

### 디렉토리 구조

```
~/
├── Projects/
│   ├── work/      # 회사 프로젝트 (회사 이메일 자동 적용)
│   └── me/        # 개인 프로젝트
├── Shell/
│   ├── commands.sh # 커스텀 함수
│   ├── aliases.sh  # alias 정의
│   ├── exports.sh  # 환경변수 정의
│   └── work.sh     # 업무 전용 설정 (dotfiles-work)
└── .secrets.zsh   # 시크릿 (1Password에서 자동 로드)
```

## 시크릿 설정 (1Password)

chezmoi가 1Password에서 시크릿을 자동으로 가져옵니다.

### 최초 설정

1. 1Password "Secrets" vault에 아이템 생성:
   - **Secure Note**: BetterTouchTool License
   - 업무 설정에 필요한 아이템은 dotfiles-work README를 참고
2. 1Password CLI 인증:
   ```bash
   eval $(op signin)
   ```
3. `chezmoi apply` 실행

셸 환경변수로 쓸 비밀값은 `dot_secrets.zsh.tmpl`에 `onepasswordRead`로 추가한다. `~/.secrets.zsh`는 apply 때마다 다시 생성되므로 직접 수정하지 않는다.

### 관리되는 시크릿

| 타입 | 아이템 | 용도 |
|------|--------|------|
| Secure Note | BetterTouchTool License | BTT 라이선스 자동 설치 |

## 일상 사용

```bash
# 원격 변경 받기 + 적용 (업무 설정도 함께 pull·적용)
chezmoi update

# 적용 (업무 설정도 함께 적용)
chezmoi apply

# 설정 파일 수정
chezmoi edit ~/.zshrc

# 변경사항 미리보기
chezmoi diff

# 소스 디렉토리 이동
chezmoi cd

# 변경사항 커밋 (형식: <type>: <subject>, 예: feat: ghostty 테마 변경)
git add . && git commit -m "feat: <변경 내용>" && git push

# 업무 설정 파일 다루기 (dotfiles-work 소스)
chezmoi_work edit ~/.aws/config
chezmoi_work diff
chezmoi_work apply

# 두 저장소의 로컬 변경 re-add 후 커밋·푸시 (커밋 메시지 입력)
chezmoi_sync
```

> `chezmoi diff`, `chezmoi edit`로는 업무 설정 파일(`~/.aws/config`, `~/.pgpass` 등)을 다룰 수 없습니다. 공개 소스가 관리하지 않기 때문입니다. 업무 설정 파일에는 `chezmoi_work`를 사용합니다.

## 업무 설정 (dotfiles-work)

회사 계정, 인프라 정보, 업무 스킬은 공개 저장소에 두지 않고 private 저장소 `jo-minjun/dotfiles-work`에 둔다.

- `chezmoi apply`의 마지막 단계(`.chezmoiscripts/work/`)에서 `~/.local/share/chezmoi-work`에 클론(이후에는 `git pull --ff-only`)하고 별도 chezmoi 소스로 적용한다
- 상태 파일은 `~/.config/chezmoi/chezmoistate-work.boltdb`로 분리하고, 설정 데이터(`chezmoi.toml`)는 공유한다
- gh에 `jo-minjun` 계정이 로그인되어 있지 않거나 저장소 접근 권한이 없으면 건너뛴다
