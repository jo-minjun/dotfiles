# Dotfiles

chezmoi로 관리하는 macOS 개발 환경. 명령어 하나로 새 머신 설정 완료.

## 사전 요구사항

1Password 계정이 필요합니다. 시크릿과 라이선스가 1Password에서 자동으로 로드됩니다.

chezmoi가 자동으로 설치하지만, 1Password 로그인은 수동으로 해야 합니다:

1. `chezmoi apply` 실행 (1Password 앱/CLI 자동 설치)
2. 1Password 앱 실행 → 로그인
3. 설정 > 개발자 > "CLI와의 생체 인증 잠금 해제" 활성화
4. `chezmoi apply` 다시 실행

## 설치

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jo-minjun
```

## 설치되는 것들

### CLI 도구

| 카테고리 | 패키지 |
|----------|--------|
| 개발 | node, bun, pnpm, maven, mise, jenv, rustup |
| 언어 서버 | jdtls, kotlin-language-server, python-lsp-server, typescript-language-server, intelephense (npm) |
| 클라우드/인프라 | awscli, aws-iam-authenticator, kubernetes-cli, kubectx, k9s, helm, kafkactl, terraform |
| API | bruno-cli, @modelcontextprotocol/inspector (npm) |
| DB | libpq, mysql-client |
| AI | Claude Code (설치 스크립트), codex |
| 배포 | vercel (npm) |
| 네트워크 | tailscale |
| 유틸리티 | chezmoi, gh, jq, bat, delta, ripgrep, fd, fzf, zoxide, tree, ouch, yazi, lazygit, mermaid-cli, 1password-cli |
| 파일 미리보기 | ffmpeg, imagemagick, poppler, resvg, sevenzip |

### 앱

| 앱 | 설명 |
|----|------|
| 1Password | 패스워드 관리 |
| BetterTouchTool | 제스처/단축키 |
| Bruno | API 테스트 |
| Claude | AI 어시스턴트 |
| Discord | 메신저 |
| Docker Desktop | 컨테이너 |
| ego lite | AI 에이전트용 브라우저 (공식 설치 스크립트, 온보딩은 수동) |
| Ghostty | 터미널 |
| Ice | 메뉴 막대 정리 |
| IINA | 동영상 플레이어 |
| JetBrains Toolbox | IDE 관리 |
| Notion | 노트 |
| Obsidian | 노트 |
| Plaud | 회의 녹음·요약 |
| Postman | API 테스트 |
| Slack | 메신저 |
| Tailscale | VPN |

## 설정되는 것들

| 항목 | 내용 |
|------|------|
| Touch ID sudo | 터미널에서 sudo 시 Touch ID 사용 |
| oh-my-zsh + Powerlevel10k | 쉘 테마 |
| Git 이메일 분리 | `~/Projects/work/` → 회사 이메일, 그 외 → 개인 이메일 |
| Ghostty | JetBrains Mono, Idea 테마 |
| Claude Code | LSP, statusline, 권한 설정, 서브에이전트, 스킬 |
| mise | 기본 도구(node lts, java corretto-25, python 3.15, kotlin 2.4), `~/Projects`·`~/orca/workspaces` 하위 설정 자동 신뢰 |
| 1Password 시크릿 | Docker Hub |
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
│   └── exports.sh  # 환경변수 정의
└── .secrets.zsh   # 시크릿 (1Password에서 자동 로드)
```

## 시크릿 설정 (1Password)

chezmoi가 1Password에서 시크릿을 자동으로 가져옵니다.

### 최초 설정

1. 1Password "Secrets" vault에 아이템 생성:
   - **Login 아이템**: Docker Hub, GitHub Token
   - **Secure Note**: BetterTouchTool License
2. 1Password CLI 인증:
   ```bash
   eval $(op signin)
   ```
3. `chezmoi apply` 실행

### 관리되는 시크릿

| 타입 | 아이템 | 용도 |
|------|--------|------|
| Login | Docker Hub | Docker 이미지 푸시 |
| Secure Note | BetterTouchTool License | BTT 라이선스 자동 설치 |

## 일상 사용

```bash
# 설정 파일 수정
chezmoi edit ~/.zshrc

# 변경사항 미리보기
chezmoi diff

# 적용
chezmoi apply

# 소스 디렉토리 이동
chezmoi cd

# 변경사항 커밋
git add . && git commit -m "Update dotfiles" && git push

# 로컬 변경 re-add 후 커밋·푸시 (커밋 메시지 입력)
chezmoi_sync
```
