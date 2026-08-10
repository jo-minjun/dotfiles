---
name: vr-deploy
description: "태그 푸시로 Jenkins 빌드를 트리거하고 ArgoCD로 지정 환경에 배포할 때 사용하는 스킬. 사용자가 '배포해줘', '태그 배포', 'dev1에 배포', 'Jenkins + ArgoCD 배포', 'SNAPSHOT 배포' 등을 요청하거나, 병합된 커밋을 특정 환경으로 배포해야 할 때 트리거한다."
---

# 태그 푸시 → Jenkins 빌드 → ArgoCD 환경 배포

Jenkins MultiBranch Pipeline과 ArgoCD가 연동된 fintech 팀 서비스를 배포한다. 전형적인 흐름은 다음과 같다.

```
git tag → git push origin <tag>
  → Jenkins tag job 자동 트리거
    → 어느 스테이지에서 "배포 환경 선택" input 일시정지
      → 환경 선택 제출
        → 이미지 빌드/푸시 (ECR)
          → helm values repo의 image tag 갱신
            → ArgoCD sync (Manual policy인 경우 수동)
              → 배포 완료
```

이 스킬은 태그 존재 ~ 환경 Healthy까지의 전 과정을 자동화한다.

**파이프라인 세부 사항은 리포지토리마다 다를 수 있다.** 공유 라이브러리(`dockerFilePipeline` 등) 선택, 스테이지 이름, input 파라미터 타입(checkbox/choice/string) 모두 `Jenkinsfile`에 따라 달라진다. 이 스킬은 "tag 푸시 → Jenkins input 게이트 → ArgoCD sync" 패턴을 전제로 하되, **구체적인 스테이지 이름과 파라미터 구조는 런타임에 파악**한다.

## 전제 조건

- 배포 대상 커밋이 이미 원격 브랜치(master/main)에 반영되어 있다
- 배포 태그(`1.0.0-SNAPSHOT` 등)가 해당 커밋에 이미 달려 있다. 또는 달아야 한다
- 로컬 환경에 다음 CLI가 설치되어 있고 인증되어 있다:
  - `gh` (GitHub CLI)
  - `jenkins-cli` 래퍼 — `JENKINS_URL`, `JENKINS_USER_ID`, `JENKINS_API_TOKEN` 환경변수 필요 (일반적으로 `~/.secrets.zsh`에 저장)
  - `argocd` (ArgoCD CLI) — `argocd login` 완료 상태
- `curl`, `python3`(json 파싱), `jq`(선택) 사용 가능

Jenkins CLI는 항상 HTTP transport로 호출한다. 기본 WebSocket transport는 사내 Jenkins reverse proxy에서 `Unexpected request origin` / `CLI handshake failed with status code 403`로 실패할 수 있으므로, 모든 Jenkins CLI 명령은 `jenkins-cli -http ...` 형태를 사용한다.

## 워크플로우

### Phase 0: 사전 점검

**사용하는 명령어**
- `jenkins-cli -http who-am-i` — Jenkins 인증 상태 확인
- `argocd account get-user-info` — ArgoCD 인증 상태 확인

```bash
# Jenkins 인증 확인
jenkins-cli -http who-am-i
# → "Authenticated as: <user>"가 아닌 "anonymous"면 중단.
#   ~/.secrets.zsh 에 JENKINS_USER_ID / JENKINS_API_TOKEN 이 정의돼 있는지 확인.

# ArgoCD 인증 확인
argocd account get-user-info
# → "Logged In: true"가 아니면 argocd login 필요
```

환경변수가 로드되지 않은 경우 사용자에게 `source ~/.secrets.zsh`(또는 관련 파일)를 요청한 뒤 재시도한다.

### Phase 1: 태그 푸시

**사용하는 명령어**
- `git tag --points-at <sha>` / `git show-ref --tags <tag>` — 로컬 태그 위치 확인
- `git tag -d <tag>` / `git tag <tag> <sha>` — 재태깅
- `git push [--force] origin refs/tags/<tag>` — 원격 푸시

