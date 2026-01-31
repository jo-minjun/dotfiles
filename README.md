# Dotfiles

chezmoi로 관리하는 macOS 개발 환경. 명령어 하나로 새 머신 설정 완료.

## 설치

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jo-minjun
```

## 설치되는 것들

### CLI 도구

| 카테고리 | 패키지 |
|----------|--------|
| 개발 | node, node@24, bun, pnpm, maven, mise, jenv |
| 언어 서버 | jdtls, kotlin-language-server, python-lsp-server, typescript-language-server |
| 클라우드/인프라 | awscli, aws-iam-authenticator, kubernetes-cli, kubectx, k9s, kafkactl, docker-desktop |
| DB | libpq, mysql-client |
| AI | aichat, claude-squad, opencode |
| 유틸리티 | chezmoi, gh, tmux, tree, rustup-init, 1password-cli |

### 앱

| 앱 | 설명 |
|----|------|
| 1Password | 패스워드 관리 |
| BetterTouchTool | 제스처/단축키 |
| Claude, Claude Code | AI 어시스턴트 |
| Cursor | AI 코드 에디터 |
| Docker Desktop | 컨테이너 |
| Ghostty | 터미널 |
| JetBrains Toolbox | IDE 관리 |
| Naver Whale | 브라우저 |
| Notion | 노트 |
| Postman | API 테스트 |
| Slack | 메신저 |
| Google Drive | 클라우드 스토리지 |

### 웹앱 (Pake)

Pake로 빌드되는 네이티브 웹앱:
- Google Gemini

## 설정되는 것들

| 항목 | 내용 |
|------|------|
| Touch ID sudo | 터미널에서 sudo 시 Touch ID 사용 |
| oh-my-zsh + Powerlevel10k | 쉘 테마 |
| Git 이메일 분리 | `~/Projects/work/` → 회사 이메일, 그 외 → 개인 이메일 |
| Ghostty | JetBrains Mono, Idea 테마 |
| Claude Code | LSP, statusline, 권한 설정 |
| AWS/Kube 설정 | 1Password Document에서 최초 1회 다운로드 |
| 1Password 시크릿 | Docker Hub, AWS credentials, Kubeconfig |
| BetterTouchTool | 라이선스 자동 설치 |

### 디렉토리 구조

```
~/
├── Projects/
│   ├── work/      # 회사 프로젝트 (회사 이메일 자동 적용)
│   └── me/        # 개인 프로젝트
├── Commands/
│   ├── command.sh # 커스텀 함수
│   └── alias      # alias 정의
├── .kube/config   # Kubernetes 설정 (최초 1회 다운로드, 이후 로컬 관리)
├── .aws/credentials # AWS 자격증명 (최초 1회 다운로드, 이후 로컬 관리)
└── .secrets.zsh   # 시크릿 (1Password에서 자동 로드)
```

## 시크릿 설정 (1Password)

chezmoi가 1Password에서 시크릿을 자동으로 가져옵니다.

### 최초 설정

1. 1Password "Secrets" vault에 아이템 생성:
   - **Login 아이템**: Docker Hub, GitHub Token
   - **Document**: Kubeconfig, AWS Credentials, BetterTouchTool License
2. 1Password CLI 인증:
   ```bash
   eval $(op signin)
   ```
3. `chezmoi apply` 실행 (1Password에서 자동 다운로드)

### 자격증명 갱신

**1Password → 로컬 다운로드** (새 머신 설정, 1Password 내용 변경 시):
```bash
op document get "Kubeconfig" --vault "Secrets" > ~/.kube/config
op document get "AWS Credentials" --vault "Secrets" > ~/.aws/credentials
```

**로컬 → 1Password 업로드** (로컬에서 수정 후 다른 머신에 반영 시):
```bash
# 최초 업로드
op document create ~/.kube/config --vault "Secrets" --title "Kubeconfig"
op document create ~/.aws/credentials --vault "Secrets" --title "AWS Credentials"

# 기존 문서 업데이트
op document edit "Kubeconfig" ~/.kube/config --vault "Secrets"
op document edit "AWS Credentials" ~/.aws/credentials --vault "Secrets"
```

### 관리되는 시크릿

| 타입 | 아이템 | 용도 |
|------|--------|------|
| Login | Docker Hub | Docker 이미지 푸시 |
| Document | Kubeconfig | Kubernetes 클러스터 설정 |
| Document | AWS Credentials | AWS 프로필 (meshdev, meshlabs 등) |
| Document | BetterTouchTool License | BTT 라이선스 자동 설치 |

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
```
