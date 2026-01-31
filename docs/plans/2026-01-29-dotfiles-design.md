# Dotfiles 설계 문서

## 개요

chezmoi를 사용하여 macOS 개발 환경을 자동화하는 dotfiles 프로젝트.

## 요구사항

- [x] chezmoi로 dotfiles 관리
- [x] Homebrew 패키지 자동 설치 (Brewfile)
- [x] ~/Command 디렉토리 자동 설치
- [x] 시크릿은 .secrets.zsh로 분리 (dotfiles에 포함 안 함)
- [x] oh-my-zsh + powerlevel10k 설정
- [x] ~/Project/work, ~/Project/me 디렉토리 구조
- [x] work.inc로 회사용 git 설정 관리
- [x] BetterTouchTool 설정 및 preset 포함
- [x] Naver Whale, 1Password 설치

## 디렉토리 구조

```
~/.local/share/chezmoi/              # chezmoi 소스 디렉토리
├── .chezmoi.toml.tmpl               # chezmoi 설정
├── .chezmoiignore                   # 무시할 파일 패턴
│
├── run_once_before_00-create-directories.sh.tmpl
├── run_once_before_01-install-homebrew.sh.tmpl
├── run_once_before_02-install-oh-my-zsh.sh.tmpl
├── run_onchange_after_brew-bundle.sh.tmpl
│
├── dot_zshrc.tmpl                   # .zshrc
├── dot_p10k.zsh                     # powerlevel10k 설정
├── dot_gitconfig.tmpl               # .gitconfig
├── dot_secrets.zsh.tmpl             # .secrets.zsh 템플릿 (가이드만)
├── dot_Brewfile                     # Homebrew 패키지 목록
│
├── Command/
│   ├── commands.sh
│   └── alias
│
├── Project/
│   └── work/
│       └── work.inc
│
└── private_Library/
    └── private_Application Support/
        └── private_BetterTouchTool/
            ├── btt_data_backup.json
            └── Presets/
                └── *.bttpreset
```

## 설치 스크립트

### 1. run_once_before_00-create-directories.sh.tmpl

```bash
#!/bin/bash
mkdir -p ~/Project/work
mkdir -p ~/Project/me
mkdir -p ~/Command
```

### 2. run_once_before_01-install-homebrew.sh.tmpl

```bash
#!/bin/bash
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
```

### 3. run_once_before_02-install-oh-my-zsh.sh.tmpl

```bash
#!/bin/bash
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
```

### 4. run_onchange_after_brew-bundle.sh.tmpl

```bash
#!/bin/bash
# Brewfile 해시: {{ include "dot_Brewfile" | sha256sum }}
brew bundle --file="{{ .chezmoi.homeDir }}/.Brewfile" --no-lock
```

## 설정 파일

### .zshrc (dot_zshrc.tmpl)

현재 .zshrc 기반 + 시크릿 로드 추가:

```bash
# 시크릿 로드 (파일이 있을 때만)
[[ -f ~/.secrets.zsh ]] && source ~/.secrets.zsh
```

### .gitconfig (dot_gitconfig.tmpl)

```gitconfig
[user]
    name = 조민준
    email = alswns9288@gmail.com

[includeIf "gitdir:~/Project/work/"]
    path = ~/Project/work/work.inc
```

### work.inc

```gitconfig
[user]
    name = 조민준
    email = minjun.jo@vroong.com
```

### .secrets.zsh (dot_secrets.zsh.tmpl)

템플릿만 포함 (실제 값 없음):

```bash
# 이 파일은 dotfiles에 포함되지 않습니다.
# 새 머신에서 아래 변수들을 직접 설정하세요:
#
# export AWS_ACCESS_KEY_ID=""
# export AWS_SECRET_ACCESS_KEY=""
# export DOCKER_PASSWORD=""
```

### .chezmoiignore

```
.secrets.zsh
Library/Application Support/BetterTouchTool/Purchased.plist
Library/Application Support/BetterTouchTool/*.license
```

## Brewfile

현재 설치된 79개 formula + 13개 cask + 추가 앱:

```ruby
# Casks
cask "bettertouchtool"
cask "naver-whale"
cask "1password"
# ... 기존 설치된 패키지들
```

## BetterTouchTool

### 포함 파일

- `~/Library/Application Support/BetterTouchTool/btt_data_backup.json`
- `~/Library/Application Support/BetterTouchTool/Presets/*.bttpreset`

### 제외 파일

- `Purchased.plist` (라이센스)
- `*.license`

## 새 머신 설치 과정

### 1. 원라이너 설치

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <github-username>
```

### 2. 자동 실행 순서

1. `run_once_before_00-create-directories.sh` → 디렉토리 생성
2. `run_once_before_01-install-homebrew.sh` → Homebrew 설치
3. `run_once_before_02-install-oh-my-zsh.sh` → oh-my-zsh 설치
4. dotfiles 복사 → .zshrc, .gitconfig, Command/, etc.
5. `run_onchange_after_brew-bundle.sh` → brew bundle 실행

### 3. 수동 설정

```bash
# 시크릿 설정
vi ~/.secrets.zsh

# BetterTouchTool 라이센스 입력 (앱에서)
```

## 일상적인 사용

```bash
chezmoi edit ~/.zshrc     # 설정 수정
chezmoi diff              # 변경사항 미리보기
chezmoi apply             # 변경사항 적용
chezmoi cd                # chezmoi 소스 디렉토리로 이동
chezmoi git add .         # git 커밋
chezmoi git commit -m "Update zshrc"
chezmoi git push
```

## 구현 태스크

1. [ ] chezmoi 초기화 및 기본 설정
2. [ ] 설치 스크립트 작성 (run_once_before_*)
3. [ ] 현재 Brewfile 생성 (brew bundle dump)
4. [ ] .zshrc 템플릿 작성
5. [ ] .gitconfig 템플릿 작성
6. [ ] Command 폴더 추가
7. [ ] work.inc 추가
8. [ ] .secrets.zsh 템플릿 작성
9. [ ] BetterTouchTool 설정 추가
10. [ ] .chezmoiignore 작성
11. [ ] 테스트 및 검증
12. [ ] GitHub 저장소 생성 및 push
