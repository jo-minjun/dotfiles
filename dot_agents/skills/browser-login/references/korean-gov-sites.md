# 홈택스·정부24: 로그인 뒤 업무 화면 다루기

간편인증 로그인(`references/simple-auth.md`)을 마친 뒤, 실제 업무 화면에서 조회·확인을 하는 절차다. 홈택스가 WebSquare 프레임 구조라 일반 페이지와 다르게 다뤄야 하는 부분만 모았다.

## 로그인 성공 판정

- 상단에 **이름 + `로그아웃`** 이 보이면 성공이다. 홈택스는 로그인 뒤 URL이 `menuCd=index4`로 바뀐다.
- `인증 완료`를 누른 뒤 결과가 같은 화면에 나올 수 있으니, URL 변화만으로 판단하지 말고 snapshot에서 로그아웃 버튼을 확인한다.

## 홈택스 간편인증 팝업 진입

로그인 전 화면(`menuCd=index3`)의 로그인 박스에 있는 `개인용 간편인증` 앵커를 누르면 레이어 팝업 iframe이 뜰다. 2~3초 기다려야 안쪽이 그려진다. 민간 인증서 버튼(`카카오톡`, `네이버`, `토스`, `통신사PASS`)을 고르고, 이름·생년월일·휴대폰을 채운 뒤(휴대폰은 앞자리 `combobox` `010` + 나머지 입력란) 필수 동의를 켜고 `인증 요청`을 누른다. 사용자가 앱에서 승인한 뒤 `인증 완료`를 누르면 로그인된다.

## 업무 화면 찾기

전체메뉴를 헤집는 것보다 **상단 검색창**이 빠르다. placeholder가 `검색어를 입력하세요!`인 입력란에 업무명을 넣고 `검색`을 누르면, `적용된 검색어 '...' / 메뉴 (N건)` 아래 결과 목록이 나온다. 그 목록의 `anchor`를 누르면 해당 업무 화면으로 이동한다.

- 민원 신청 진행상황은 검색어 `사업자등록 진행상황` → `사업자등록 신청·정정·휴폐업 > 민원신청 처리결과 조회`.
- 조회 화면의 접수일자 기본값은 최근 1주일이다. 그대로 `조회`를 누르면 최근 건이 뜬다.

## 신청 화면은 보안프로그램 벽에 막힌다

`개인 사업자등록 신청` 같은 **신청** 화면은 Mac/Chrome에서 `통합설치 프로그램 안내`(공동인증서·KUPLOAD·MAGIC-XML·IPINSIDE)로 대체된다. 이 화면에는 닫기·계속 버튼이 없다. 설치를 대신 해 주지 말고, **조회 메뉴로 목적을 달성**하거나(대개 그것으로 충분하다) 사용자에게 넘긴다.

## alert 창이 evaluate를 막는다

신청 메뉴를 누르면 "통합설치 화면으로 이동합니다..." alert가 뜨고, 그동안 `Runtime.evaluate` 계열 호출이 전부 실패한다. 클릭 직후 `page.acceptDialog()`를 먼저 부르고 이어간다.

## 프레임 안쪽 값 읽기 (cross-origin iframe)

홈택스의 간편인증·업무 화면은 별도 프레임(`simple_iframeView` 등)에 있다. `page.evaluate()`에서 `iframe.contentDocument`는 cross-origin이라 `null`이고, `document.querySelectorAll`로도 안 잡힌다. CDP로 프레임 컨텍스트를 만들어 읽는다.

```js
const tree = await page.cdp("Page.getFrameTree", {});
// name(예: "simple_iframeView") 또는 url로 대상 frameId를 찾는다
const frameId = "...";
const w = await page.cdp("Page.createIsolatedWorld", { frameId, worldName: "probe" });
const r = await page.cdp("Runtime.evaluate", {
  contextId: w.executionContextId, returnByValue: true,
  expression: `(() => JSON.stringify([...document.querySelectorAll('input[type=checkbox]')]
      .map(c => ({id: c.id, name: c.name, checked: c.checked}))) )()`,
});
console.log(JSON.parse(r.result.value));
```

