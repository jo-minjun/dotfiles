# Dotfiles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** chezmoi를 사용하여 macOS 개발 환경을 자동화하는 dotfiles 구축

**Architecture:** chezmoi로 dotfiles 관리. run_once_before 스크립트로 Homebrew/oh-my-zsh 설치, run_onchange_after로 brew bundle 실행. 시크릿은 .secrets.zsh로 분리하여 dotfiles에 포함하지 않음.

**Tech Stack:** chezmoi, Homebrew, oh-my-zsh, powerlevel10k, mise, BetterTouchTool

---

### Task 1: chezmoi 설치 및 초기화

**Files:**
- Create: `~/.local/share/chezmoi/` (chezmoi가 자동 생성)

**Step 1: chezmoi 설치**

Run:
```bash
brew install chezmoi
```

Expected: chezmoi가 설치됨

**Step 2: chezmoi 초기화**

Run:
```bash
chezmoi init
```

Expected: `~/.local/share/chezmoi/` 디렉토리 생성

**Step 3: 확인**

Run:
```bash
chezmoi cd && pwd
```

Expected: `/Users/minjun.jo/.local/share/chezmoi`

---

### Task 2: .chezmoiignore 작성

**Files:**
- Create: `~/.local/share/chezmoi/.chezmoiignore`

**Step 1: .chezmoiignore 파일 생성**

```bash
chezmoi cd
```

파일 내용:
```
# 시크릿 파일 (기존 파일 덮어쓰지 않음)
.secrets.zsh

# BetterTouchTool 라이센스
Library/Application Support/BetterTouchTool/*.bttlicense
Library/Application Support/BetterTouchTool/*-shm
Library/Application Support/BetterTouchTool/*-wal

# macOS 시스템 파일
.DS_Store
**/.DS_Store
```

**Step 2: 확인**

Run:
```bash
cat ~/.local/share/chezmoi/.chezmoiignore
```

Expected: 위 내용이 출력됨

**Step 3: Commit**

```bash
cd ~/.local/share/chezmoi && git add .chezmoiignore && git commit -m "chore: add .chezmoiignore"
```

---

### Task 3: 디렉토리 생성 스크립트 작성

**Files:**
- Create: `~/.local/share/chezmoi/run_once_before_00-create-directories.sh.tmpl`

**Step 1: 스크립트 파일 생성**

파일 내용:
```bash
#!/bin/bash
set -e

echo "Creating directories..."

mkdir -p ~/Project/work
mkdir -p ~/Project/me
mkdir -p ~/Command

echo "Directories created successfully"
```

**Step 2: 실행 권한 확인**

Run:
```bash
ls -la ~/.local/share/chezmoi/run_once_before_00-create-directories.sh.tmpl
```

Expected: 파일이 존재함 (chezmoi가 자동으로 실행 권한 처리)

**Step 3: Commit**

```bash
cd ~/.local/share/chezmoi && git add run_once_before_00-create-directories.sh.tmpl && git commit -m "feat: add directory creation script"
```

---

### Task 4: Homebrew 설치 스크립트 작성

**Files:**
- Create: `~/.local/share/chezmoi/run_once_before_01-install-homebrew.sh.tmpl`

**Step 1: 스크립트 파일 생성**

파일 내용:
```bash
#!/bin/bash
set -e

if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon Mac
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    echo "Homebrew installed successfully"
else
    echo "Homebrew already installed"
fi
```

**Step 2: Commit**

```bash
cd ~/.local/share/chezmoi && git add run_once_before_01-install-homebrew.sh.tmpl && git commit -m "feat: add Homebrew installation script"
```

---

### Task 5: oh-my-zsh 설치 스크립트 작성

**Files:**
- Create: `~/.local/share/chezmoi/run_once_before_02-install-oh-my-zsh.sh.tmpl`

**Step 1: 스크립트 파일 생성**

파일 내용:
```bash
#!/bin/bash
set -e

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "oh-my-zsh installed successfully"
else
    echo "oh-my-zsh already installed"
fi
```

**Step 2: Commit**

```bash
cd ~/.local/share/chezmoi && git add run_once_before_02-install-oh-my-zsh.sh.tmpl && git commit -m "feat: add oh-my-zsh installation script"
```

---

### Task 6: Brewfile 생성

**Files:**
- Create: `~/.local/share/chezmoi/dot_Brewfile`

**Step 1: 현재 설치된 패키지로 Brewfile 생성**

Run:
```bash
brew bundle dump --file=~/.local/share/chezmoi/dot_Brewfile --force
```

**Step 2: Brewfile에 추가 패키지 추가**

파일 끝에 추가:
```ruby
# 추가 앱
cask "bettertouchtool"
cask "naver-whale"
```

Note: 1password는 이미 설치되어 있음

**Step 3: vscode 확장 제거 (선택)**

Brewfile에서 `vscode "..."` 라인들은 제거하거나 유지 (선호에 따라)

**Step 4: Commit**

```bash
cd ~/.local/share/chezmoi && git add dot_Brewfile && git commit -m "feat: add Brewfile with current packages"
```

