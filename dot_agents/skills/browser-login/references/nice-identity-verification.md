# NICE/PASS 휴대폰 본인확인 창

공공·금융 사이트의 신청서에서 `본인인증` 버튼을 누르면 `nice.checkplus.co.kr` 창이 새 탭으로 열린다. 한전ON 명의변경 신청서에서 확인했다.

## 흐름

한 화면에서 한 단계씩 진행하고, 각 단계는 **입력이 끝나면 `Enter`로 넘어간다**.

1. 통신사 선택 — 알뜰폰이면 `알뜰폰 사업자 확인` → 탭(SKT/KT/LGU+ 알뜰폰) → `확인` → 통신사 버튼.
2. 인증방법 — `PASS 인증` / `QR코드 인증` / `문자(SMS) 인증`. 사용자가 고른다. SMS가 가장 단순하다.
3. `본인확인 이용 동의` 체크 → 약관 패널을 열어 5개(개인정보 이용, 고유 식별정보 처리, 서비스 이용약관, 통신사 이용약관, 제3자 정보제공)를 각각 열고 `확인`을 누른다. 패널을 닫지 않으면 `다음` 버튼이 패널에 가려 `intercepts pointer events`로 실패한다.
4. 이름 → 생년월일 6자리 + 성별 1자리(주민번호 뒤 첫 자리) → 휴대폰번호 11자리.
5. 보안문자(캡차) → `인증번호 받기` → 문자로 온 번호 입력.

## 단계 이동은 `Enter`다. `Tab`은 안 된다

`다음` 버튼은 입력이 유효해질 때까지 `display: none`이다. 필드에 값을 넣고 `Tab`을 눌러도 다음 단계로 안 넘어간다 — 포커스를 옮길 뿐이다. 값을 넣은 뒤 그 필드에서 `Enter`를 누르면 다음 필드/단계가 열리고 `다음`이 보이기 시작한다. 타이핑 후 기다리기만 해도 자동 진행되지 않는다.

## 좌표로 필드를 고르지 않는다

필드가 세로로 촘촘히 붙어 있어서 `getBoundingClientRect()` 중심에서 조금만 어긋난 좌표를 누르면 **이웃 필드**가 포커스를 받는다. 그러면 이후 타이핑이 전부 그 필드에 이어 붙는다 — 이름 칸이 `홍길동01012345678`처럼 되는 사고가 이것이다.

- 필드마다 넣은 직후 `document.querySelector(sel).value.length`를 되읽어 기대 길이(이름 3, 생년월일 6, 성별 1, 휴대폰 11)와 맞는지 확인한다.
- 어긋났으면 그 필드만 `Control+A` → `Backspace`로 비우고 다시 넣는다. 페이지 전체를 새로고침하면 캡차도 새로 받아야 하니 필드 단위로 고친다.

## 캡차 이미지는 `fetch` + base64로 뽑는다

캡차 `<img src=".../cert/captcha/image/...">`는 스크린샷으로는 제대로 안 잡힌다(`screenshot({clip})`·`sips` 크롭 모두 빈 이미지). 대신 페이지 안에서 `fetch` → `btoa` → 파일로 쓰면 읽을 수 있는 PNG(140×40)가 나온다.

```js
const b64 = await page.evaluate(async () => {
  const img = [...document.querySelectorAll('img')].find(i => (i.src || '').includes('/cert/captcha/image/'));
  const resp = await fetch(img.src, { cache: 'no-store' });
  const bytes = new Uint8Array(await resp.arrayBuffer());
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
});
await fs.writeFile('/tmp/cap.png', Buffer.from(b64, 'base64'));
```

`page.fetch(src, { saveAs })`는 검은 이미지가 나왔다 — `fetch`+btoa 쪽을 쓴다.

## 캡차 읽기는 한 번만 시도한다

뷰전으로 읽은 값이 틀리면 `처리실패!` 화면(`/cert/mobileCert/fail/message`)과 `재시도` 버튼이 나오고, 재시도하면 **통신사 선택부터 다시** 해야 한다(입력한 이름·주민번호가 날아간다).

- 한 번 읽어 넣고 결과를 본다. 틀렸으면 재시도하지 말고 사용자에게 캡차만 넘긴다 — 처음부터 다시 도는 비용이 크다.
- 캡차를 읽었다고 확신할 수 없으면, 다 채워 놓고 마지막 캡차 입력만 사용자에게 부탁하는 편이 빠르다.

## 이 창은 사용자와 같은 Space에 있다

새 탭으로 열리므로 `task.tabs()`로 라벨을 찾아 `task.page("p3")`처럼 잡는다. 원래 신청서 탭은 그대로 두고, 인증이 끝나면 그 탭으로 돌아가 제출한다.

사용자가 브라우저를 직접 잡으면 이후 명령이 `Control of this task space is with the user`로 막힌다. 이건 우회할 장애가 아니라 정지 신호다 — `takeOverTaskSpace()`를 스스로 부르지 말고 이어갈지 묻는다.