사용자와 배포할 태그, 대상 환경, 대상 커밋을 합의한다.

1. 로컬 태그 위치 확인:
   ```bash
   git tag --points-at <commit-sha>
   git show-ref --tags <tag>
   ```
2. 태그가 없거나 잘못된 커밋을 가리키면 **사용자 확인 후** 다시 태깅한다:
   ```bash
   git tag -d <tag>
   git tag <tag> <commit-sha>
   ```
3. 원격 푸시 (재태깅이면 force):
   ```bash
   # 새 태그
   git push origin refs/tags/<tag>

   # 재태깅 (기존 태그 이동)
   git push --force origin refs/tags/<tag>
   ```

**주의**: 상용 배포 태그에 force push는 신중히. 사용자 명시적 승인 필수.

### Phase 2: Jenkins 빌드 진행 및 입력 게이트 처리

**사용하는 명령어 (서브섹션별)**
- 2-0: `git remote get-url origin`, `jenkins-cli -http list-jobs`
- 2-1: `curl ${JENKINS_URL}/job/<repo>/job/<tag>/api/json` — 빌드 번호/상태
- 2-2, 2-6: `curl ${JENKINS_URL}/job/<repo>/job/<tag>/<build>/wfapi/describe` — 스테이지 상태
- 2-3: `curl ${JENKINS_URL}/job/<repo>/job/<tag>/<build>/input/` — 입력 폼 HTML
- 2-5: `curl ${JENKINS_URL}/crumbIssuer/api/json` — CSRF crumb, `curl -X POST .../input/<id>/submit` — 입력 제출
- 2-6(실패 시): `curl ${JENKINS_URL}/job/<repo>/job/<tag>/<build>/consoleText` — 실패 로그

태그 푸시 직후 Jenkins가 자동으로 태그 이름의 서브 잡을 생성/트리거한다 (`job/<repo>/job/<tag>`).

**Jenkins 파이프라인은 리포마다 다른 구조**를 갖는다. 다음 변형을 모두 수용해야 한다:

- 입력 게이트가 **0개**: 태그 빌드가 아무 질문 없이 바로 빌드/배포한다
- 입력 게이트가 **1개**: 한 번만 입력을 요구 (환경 선택 또는 모듈 선택)
- 입력 게이트가 **여러 개**: 초반에 "배포할 모듈 선택" → 후반에 "환경 선택" 같은 다단계
- 입력 게이트 **위치**: 파이프라인 초반/중반/후반 어디든 올 수 있다
- 입력 **의미**: 환경 / 모듈 / 커밋 / 버전 중 어떤 것도 가능하다. form의 제목(`<h1>`)을 파싱하거나 옵션 이름으로 추측

따라서 Phase 2는 "**빌드 종료 or 입력 대기**가 나올 때까지 폴링 → 입력이면 처리 → 다시 폴링"의 루프로 구성한다.

#### 2-0. Jenkins 프로젝트 확인

Jenkins 루트의 MultiBranch 잡 목록을 검색해 배포할 프로젝트를 확정한다. 리포 이름을 그대로 쓰는 경우가 많지만 컨벤션이 항상 맞지는 않으므로, **검색 키워드로 후보를 추린 뒤 유일하면 진행, 애매하면 사용자에게 질문**한다.

키워드 추출 규칙:

- 현재 git remote에서 리포 이름을 뽑고 (`vroong-osmind` 등)
- `vroong-` 같은 조직 공통 prefix를 제거한 핵심 키워드를 사용 (`osmind`)
- 그렇게 하면 `vroong-osmind`, `vroong-data-agent-server` 같이 유사한 이름이 많아도 의도한 것만 걸러낼 수 있다