- snapshot에는 `checkbox`만 나오고 `checked` 상태가 안 나온다. 필수 동의가 실제로 켜졌는지는 이 방법으로 확인한다.
- 입력란의 값은 이 방법으로도 읽지 않는다(`browser-login` 규칙).
- 홈택스 필수 동의의 실제 DOM id는 `totalAgree`, `privacy`, `policy4`다. 처음에는 셋 다 `checked: false`다.
- **틀린 프레임을 읽으면 "클릭이 안 먹었다"로 오해한다.** 메인 문서에서 `page.evaluate`로 체크박스를 모으면 팝업이 아니라 바깥 로그인 화면의 것(`mf_txppWframe_loginboxFrame_ckbBaseApp_input` = PC방화벽/키보드보안/아이디저장)이 잡힌다. 그 값은 전부 `false`라 클릭 실패처럼 보이지만, 정작 팝업의 필수 동의는 이미 켜져 있을 수 있다. `id`가 `totalAgree`/`privacy`/`policy4`가 아니면 프레임을 잘못 잡은 것이니 `Page.createIsolatedWorld`로 팝업 컨텍스트에서 다시 읽는다. 상태를 단정하기 전에 id부터 확인한다.

## 체크박스 클릭은 조용히 실패한다

웹스퀘어 커스텀 체크박스는 `page.click("@ref")`로 누르면 **예외 없이 지나가는데 `checked`는 `false`로 남는다**. 실패를 알아채기 어려우니, 누른 뒤 반드시 위 CDP 방법으로 `checked`를 되읽어 확인한다.

가장 확실한 방법은 프레임 안에서 `#totalAgree`를 DOM 클릭하는 것이다. 그러면 필수 두 개(`#privacy`, `#policy4`)가 같이 켜진다.

```js
// 위 createIsolatedWorld 컨텍스트에서
await page.cdp("Runtime.evaluate", {
  contextId: ctx, returnByValue: true,
  expression: `document.querySelector('#totalAgree').click()`,
});
```

## ref는 프레임이 다시 그려지면 죽는다

입력란을 채우거나 인증서를 고르면 iframe이 재렌더되어 이전 `@ref`가 전부 `Stale ref`가 된다. 버튼을 누를 때마다 `page.snapshot({ scope: "full_page" })`를 새로 찍고, 라벨 정규식으로 ref를 다시 뽑는다.

```js
const snap = await page.snapshot({ scope: "full_page" });
const m = [...snap.matchAll(/button \[ref=(\d+)\]\s*\n\s*text "인증 요청"/g)];
const ref = m.at(-1)[1]; // 같은 라벨이 여러 번 나오면 마지막 것
```

## 메뉴 클릭이 pointer interception으로 막힐 때

홈택스 헤더의 큰 메뉴(`증명･등록･신청･사업장현황` 등)는 다른 레이어가 포인터를 가로채서 `page.click`이 `intercepts pointer events` 타임아웃으로 실패한다. 메뉴를 계속 노리지 말고 세션 유지 주소로 페이지를 다시 열어 검색창부터 새로 잡는다.

```js
await page.goto("https://hometax.go.kr/websquare/websquare.html?w2xPath=/ui/pp/index_pp.xml&menuCd=index4");
await page.waitForTimeout(3500);
```

- 재진입하면 `@ref`가 전부 새로 매겨진다. 이전 ref로 `fill`/`click`을 이어 쓰면 `Stale ref`가 나므로, 검색 입력란은 `placeholder="검색어를 입력하세요!"` 정규식으로 다시 뽑는다.
- 신청 화면(`menuCd=search&searchInfo...`)에서 멈췄을 때도 같은 방법으로 `menuCd=index4`로 빠져나온다.
- 상단 검색창에는 업무 화면 이름이 아니라 **찾으려는 일의 표현**을 넣는다. `사업자등록증명`처럼 서류 이름으로는 결과가 잘 안 나오고, `사업자등록 진행상황`이 `민원신청 처리결과 조회`를 바로 띄운다.

## 증명 발급 → PDF 저장

발급 신청 화면은 조회 화면과 다르다. `사업자등록증명` 같은 **즉시발급 증명**은 보안프로그램 벽에 막히지 않고 실제로 발급까지 진행된다. (`개인 사업자등록 신청`처럼 새로 사업자를 만드는 신청만 설치 벽에 막힌다.)

