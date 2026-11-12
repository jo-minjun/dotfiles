#!/bin/bash
# SessionStart(startup) 훅: 새 세션이 시작될 때 git 작업 위치를 origin 최신으로 fast-forward 한다.
#   - 메인 checkout: 브랜치가 main·master 일 때만 origin 의 같은 브랜치로 맞춘다.
#   - <repo>/.claude/worktrees/ 아래 워크트리: origin 기본 브랜치로 맞춘다.
#     Code 탭은 워크트리 기준 브랜치 설정(worktree.baseRef)을 쓰지 않아서 시작 직후에 맞춘다.
# 커밋하지 않은 변경이 있거나 fast-forward 가 안 되면 건드리지 않는다. git 이 없거나 저장소가 아니면 아무것도 하지 않는다.
# stdout 은 세션 맥락에 들어가므로 알릴 일이 있을 때만 한 줄 쓴다. 세션 시작을 막지 않도록 항상 0 으로 끝낸다.

input=$(cat 2>/dev/null)
command -v git >/dev/null 2>&1 || exit 0

dir=""
if command -v jq >/dev/null 2>&1; then
  dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -n "$dir" ] && [ -d "$dir" ] || dir=$PWD

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
g() { git -C "$top" "$@"; }

# 자격 증명 입력을 기다리며 세션 시작이 멈추지 않게 한다.
export GIT_TERMINAL_PROMPT=0

g remote get-url origin >/dev/null 2>&1 || exit 0
branch=$(g symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0

git_dir=$(g rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
common_dir=$(g rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0

if [ "$git_dir" = "$common_dir" ]; then
  case "$branch" in
    main | master) target=$branch ;;
    *) exit 0 ;;
  esac
  place="메인 checkout"
else
  case "$top" in
    */.claude/worktrees/*) ;;
    *) exit 0 ;;
  esac
  target=$(g symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  target=${target#origin/}
  if [ -z "$target" ]; then
    for candidate in main master; do
      if g show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
        target=$candidate
        break
      fi
    done
  fi
  [ -n "$target" ] || exit 0
  place="워크트리"
fi

subject="${place}의 $branch 브랜치"

if [ -n "$(g status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  echo "[git 갱신 건너뜀] ${subject}에 커밋하지 않은 변경이 있다. origin/$target 기준으로 맞추지 않았다."
  exit 0
fi

# 저장소의 fetch refspec 이 좁아도 origin/<target> 이 갱신되도록 refspec 을 명시한다.
if ! g fetch --quiet --no-tags origin "+refs/heads/$target:refs/remotes/origin/$target" 2>/dev/null; then
  echo "[git 갱신 실패] origin/$target fetch 가 실패했다. ${subject}를 갱신하지 않았다."
  exit 0
fi

g merge-base --is-ancestor "origin/$target" HEAD 2>/dev/null && exit 0

if ! g merge-base --is-ancestor HEAD "origin/$target" 2>/dev/null; then
  echo "[git 갱신 건너뜀] ${subject}에 origin/${target}에 없는 커밋이 있다. fast-forward 하지 않았다."
  exit 0
fi

before=$(g rev-parse --short HEAD)
if ! g merge --ff-only --quiet "origin/$target" >/dev/null 2>&1; then
  echo "[git 갱신 실패] ${subject}를 origin/$target 기준으로 fast-forward 하지 못했다."
  exit 0
fi
after=$(g rev-parse --short HEAD)
echo "[git 갱신] ${subject}를 origin/$target 기준으로 fast-forward 했다 ($before → $after)."
exit 0