```bash
# 리포 이름 추출
REPO_RAW=$(git remote get-url origin | sed -E 's|.*[:/][^/]+/([^/.]+)(\.git)?$|\1|')

# 팀 prefix 제거 (없으면 전체 이름 유지)
KEYWORD="${REPO_RAW#vroong-}"

# Jenkins 루트 잡 목록에서 검색
MATCHES=$(jenkins-cli -http list-jobs | grep -iF "$KEYWORD")
COUNT=$(echo "$MATCHES" | grep -c .)

echo "keyword: $KEYWORD"
echo "matches ($COUNT):"
echo "$MATCHES"
```

매칭 처리:

- **`COUNT == 1`**: 유일. `REPO`로 확정하고 진행.
  ```bash
  REPO=$(echo "$MATCHES" | head -1)
  ```
- **`COUNT > 1`**: 모호. 목록을 사용자에게 보여주고 어느 프로젝트인지 선택 받는다. 선택이 리포와 다른 이름이면 그 이유를 간단히 확인(예: 레거시 네이밍).
- **`COUNT == 0`**: 키워드가 너무 엄격하거나 해당 리포가 Jenkins에 없는 경우. 사용자에게 파이프라인 이름을 직접 묻거나, 키워드를 더 넓혀 재검색한다.

검색은 **루트 레벨 잡만** 걸린다. 브랜치/태그 서브 잡(`<project>/<branch>`)은 자동으로 나타나지 않으므로 프로젝트(=MultiBranch 컨테이너) 자체를 지정하는 것이 맞다.

#### 2-1. 빌드 번호 확인

```bash
JENKINS_URL="${JENKINS_URL:-https://jenkins.meshtools.io}"
# REPO는 2-0에서 확정
TAG="<tag>"                   # e.g. 1.0.0-SNAPSHOT
ENCODED_TAG=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$TAG")

# 최근 빌드의 번호와 상태 조회
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/${REPO}/job/${ENCODED_TAG}/api/json?tree=lastBuild%5Bnumber,building,url%5D" \
  | python3 -m json.tool
```

`lastBuild.building: true`면 진행 중. 해당 `number`를 `BUILD_NUM`으로 사용한다.

> 참고: 태그에 `.` 등 URL 특수문자가 있으므로 반드시 URL 인코딩한다.

#### 2-2. 입력 게이트 루프

**스테이지 이름을 하드코딩하지 않는다.** 전체 스테이지 중 `PAUSED_PENDING_INPUT` 상태인 것을 실시간으로 탐색한다. 아래 루프를 빌드가 종료될 때까지 반복한다:

```bash
BUILD_NUM="<number>"

while true; do
  # (a) 빌드 상태 및 입력 대기 스테이지 조회
  DESCRIBE=$(curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
    "${JENKINS_URL}/job/${REPO}/job/${ENCODED_TAG}/${BUILD_NUM}/wfapi/describe")

  STATE=$(echo "$DESCRIBE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
paused = [s for s in d.get('stages', []) if s['status'] == 'PAUSED_PENDING_INPUT']
if paused:
    print('PAUSED', paused[0]['name'])
else:
    print('BUILD', d.get('status'))
")
  echo "=> $STATE"

  case "$STATE" in
    "BUILD SUCCESS") break ;;
    "BUILD FAILED"|"BUILD ABORTED") echo "build failed"; exit 1 ;;
    "BUILD IN_PROGRESS"|"BUILD "*) sleep 10; continue ;;
    "PAUSED "*)
      # (b) 입력 게이트 처리 — 2-3으로
      STAGE_NAME=$(echo "$STATE" | cut -d' ' -f2-)
      break_inner=0
      ;;
  esac

  # (c) 입력 처리 후 루프 재진입
  [ "${break_inner:-0}" = "1" ] && break_inner=0 && continue
done
```

> 위 스켈레톤은 의사코드에 가깝다. 실제로는 입력이 발견되는 시점마다 2-3 → 2-4 → 2-5를 수행하고 다시 2-2로 돌아와 빌드 종료까지 관찰한다.

#### 2-3. 입력 게이트 의미와 파라미터 구조 파악

입력이 나타나면 **무엇을 묻는 게이트인지** 먼저 파악한다. form HTML의 `<h1>` 제목과 옵션 이름을 추출한다.