1. 검색창에 서류명을 넣고 결과의 `국세증명 > 즉시발급 증명 > 사업자등록증명` 앵커를 누른다.
2. 사업자등록번호를 고른다. **`page.click("@ref")`로는 목록이 안 열린다** — 화면에는 WebSquare 컴보박스로 보이지만 실제 `<select>`가 DOM에 있으므로 값을 지정하고 `change`를 보낸다.

   ```js
   const el = document.querySelector('#mf_txppWframe_pfm_UTECAAA0Z001_sbx_pfbPsenNtplBsno');
   el.value = '000-00-00000';
   el.dispatchEvent(new Event('change', { bubbles: true }));
   ```

   고르면 상호·대표자명이 자동으로 채워진다. 채워지지 않으면 값이 틀린 것이다. 옵션 목록은 `page.evaluate`로 `[...document.querySelectorAll('select')].map(s => [...s.options].map(o => o.text))`를 찍어 확인한다.
3. 필수 컴보박스(사용용도 `...sbx_cvaDcumUseUsgCd`, 제출처 `...sbx_cvaDcumSbmsOrgnClCd`, 수령방법 `...sbx_cvaAplnRecptMthd`)도 같은 방식으로 값을 지정하고, snapshot에 선택한 텍스트가 그대로 나오는지 확인한다. 값이 안 들어가면 `작성완료`에서 필수항목 검증에 걸린다.
4. `작성완료` → "작성이 완료되었어요. 신청하시겠습니까?" 팝업의 `신청하기` → "정상적으로 접수되었습니다" 알림의 `확인`.
5. `menuCd=UTECAAA0A015` 결과 화면으로 넘어간다. `민원처리결과 조회`를 누르면 목록(`menuCd=UTECAAB0A001`)에 방금 건이 맨 위에 발급번호·접수번호·`처리완료`와 함께 뜬다.
6. 목록의 `출력` → 위·변조 방지 경고 팝업에서 `예`. 새 탭이 `https://sesw.hometax.go.kr/serp/clipreport.do`로 열린다.
7. 새 탭은 `task.adopt()`로 채택한 뒤 CDP로 PDF를 저장한다. 인쇄 대화상자를 거치지 않는다.

   ```js
   const res = await p2.cdp("Page.printToPDF", {
     printBackground: true, paperWidth: 8.27, paperHeight: 11.69,
     marginTop: 0.4, marginBottom: 0.4, marginLeft: 0.4, marginRight: 0.4,
   });
   await fs.writeFile(outPath, Buffer.from(res.data, "base64"));
   ```

8. 저장한 PDF를 `read_file`로 열어 발급번호·상호·사업자등록번호·주소·개업일을 확인하고 파일로 보낸다.

**함정**

- **`출력` 버튼은 `intercepts pointer events`로 실패하는데, 클릭은 이미 먹혀 팝업이 떠 있는 경우가 많다.** 실패 예외를 보고 재시도하지 말고 스크린샷을 찍어 팝업 유무부터 확인한다. 같은 레이어가 다음 단계 버튼도 가로챈다.
- clipreport 본문은 글자마다 줄바꿈되어 나온다(`발\n급\n번\n호`). 렌더링이 깨진 게 아니라 추출 방식 문제이므로, 판독은 저장한 PDF를 `read_file`로 읽어서 한다.
- 발급 흐름 중간에 `menuCd=index4`로 재진입하지 않는다. 입력이 초기화된다. 세션이 끊겼으면 처음부터 다시 한다.
- 마스킹된 값(주민번호 뒷자리, 이메일 일부)은 그대로 두고 발급한다. 원본 확인이 필요하면 사용자에게 넘긴다.

## 완료 보고

민원처리결과 목록에서 **민원명 / 상태 / 접수번호 / 접수일시**를 그대로 옮긴다. `출력` 버튼이 있으면 발급까지 진행해 PDF로 받아 주고(위 "증명 발급 → PDF 저장"), 화면 캡처나 파일을 함께 보낸다.

## 조회로 끝나면 되는 일에 신청 화면을 열지 않는다

상태 확인 요청은 `민원신청 처리결과 조회` 한 번으로 끝난다. 신청 화면은 보안프로그램 벽에 막혀 아무것도 못 보고, 사용자를 Mac에서 설치 안내로 밀어넣는다. 대상이 `사업자등록 신청`인지 `사업자등록증`인지애매하면 **신청이 아니라 조회·진행상황 쪽으로 먼저 간다**.
