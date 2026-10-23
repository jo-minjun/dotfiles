# SHELL

## 파일 구성
- 셸 설정은 chezmoi로 관리한다. 소스는 `~/.local/share/chezmoi`다

| 대상 | 소스 | 용도 |
|---|---|---|
| `~/.zshrc` | `dot_zshrc.tmpl` | 프레임워크·플러그인 로딩, hook |
| `~/Shell/commands.sh` | `Shell/private_executable_commands.sh.tmpl` | 함수 |
| `~/Shell/aliases.sh` | `Shell/aliases.sh` | alias |
| `~/Shell/exports.sh` | `Shell/exports.sh` | PATH, 환경변수 |
| `~/Shell/local.sh` | `Shell/create_local.sh` | 기기 전용 설정 |
| `~/.secrets.zsh` | `dot_secrets.zsh.tmpl` | 비밀값 |

## alias·함수 추가
- 위 표의 용도에 맞는 파일에 추가하라. 특정 기기에서만 쓰는 설정은 `local.sh`에 두어라
- 토큰, 비밀번호 같은 비밀값은 `~/.secrets.zsh`에만 두고 다른 파일에 하드코딩하지 마라
- 추가하기 전에 `ls_shell`과 `type <name>`으로 이름이 겹치는지 확인하라. OMZ 플러그인(git, docker, kubectl 등)이 정의한 alias와도 겹치면 안 된다
- `ls_shell`은 grep으로 목록을 뽑는다. 함수는 줄 맨 앞에 `name() {` 형식으로, alias는 줄 맨 앞에 `alias name=` 형식으로 정의하고, 이름에는 소문자와 `_`만 써라
- 인자가 필요한 함수는 인자 없이 호출됐을 때 제목, `Usage`, 예시를 출력하고 `return 0` 하라
- 출력에는 `print_bold`, `print_green`, `print_yellow`, `print_red` 헬퍼를 쓰고, 메시지는 한글로 써라
- 함수 안의 변수는 `local`로 선언하라
- 삭제, reset, force push처럼 되돌릴 수 없는 작업은 실행 전에 `[y/N]` 확인을 받아라
- `commands.sh`는 템플릿이다. 함수 본문에 `{{`가 있으면 `{{ "{{...}}" }}` 형태로 이스케이프하라

## chezmoi 반영
- 대상 파일이 아니라 소스 파일을 수정하라. 템플릿(`.tmpl`) 파일은 `chezmoi re-add`가 소스를 갱신하지 않는다
- 수정하기 전에 `chezmoi diff <대상>`으로 대상 쪽에 반영되지 않은 변경이 있는지 확인하라. 있으면 apply 시 덮어써지므로 사용자에게 먼저 알려라
- 소스를 수정한 뒤 다음 순서로 적용하라
  1. `chezmoi diff <대상>`으로 바뀌는 내용 확인
  2. `chezmoi apply <대상>`
  3. `zsh -n <대상>`으로 문법 검사
  4. `zsh -ic 'type <name>'`으로 로드되는지 확인
- `local.sh`는 `create_` 파일이라 처음 한 번만 만들어진다. 기기 전용 설정은 대상 파일 `~/Shell/local.sh`를 직접 수정하고, 소스 `create_local.sh`는 새 기기의 기본값을 바꿀 때만 수정하라
- 커밋·푸시는 사용자가 요청할 때 `/chezmoi-sync` 스킬 절차로 진행하라. 셸 함수 `chezmoi_sync`는 커밋 메시지를 대화형으로 입력받으므로 에이전트는 쓰지 마라