```bash
HTML=$(curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/${REPO}/job/${ENCODED_TAG}/${BUILD_NUM}/input/")

# 입력 제목 (예: "배포 환경 선택", "배포할 모듈 선택", "버전 확인")
TITLE=$(echo "$HTML" | python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'<h1>([^<]+)</h1>', html)
print(m.group(1) if m else '(unknown)')
")

# form action에서 input ID 추출
INPUT_ID=$(echo "$HTML" | python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'action=\"([^\"]+)/submit\"', html)
print(m.group(1) if m else '')
")

echo "input title: $TITLE"
echo "input id: $INPUT_ID"
```

파라미터 타입별 마커:

| 타입 | HTML 마커 | 제출 JSON |
|------|-----------|----------|
| boolean/checkbox 다중 | `<input name="value" type="checkbox">` + 각 `<input name="name" type="hidden" value="<opt>">` | `{"parameter":[{"name":"<opt>","value":true/false}, ...]}` |
| choice (단일 select) | `<select name="value"><option value="<opt>">` | `{"parameter":[{"name":"<PARAM>","value":"<opt>"}]}` |
| radio (단일) | `<input name="value" type="radio" value="<opt>">` | 위와 동일 |
| string | `<input name="value" type="text">` | `{"parameter":[{"name":"<PARAM>","value":"<string>"}]}` |

checkbox 다중 선택 예시:

```bash
# 옵션 추출 (checkbox 계약: <input name="name" type="hidden" value="<opt>"> 패턴 반복)
OPTIONS=$(echo "$HTML" | python3 -c "
import sys, re
html = sys.stdin.read()
names = re.findall(r'<input name=\"name\" type=\"hidden\" value=\"([^\"]+)\">', html)
print(' '.join(names))
")
echo "checkbox options: $OPTIONS"
```

choice/radio인 경우:

```bash
# select 옵션 추출
OPTIONS=$(echo "$HTML" | python3 -c "
import sys, re
html = sys.stdin.read()
opts = re.findall(r'<option value=\"([^\"]+)\">', html)
print(' '.join(opts))
")
```

#### 2-4. 사용자 승인

**추출된 제목과 옵션을 사용자에게 보여주고 명시적 선택을 받는다.** 이 단계는 어떤 경우에도 생략하지 않는다. 배포/모듈 선택은 비가역적이고 오선택이 외부 시스템에 영향을 준다.

사용자에게 제시할 내용:
- 입력 제목 (`TITLE`) — "이 게이트가 무엇을 묻고 있는지"
- 옵션 목록 (`OPTIONS`)
- 파이프라인 단계(스테이지 이름) — 초반/후반 어디에서 나온 입력인지

사용자가 선택한 값을 `SELECT` 변수에 저장한다. 다중 선택 허용이 필요한 경우 배열로 받는다.

```bash
SELECT="dev1"   # 예: 환경 선택 게이트에서 dev1
# 또는
SELECT="ordermgmt"   # 예: 모듈 선택 게이트에서 ordermgmt
```

#### 2-5. 입력 제출

CSRF crumb을 받아 파라미터 타입에 맞는 JSON으로 submit한다.

**checkbox 다중 선택 (선택된 것만 true):**

```bash
ENVS=($OPTIONS)   # 2-3에서 추출

JSON=$(python3 -c "
import json, sys
envs = sys.argv[1].split()
sel = sys.argv[2]
print(json.dumps({'parameter': [{'name': e, 'value': e == sel} for e in envs]}))
" "${ENVS[*]}" "$SELECT")
```

**choice/radio/string (단일 값):**

```bash
# PARAM_NAME은 HTML의 <input name="name" value="<param>"> 또는 <select name="value" data-name="<param>">에서 추출하거나 Jenkinsfile 참조
PARAM_NAME="ENV"   # 예

JSON=$(python3 -c "
import json, sys
print(json.dumps({'parameter': [{'name': sys.argv[1], 'value': sys.argv[2]}]}))
" "$PARAM_NAME" "$SELECT")
```

