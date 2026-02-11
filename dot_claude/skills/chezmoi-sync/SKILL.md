---
name: chezmoi-sync
description: chezmoi로 관리하는 dotfiles 변경사항을 소스에 반영하고 커밋/푸시하는 워크플로우. /chezmoi-sync 슬래시 커맨드로 호출. 사용자가 chezmoi 관리 파일을 수정한 후 'chezmoi 반영', 'dotfiles 싱크', 'chezmoi 커밋' 등을 요청할 때 사용.
---

# chezmoi-sync

chezmoi 관리 파일의 변경사항을 소스 리포에 반영, 커밋, 푸시하는 워크플로우.

## 환경

- chezmoi 소스: `~/.local/share/chezmoi`
- 원격 리포: `origin/main`
- 커밋 메시지: 한글, `<type>: <subject>` 형식 (feat, fix, refactor, docs, chore)

## 워크플로우

### 1. 변경 감지

```bash
chezmoi diff
```

변경이 없으면 "변경사항 없음"을 알리고 종료.

### 2. 소스 반영

변경된 모든 파일을 한번에 반영:

```bash
chezmoi re-add
```

반영 후 diff가 비어있는지 확인:

```bash
chezmoi diff
```

### 3. 커밋

chezmoi 소스 리포에서 git 작업 수행. 모든 git 명령에 `-C ~/.local/share/chezmoi` 사용.

```bash
git -C ~/.local/share/chezmoi status
git -C ~/.local/share/chezmoi diff --staged
git -C ~/.local/share/chezmoi diff
```

변경 내용을 분석하여 커밋 메시지를 자동 생성. 기존 커밋 로그 스타일을 참고:

```bash
git -C ~/.local/share/chezmoi log --oneline -5
```

변경 파일을 스테이징하고 커밋:

```bash
git -C ~/.local/share/chezmoi add <changed-files>
git -C ~/.local/share/chezmoi commit -m "<type>: <subject>"
```

### 4. 푸시

```bash
git -C ~/.local/share/chezmoi push
```

### 5. 완료 보고

변경된 파일 목록과 커밋 메시지를 요약하여 보고.
