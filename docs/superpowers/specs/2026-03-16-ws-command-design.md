# ws() — tmux 워크스페이스 명령어 설계

## 개요

tmux를 이용해 개발 워크스페이스를 한 번에 구성하는 셸 함수.

## 사용법

```bash
ws [세션이름]
```

- 세션 이름 생략 시 현재 디렉토리명 사용
- 동명 세션이 이미 존재하면 attach (tmux 밖) 또는 switch (tmux 안)
- 모든 pane은 현재 디렉토리에서 시작

## 레이아웃

```
┌──────────────────────┬───────────────┐
│                      │               │
│                      │    yazi       │
│    clauded           │  (상 60%)     │
│   (좌 60%)           ├───────────────┤
│                      │               │
│                      │  terminal     │
│                      │  (하 40%)     │
└──────────────────────┴───────────────┘
       좌 60%               우 40%
```

- 좌측 60%: Claude Code (`clauded`)
- 우측 상단 60% (우측 영역 내): yazi 파일 탐색기
- 우측 하단 40% (우측 영역 내): 일반 터미널

## 동작 흐름

1. 세션 이름 결정: 첫 번째 인자 또는 `$(basename "$PWD")`
   - 세션 이름에서 알파벳, 숫자, `-`, `_` 외의 문자를 `-`로 치환
   - 치환 결과가 비어 있거나 `-`만 남으면 `workspace`를 기본값으로 사용
2. `tmux has-session -t "=$session_name"`으로 동명 세션 존재 확인
   - 존재 + tmux 안(`$TMUX` 설정됨): `tmux switch-client -t $session_name`
   - 존재 + tmux 밖: `tmux attach-session -t $session_name`
   - 존재하지 않으면 다음 단계로
3. `tmux new-session -d -s $session_name -c "$PWD"`로 detached 세션 생성
   - 생성된 pane: `$session_name:1.1` (좌측, 1-based 넘버링)
4. `tmux split-window -h -p 40 -t $session_name:1.1 -c "$PWD"`로 우측 pane 생성
   - 포커스가 우측 pane(`$session_name:1.2`)으로 이동
5. `tmux split-window -v -p 40 -t $session_name:1.2 -c "$PWD"`로 우측 하단 pane 생성
   - 포커스가 우측 하단 pane(`$session_name:1.3`)으로 이동
6. `tmux send-keys -t $session_name:1.2 'yazi' C-m` (우측 상단에 yazi 실행)
7. `tmux send-keys -t $session_name:1.1 'clauded' C-m` (좌측에 clauded 실행)
8. `tmux select-pane -t $session_name:1.1` (좌측 pane에 포커스)
9. attach 또는 switch (step 2와 동일한 분기)

## 구현 위치

`Shell/private_executable_commands.sh.tmpl`에 `ws()` 함수 추가.

## 의존성

- tmux (Brewfile에 이미 포함)
- clauded alias (Shell/aliases.sh에 이미 정의)
- yazi (Brewfile에 이미 포함)