공통 제출:

```bash
CRUMB_FIELD=$(curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/crumbIssuer/api/json" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumbRequestField']+':'+d['crumb'])")

curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  -H "$CRUMB_FIELD" \
  -X POST \
  --data-urlencode "json=$JSON" \
  --data-urlencode "proceed=Choose" \
  -w "HTTP %{http_code}\n" \
  "${JENKINS_URL}/job/${REPO}/job/${ENCODED_TAG}/${BUILD_NUM}/input/${INPUT_ID}/submit"
# HTTP 302가 성공
```

제출 후 2-2로 돌아가 **빌드 종료 또는 다음 입력 게이트**가 나올 때까지 계속 관찰한다.

#### 2-6. 빌드 종료 확인

모든 입력 게이트가 처리되고 빌드가 `SUCCESS`로 끝나면 파이프라인이 선언한 부작용(이미지 빌드/푸시, helm values 갱신 등)이 완료된 상태다.

**순서는 파이프라인마다 다르다.** 이미지 푸시가 입력 게이트보다 먼저 일어날 수도, 나중에 일어날 수도 있다:
- 이미지 푸시 먼저 → 이후 "어느 환경에 배포할지" 입력 → 환경별 helm values 갱신
- 입력 먼저 → 이후 이미지 빌드/푸시 → helm values 갱신

어느 쪽이든 `SUCCESS` 시점에는 부작용이 모두 끝난다. 실제 어떤 스테이지에서 어떤 부작용이 발생했는지는 `wfapi/describe`의 stage 진행 순서와 console log로 확인한다.

`FAILED`/`ABORTED`로 끝난 경우 console log를 확인한다:

```bash
curl -s -u "${JENKINS_USER_ID}:${JENKINS_API_TOKEN}" \
  "${JENKINS_URL}/job/${REPO}/job/${ENCODED_TAG}/${BUILD_NUM}/consoleText" | tail -100
```

### Phase 3: ArgoCD 앱 동기화

**사용하는 명령어**
- `argocd app list --output name | grep -i "<repo>"` — 앱 검색
- `argocd app diff <app>` — 예상 변경 diff
- `argocd app get <app> --output json` — 현재 sync/health/image
- `argocd app sync <app> --timeout 180` — 동기화 실행
- `argocd app wait <app> --health --timeout 300` — Healthy 대기

Jenkins가 환경별 helm values를 갱신한 뒤에도 ArgoCD가 Manual sync policy인 경우 자동 반영되지 않는다. 선택한 환경에 해당하는 앱을 찾아 sync한다.

팀 내 일반적인 ArgoCD 앱 네이밍 컨벤션은 `argocd/<repo>-<env>`(예: `argocd/vroong-osmind-dev1`). 다만 모노레포/다중 모듈 구조에서는 `argocd/<repo>-<module>-<env>` 같이 다를 수 있으므로 확실치 않으면 조회한다:

```bash
argocd app list --output name | grep -i "<repo>"
```

사용자와 대상 앱 이름을 확정한 뒤 sync:

```bash
APP="argocd/${REPO}-${SELECT}"   # 단순 케이스. 모노레포면 <repo>-<module>-<env> 등으로 구성

# 변경 확인 (이미지 태그 diff 위주)
argocd app diff "$APP" | head -20

# 현재 상태
argocd app get "$APP" --output json | python3 -c "
import sys, json
d = json.load(sys.stdin)
s = d['status']
print('sync:', s['sync']['status'])
print('health:', s['health']['status'])
for img in s.get('summary', {}).get('images', []):
    if '<repo-short>' in img:   # 예: osmind, accounting 등
        print('image:', img)
"

# sync (Manual sync policy인 경우 필수)
argocd app sync "$APP" --timeout 180

# Healthy 대기
argocd app wait "$APP" --health --timeout 300
```

대부분 Manual sync policy라 `sync` 호출이 필요하다. Auto sync인 앱은 몇 분 이내 자동 반영되지만, 급한 경우 수동 sync로 가속할 수 있다.