---

### Task 7: brew bundle 실행 스크립트 작성

**Files:**
- Create: `~/.local/share/chezmoi/run_onchange_after_brew-bundle.sh.tmpl`

**Step 1: 스크립트 파일 생성**

파일 내용:
```bash
#!/bin/bash
set -e

# Brewfile hash: {{ include "dot_Brewfile" | sha256sum }}
# 위 해시가 변경되면 이 스크립트가 재실행됨

echo "Running brew bundle..."
brew bundle --file="{{ .chezmoi.homeDir }}/.Brewfile" --no-lock

echo "Brew bundle completed"
```

**Step 2: Commit**

```bash
cd ~/.local/share/chezmoi && git add run_onchange_after_brew-bundle.sh.tmpl && git commit -m "feat: add brew bundle script"
```

---

### Task 8: .zshrc 템플릿 작성

**Files:**
- Create: `~/.local/share/chezmoi/dot_zshrc.tmpl`

**Step 1: 현재 .zshrc를 chezmoi에 추가**

Run:
```bash
chezmoi add ~/.zshrc --template
```

**Step 2: 시크릿 로드 코드 추가**

`dot_zshrc.tmpl` 파일에서 `source ~/Command/command.sh` 다음에 추가:

```bash
# 시크릿 로드 (파일이 있을 때만)
[[ -f ~/.secrets.zsh ]] && source ~/.secrets.zsh
```

**Step 3: 확인**

Run:
```bash
grep -A2 "source ~/Command/command.sh" ~/.local/share/chezmoi/dot_zshrc.tmpl
```

Expected: 시크릿 로드 코드가 보임

**Step 4: Commit**

```bash
cd ~/.local/share/chezmoi && git add dot_zshrc.tmpl && git commit -m "feat: add .zshrc template with secrets loading"
```

---

### Task 9: .p10k.zsh 추가

**Files:**
- Create: `~/.local/share/chezmoi/dot_p10k.zsh`

**Step 1: 현재 .p10k.zsh를 chezmoi에 추가**

Run:
```bash
chezmoi add ~/.p10k.zsh
```

**Step 2: Commit**

```bash
cd ~/.local/share/chezmoi && git add dot_p10k.zsh && git commit -m "feat: add powerlevel10k config"
```

---

### Task 10: .gitconfig 템플릿 작성

**Files:**
- Create: `~/.local/share/chezmoi/dot_gitconfig.tmpl`

**Step 1: 현재 .gitconfig를 chezmoi에 추가**

Run:
```bash
chezmoi add ~/.gitconfig --template
```

**Step 2: includeIf 경로를 work.inc로 변경**

`dot_gitconfig.tmpl` 파일 수정:

```gitconfig
[user]
	name = 조민준
	email = alswns9288@gmail.com

[includeIf "gitdir:~/Project/work/"]
	path = ~/Project/work/work.inc
```

**Step 3: Commit**

```bash
cd ~/.local/share/chezmoi && git add dot_gitconfig.tmpl && git commit -m "feat: add .gitconfig template"
```

---

### Task 11: Command 폴더 추가

**Files:**
- Create: `~/.local/share/chezmoi/Command/command.sh`
- Create: `~/.local/share/chezmoi/Command/alias`

**Step 1: Command 폴더를 chezmoi에 추가**

Run:
```bash
chezmoi add ~/Command
```

**Step 2: command.sh에서 하드코딩된 시크릿 제거**

`~/.local/share/chezmoi/Command/command.sh` 파일에서 민감한 정보를 환경변수로 교체:

- 52행: `Iliu@ods07132` → `$DOCKER_HUB_PASSWORD`
- 90행: AWS profile은 그대로 유지 (이미 --profile 사용 중)

**Step 3: Commit**

```bash
cd ~/.local/share/chezmoi && git add Command && git commit -m "feat: add Command folder with shell functions"
```

---

### Task 12: work.inc 추가

**Files:**
- Create: `~/.local/share/chezmoi/Project/work/work.inc`

**Step 1: 디렉토리 생성 및 파일 작성**

```bash
mkdir -p ~/.local/share/chezmoi/Project/work
```

파일 내용 (`Project/work/work.inc`):
```gitconfig
[user]
	name = 조민준
	email = minjun.jo@vroong.com
```

**Step 2: Commit**

```bash
cd ~/.local/share/chezmoi && git add Project && git commit -m "feat: add work.inc for work git config"
```

---

### Task 13: .secrets.zsh 템플릿 작성

**Files:**
- Create: `~/.local/share/chezmoi/dot_secrets.zsh.tmpl`

**Step 1: 템플릿 파일 생성**

