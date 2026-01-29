# Dotfiles

chezmoi로 관리하는 macOS 개발 환경 설정

## 새 머신에서 설치

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jo-minjun
```

이 명령어 하나로:
1. chezmoi 설치
2. 이름/이메일 입력 프롬프트
3. Homebrew, oh-my-zsh 자동 설치
4. 모든 dotfiles 적용
5. brew bundle로 패키지 설치

## 포함된 설정

| 항목 | 설명 |
|------|------|
| Brewfile | Homebrew 패키지 (bettertouchtool, naver-whale, 1password 등) |
| .zshrc | oh-my-zsh + powerlevel10k |
| .gitconfig | Git 설정 + 회사/개인 이메일 분리 |
| Commands/ | 커스텀 쉘 함수 및 alias |
| BetterTouchTool | 제스처/단축키 설정 |

## 일상적인 사용

```bash
# 설정 수정
chezmoi edit ~/.zshrc

# 변경사항 미리보기
chezmoi diff

# 적용
chezmoi apply

# 소스 디렉토리로 이동
chezmoi cd

# 변경사항 커밋 및 푸시
cd ~/.local/share/chezmoi
git add . && git commit -m "Update dotfiles" && git push
```

## 수동 설정 (새 머신)

### 1. 시크릿 설정

```bash
vi ~/.secrets.zsh
```

```bash
export DOCKER_HUB_PASSWORD="your-password"
export GITHUB_TOKEN="your-token"
```

### 2. BetterTouchTool

- 앱 실행 후 라이센스 입력

## 디렉토리 구조

```
~
├── .zshrc                 # zsh 설정
├── .p10k.zsh              # powerlevel10k 테마
├── .gitconfig             # git 설정
├── .Brewfile              # Homebrew 패키지
├── .secrets.zsh           # 시크릿 (git 미추적)
├── Commands/
│   ├── command.sh         # 커스텀 쉘 함수
│   └── alias              # alias 정의
└── Projects/
    ├── work/
    │   └── work.inc       # 회사용 git 설정
    └── me/                # 개인 프로젝트
```

## Git 이메일 자동 전환

- `~/Projects/work/` 하위: 회사 이메일 자동 적용
- 그 외: 개인 이메일 사용

```bash
# 확인
cd ~/Projects/work/some-repo && git config user.email  # 회사 이메일
cd ~/Projects/me/some-repo && git config user.email    # 개인 이메일
```