**다중 모듈 배포 시**: Phase 2에서 모듈 선택 입력이 있었다면, 선택된 모듈에 해당하는 ArgoCD 앱을 sync한다. 환경 선택 입력이 함께 있었다면 `<repo>-<module>-<env>` 조합의 앱을 특정한다.

### Phase 4: 배포 검증

**사용하는 명령어 (선택)**
- `curl <app-url>/health` — 헬스 엔드포인트
- `kubectl logs -n vroong-<env> deploy/<app>` — 파드 로그
- `kubectl rollout status -n vroong-<env> deploy/<app>` — 롤아웃 진행 상태

- 애플리케이션 헬스 엔드포인트 호출 (보통 `/health` 또는 `/`)
- 로그 확인 (`kubectl logs -n vroong-<env> deploy/<app>`)
- 사용자 수용 테스트 (상세는 `vr-deploy-plan` 스킬의 테스트 플랜 참고)

## 자주 발생하는 이슈

### 모든 스테이지가 `NOT_EXECUTED`로 끝남

- 태그가 아닌 branch 빌드로 트리거된 경우일 수 있다. 많은 공유 라이브러리가 "tag 빌드에서만 배포 스테이지 실행" 정책을 쓴다.
- master/main 브랜치 빌드는 no-op으로 끝나는 것이 정상.
- 배포하려면 태그를 push해야 한다. 현재 리포의 `Jenkinsfile`/공유 라이브러리를 읽어 어떤 트리거에서 어떤 스테이지가 실행되는지 확인.

### 입력 게이트가 없이 바로 SUCCESS로 끝남

- 파이프라인이 환경/모듈 선택 없이 모든 환경에 자동 배포하는 구조일 수 있다 (CI-only 또는 GitOps 기반).
- 해당 리포의 `Jenkinsfile`/helm values repo 구조를 검토해 배포가 실제로 일어나고 있는지, ArgoCD가 뒤에서 처리하는지 확인.

### `HTTP 403 Forbidden` on input submit

- CSRF crumb 누락 또는 만료. crumb을 다시 받아 재시도.
- 인증 토큰 권한 부족. `jenkins-cli -http who-am-i`로 권한 그룹 확인.

### ArgoCD `OutOfSync` 지속

- Jenkins 빌드 내 "helm values update" 관련 스테이지(이름은 리포마다 다름)가 `SUCCESS`인지 확인. 실패 시 helm values repo 커밋 권한 문제일 가능성.
- values repo(`<repo>-helm-values` 등)에서 최신 커밋의 image tag를 확인하여 실제로 갱신됐는지 검증.
- ArgoCD 앱의 `source` 설정(repo URL, path, target revision)이 기대대로인지 `argocd app get <app>`로 확인.

### 이미지 태그 포맷이 예상과 다름

- 공유 라이브러리마다 태깅 규칙이 다르다. 일반적 패턴:
  - `<git-tag>-<short-sha>` (예: `1.0.0-SNAPSHOT-d8756f0`)
  - `<git-tag>` 그대로
  - `<branch>-<short-sha>`
- helm values의 `image.tag` 필드와 실제 ECR에 push된 태그를 대조해 어떤 패턴이 쓰였는지 확인.

### 태그 재사용(force push) 주의

- `1.0.0-SNAPSHOT` 같은 롤링 태그는 재사용이 관례지만, `v1.2.3` 같은 릴리스 태그는 **재사용 금지**. 재배포가 필요하면 패치 태그(`v1.2.3-hotfix1`)를 새로 발행한다.
- force push는 이미 배포된 환경의 태그 불변성을 깨므로 상용 배포 태그에는 특히 신중히.

## 다른 스킬과의 연계

- `vr-deploy-plan`: 상용 배포 시 배포 플랜 Notion 페이지를 먼저 작성한 뒤 이 스킬로 실제 배포를 수행한다
- `vr-commit`/`vr-create-pr`: 배포 대상 커밋/PR 자체를 준비할 때 사용
