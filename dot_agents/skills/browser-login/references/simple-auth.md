# 간편인증(민간인증서) 로그인

이 문서는 browser-login 스킬의 `SKILL.md`가 간편인증으로 가라고 했을 때 읽는다. `SKILL.md`의 "규칙"은 이 문서의 모든 단계에 적용한다. 이 문서가 말하는 "절차", "코드 예시", 배너 경로는 `SKILL.md`에 있다.

정부24, 홈택스, 병무청 같은 공공기관 사이트는 아이디 대신 간편인증으로 로그인한다. 간편인증은 이름, 생년월일, 휴대폰 번호를 입력하고, 사용자가 고른 민간인증서 앱(카카오톡, 네이버, 토스, 통신사PASS 등)으로 승인 요청을 보내는 방식이다. 정부24에서는 `로그인` → "정부 통합로그인"의 `개인` 탭 → `간편인증`에 있다.

1. 어느 인증서로 요청할지 사용자에게 묻는다. 기본 인증서는 없다. 간편인증 창을 열기 전에 묻는다. 정부24에서는 창을 연 뒤 몇 분이 지나자 `인증 요청`이 "토큰 유효 시간 만료"로 실패했다.
2. 1Password 신원 항목의 값을 임시 파일로 옮긴다. 아래 "신원 정보 읽기"를 쓴다.
3. 간편인증 창을 열고, 한 번의 `ego-browser nodejs` 실행 안에서 다음을 모두 한다.
   1. 인증서를 고른다.
   2. 이름, 생년월일(YYYYMMDD), 휴대폰 번호를 채운다. 휴대폰 번호가 앞자리 선택(`010`)과 나머지 입력란으로 나뉘어 있으면 나눠서 넣는다.
   3. 필수 동의를 체크한다. 사용자가 이 스킬로 로그인을 맡겼으므로 필수 동의는 체크한다. 전체동의에 마케팅 같은 선택 동의가 섞여 있으면 필수 동의만 체크한다.
   4. 인증서 선택과 동의 체크가 반영됐는지 확인한다. snapshot에는 이 상태가 나오지 않을 수 있다. 그러면 `page.evaluate()`로 체크박스의 `checked`와 인증서 항목의 선택 표시(정부24는 `li`의 class `selected`)만 읽는다. 입력란의 값은 읽지 않는다. 맞지 않으면 요청하지 않고 멈춘다.
   5. `인증 요청`을 누르고 snapshot을 본다. 안내 창(예: 토큰 만료)이 나오면 안내 창과 간편인증 창을 닫고 2번부터 1번만 다시 한다.
4. 임시 파일을 지운다.
5. 사용자에게 "<인증서> 앱에서 <사이트>의 인증 요청을 승인해 주세요"라고 알리고 멈춘다. 사용자는 휴대폰에서만 승인하므로 `handOff()`는 부르지 않는다. Space도 닫지 않는다.
6. 사용자가 승인했다고 하면 창의 `인증 완료`를 누르고 "코드 예시"처럼 기다린다. 로그아웃 버튼이 보이면 성공이고, "절차"의 7번으로 간다.
7. 로그인 뒤 "회원정보 재확인" 같은 안내 화면이 나오면 정보를 고치지 않고, 그 화면이 나왔다고 보고에 적는다. 정부24는 로그인 직후 이 화면으로 이동했다.

## 신원 정보 읽기

1Password 서비스 계정 래퍼는 둘이다. `with_me_sa`는 개인 금고(`me-sa`), `with_im_sa`는 업무 금고(`im-sa`)를 쓴다. 로그인하려는 사이트가 회사 계정이면 `with_im_sa`를 쓴다. 둘 다 `~/.local/bin`에 있는 bash용 래퍼로, `~/Shell/commands.sh`(`with_im_sa`는 `~/Shell/work.sh`도)의 zsh 함수를 불러 bash 기반 도구에서도 같은 이름으로 부를 수 있게 한다. 가용성은 `command -v with_me_sa`로 확인한다. 인자 없이 부르면 usage가 나오고, `--help`를 넘기면 그 문자열을 명령으로 실행해 `command not found: --help`가 나므로 쓰지 않는다. 서비스 계정은 `--vault`를 줘야 한다. 래퍼가 PATH에 없으면 신원 자동 입력은 건너뛰고 배너 경로로 돌아간다. `op`이 설치돼 있어도 서비스 계정 인증이 없으면 금고를 읽지 못하므로, 토큰을 추측하거나 사용자에게 이름·생년월일·휴대폰 번호를 물어 대신 채우지 않는다. 필드 이름(성, 이름, 생일, 휴대전화)은 1Password의 한국어 필드 이름이다. 신원 항목이 2개 이상이면 어느 항목인지 사용자에게 묻는다.

```bash
umask 077
vault=$(with_me_sa op vault list --format json | jq -r '.[0].id')
item=$(with_me_sa op item list --categories Identity --vault "$vault" --format json | jq -r '.[0].id')
with_me_sa op item get "$item" --vault "$vault" --format json \
  | jq '{last: (.fields[]|select(.label=="성").value), first: (.fields[]|select(.label=="이름").value),
         birth: (.fields[]|select(.label=="생일").value), phone: (.fields[]|select(.label=="휴대전화").value)}' \
  > /tmp/browser-login-identity.json
```

`ego-browser nodejs` 스크립트는 셸의 환경 변수를 받지 않으므로 파일에서 읽는다.

```js
const fs = await import("node:fs/promises");
const id = JSON.parse(await fs.readFile("/tmp/browser-login-identity.json", "utf8"));
const name = `${id.last}${id.first}`;
// 생일은 Unix 시간(초)이다. 한국 시간 기준 날짜로 바꾼다.
const birth = new Date(Number(id.birth) * 1000).toLocaleDateString("sv-SE", { timeZone: "Asia/Seoul" }).replaceAll("-", "");
const phone = String(id.phone).replace(/\D/g, ""); // 01012345678
const mask = (text) => [name, birth, phone.slice(3), phone].reduce((acc, value) => acc.split(value).join("***"), text);
```

## 정부24의 간편인증 창

| 요소 | 찾는 방법 |
|---|---|
| 인증서 버튼 | `paragraph "<인증서>버튼을 활성화하려면 두 번 탭하세요"` 바로 위의 `anchor [ref=N]` |
| 이름, 생년월일, 휴대폰 번호 | placeholder가 `홍길동`, `19900101`, `12341234`인 입력란 |
| 휴대폰 앞자리 | 휴대폰 번호 입력란 앞의 `combobox`. `selectOption()`으로 `010`을 고른다 |
| 전체동의 | `text "전체동의"` 바로 앞의 `checkbox` |
| 요청과 완료 | `인증 요청` 버튼. 요청 뒤에는 같은 창에 `인증 완료` 버튼이 나온다 |