파일 내용:
```bash
# ===========================================
# 시크릿 환경변수 설정
# ===========================================
# 이 파일은 dotfiles 저장소에 포함되지 않습니다.
# 새 머신에서 아래 변수들을 직접 설정하세요.
#
# 사용 방법:
# 1. 이 파일을 ~/.secrets.zsh로 복사
# 2. 아래 변수들의 값을 채워넣기
# 3. source ~/.zshrc 또는 터미널 재시작
# ===========================================

# Docker Hub
# export DOCKER_HUB_PASSWORD=""

# AWS (선택 - ~/.aws/credentials 사용 권장)
# export AWS_ACCESS_KEY_ID=""
# export AWS_SECRET_ACCESS_KEY=""

# 기타 API 키
# export GITHUB_TOKEN=""
```

**Step 2: 실제 .secrets.zsh 파일 생성 (로컬용, chezmoi에 포함 안 됨)**

```bash
cp ~/.local/share/chezmoi/dot_secrets.zsh.tmpl ~/.secrets.zsh
# 그 후 ~/.secrets.zsh에 실제 값 입력
```

**Step 3: Commit**

```bash
cd ~/.local/share/chezmoi && git add dot_secrets.zsh.tmpl && git commit -m "feat: add secrets template"
```

---

### Task 14: BetterTouchTool 설정 추가

**Files:**
- Create: `~/.local/share/chezmoi/private_Library/private_Application Support/private_BetterTouchTool/` 하위 파일들

**Step 1: BTT 앱 종료 확인**

Run:
```bash
pgrep -x "BetterTouchTool" && echo "BTT is running - please quit first" || echo "BTT is not running"
```

Expected: "BTT is not running" (실행 중이면 종료 필요)

**Step 2: BTT 설정 폴더를 chezmoi에 추가**

Run:
```bash
chezmoi add ~/Library/Application\ Support/BetterTouchTool/btt_data_store.version_6_011_build_2026010801
chezmoi add ~/Library/Application\ Support/BetterTouchTool/PresetBundles
```

Note: 최신 버전의 data store 파일만 추가. -shm, -wal 파일은 런타임 파일이므로 제외.

**Step 3: 확인**

Run:
```bash
ls -la ~/.local/share/chezmoi/private_Library/private_Application\ Support/private_BetterTouchTool/
```

Expected: btt_data_store 파일과 PresetBundles 폴더가 보임

**Step 4: Commit**

```bash
cd ~/.local/share/chezmoi && git add private_Library && git commit -m "feat: add BetterTouchTool config and presets"
```

---

### Task 15: chezmoi apply 테스트

**Step 1: 변경사항 미리보기**

Run:
```bash
chezmoi diff
```

Expected: 변경될 파일들의 diff가 표시됨

**Step 2: 적용 (dry-run)**

Run:
```bash
chezmoi apply --dry-run --verbose
```

Expected: 실제 변경 없이 어떤 작업이 수행될지 표시됨

**Step 3: 적용**

Run:
```bash
chezmoi apply
```

Expected: 모든 파일이 올바른 위치에 복사됨

---

### Task 16: GitHub 저장소 생성 및 push

**Step 1: GitHub 저장소 생성**

Run:
```bash
gh repo create dotfiles --private --source=~/.local/share/chezmoi --remote=origin --push
```

또는 public으로:
```bash
gh repo create dotfiles --public --source=~/.local/share/chezmoi --remote=origin --push
```

**Step 2: 확인**

Run:
```bash
cd ~/.local/share/chezmoi && git remote -v
```

Expected: origin이 GitHub 저장소를 가리킴

**Step 3: push**

Run:
```bash
cd ~/.local/share/chezmoi && git push -u origin main
```

Expected: 모든 커밋이 GitHub에 push됨

---

### Task 17: ~/Project/me/dotfiles와 연결 (선택)

현재 `~/Project/me/dotfiles`에 설계 문서가 있습니다. 두 가지 옵션:

**Option A: chezmoi 소스를 ~/Project/me/dotfiles로 이동**

```bash
# 기존 chezmoi 소스 이동
mv ~/.local/share/chezmoi/* ~/Project/me/dotfiles/
mv ~/.local/share/chezmoi/.* ~/Project/me/dotfiles/ 2>/dev/null || true

# chezmoi가 새 위치를 사용하도록 설정
chezmoi init --source=~/Project/me/dotfiles
```

**Option B: 설계 문서를 chezmoi 소스로 이동**

```bash
# 설계 문서를 chezmoi 소스로 이동
mv ~/Project/me/dotfiles/docs ~/.local/share/chezmoi/
cd ~/.local/share/chezmoi && git add docs && git commit -m "docs: add design documents"
```

사용자 선택에 따라 진행.

---

## 검증 체크리스트

- [ ] `chezmoi doctor` 실행 - 문제 없음
- [ ] `chezmoi diff` 실행 - 예상치 못한 변경 없음
- [ ] 새 터미널 열기 - oh-my-zsh, powerlevel10k 정상 작동
- [ ] `source ~/.secrets.zsh` 후 환경변수 확인
- [ ] `git config user.email` - 개인 이메일
- [ ] `cd ~/Project/work && git config user.email` - 회사 이메일
- [ ] BetterTouchTool 실행 - 설정 복원됨
- [ ] `brew bundle check --file=~/.Brewfile` - 모든 패키지 설치됨
