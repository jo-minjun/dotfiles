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

### 1. BTT 프리셋 내보내기

BTT 설정은 앱 내부 DB에 저장되고 `.bttpreset` 파일은 내보내야만 갱신되므로, 변경 감지 전에 현재 설정으로 다시 내보낸다:

```bash
bash ~/.claude/skills/chezmoi-sync/scripts/export-btt-presets.sh
```

### 2. 변경 감지

```bash
chezmoi diff
```

변경이 없으면 "변경사항 없음"을 알리고 종료.

### 3. JSON 정규화

`chezmoi re-add` 전에 JSON 파일의 키를 정렬하여 불필요한 키 순서 diff를 방지:

```bash
bash ~/.claude/skills/chezmoi-sync/scripts/normalize-json.sh
```

### 4. 소스 반영

`chezmoi diff`에 나온 파일 중 이번에 반영할 파일만 지정해 반영한다. 소스는 여러 기기가 공유하므로, 다른 기기 경로(`/Users/<다른 사용자>`)나 이번 작업과 무관한 변경이 섞여 있으면 반영 범위를 사용자에게 확인한다.

```bash
chezmoi re-add <target>...
```

반영 후 대상 파일의 diff가 비어있는지 확인:

```bash
chezmoi diff <target>...
```

### 5. 커밋

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

### 6. 푸시

```bash
git -C ~/.local/share/chezmoi push
```

### 7. 완료 보고

변경된 파일 목록과 커밋 메시지를 요약하여 보고.
