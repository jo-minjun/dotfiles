---
name: iph
description: 사용자의 실제 아이폰(시뮬레이터 아님)에서 앱 화면을 읽고 조작한다. `iph` CLI나 iph_* MCP 도구로 화면 요소(접근성 트리)를 읽고 탭 · 입력 · 스크롤하며, 여러 단계는 자바스크립트 스크립트 한 번으로 실행하고, 되풀이할 순서는 저장해 둔다. "아이폰에서 ○○ 해 줘", "폰에서 확인해 줘", "폰 앱에 있는 내역 · 목록 가져와 줘", "폰 앱 자동화", "iph 스크립트 만들어 줘"처럼 사용자의 실제 폰 화면을 보거나 눌러야 하는 요청이면 iph를 말하지 않아도 이 스킬을 쓴다. 실제 아이폰 작업에는 mobile-mcp나 스크린샷을 보고 좌표를 누르는 방식보다 이 스킬을 먼저 쓴다. iOS 시뮬레이터, 안드로이드, 앱 빌드 · 설치에는 쓰지 않는다.
---

# iph: operate the user's real iPhone

`iph` reads the iPhone's screen as a list of elements (label, value, role, position) and taps, types and scrolls. It talks to the phone directly; nothing is installed on it. Every command prints one JSON object. If `iph_*` MCP tools are present they take the same arguments and return the same JSON; otherwise run `iph` in the shell.

This is a real phone with the user's accounts on it. A tap cannot be taken back, so the habits below are about not acting on a guess.

## Before the first command

- Use the phone iph is set up for (`--udid`, `IPH_UDID` or `udid` in `~/.config/iph/config.toml`). If several iPhones are connected and none is chosen, iph says so; ask the user which one rather than picking.
- Start with `iph read`. If it fails with `tunnel_failed`, `ax_unavailable` or `ax_timeout`, run `iph doctor` and pass each failed check's `user_action` on to the user in their words.
- Open only the app the task needs.

## The loop: read, act, check

1. **Read** before you act: `iph read` gives `elements[]` with `id`, `role`, `label`, `value`, `frame` (points), `enabled`. Only what is on screen, unless `--all`. What labels cannot tell you (what a photo shows) needs `iph screenshot -o /tmp/screen.png`, then look at the file: always PNG, about 1 s on a plain screen and 5 s on one full of photos, so take one only when the labels are not enough.
2. **Act** on an element by what it says, not by coordinates: `iph tap "일반"`, `iph type "hello"`, `iph scroll down --until "개발자"`. Coordinates go stale the moment the screen moves; a label is found again each time.
3. **Check** the result, because the phone never confirms that a touch arrived:
   - A tap waits for the screen to change and hold still (up to 2.5 s for the change, 5 s in all), then returns that screen: `elements[]` as `iph read` gives them. Decide the next step from those; no `iph read` needs to follow. `--no-wait` (script and MCP: `no_wait: true`) reads once right after the tap and returns no elements, for taps that change nothing, such as a keypad.
   - `screen_changed: false` after a tap means nothing visible happened within 2.5 s. Look at the returned elements before deciding what next; do not tap again on the assumption that it was lost.
   - `app_changed: true` means another app came to the front (a banner was hit, a link opened). Stop and tell the user.

## Outcomes

| `outcome` | What to do |
|---|---|
| `done` | Continue. With `ok: false` (only `scroll --until` that did not find its target, `error.code: "not_found"`): the scrolls went out; the target is not in that direction. |
| `not_sent` | Nothing reached the phone. Fix the cause (`error.code`, `error.hint`) and try again. |
| `unknown` | Input may have reached the phone. Do not send it again: a second tap on a button that did work is a double order or a double message. Run `iph read` and look. |

Frequent `error.code`s: `not_found` (`screen_summary.labels` shows what is on screen; scroll or go to the right screen), `ambiguous_selector` (`candidates` lists the matches; narrow with `role=`, `within=`, `index=`), `covered` (something overlaps the target; scroll), `no_focused_field` (tap the text field first).

## Do Not Disturb

A notification banner drops over the top of the screen, is not in the element list, and takes the tap meant for what is under it. iph does not switch Focus by itself, and you do not need to either: start the work without it. Only when a banner has taken a tap in this work, turn Do Not Disturb on with `iph dnd on` (MCP: `iph_dnd` with `"action": "on"`; 11 to 36 s, Control Center shows for a moment), and put the user's Focus back with `iph dnd off` when the work is done; until then the user misses notifications.

## Money, messages, orders

iph has no guard: it presses pay, send and order buttons like any other, in any app. What to press follows the user's instructions. After such a tap comes back `unknown`, read the screen before anything else: a second press is a second payment or a second message. A Face ID, passcode or payment-authentication prompt waits for the user.

## What is on the screen belongs to the user

Answer with what was asked for. Do not copy readings of banking, messaging or account screens into a repository, a script file or notes you keep; a saved script holds the steps, never the data it read.

## One action, then one script, then a saved script

A fresh reading takes 1 to 2 s and a tap about 3 s with the screen it brings up; that is the phone's pace, not something to retry around. What you can save is the model turn between steps. Work in this order:

1. **One action at a time** while the screen is new to you: `iph read`, then one `iph tap` at a time, each returning the next screen. Note the labels you see; the script will use them.
2. **One script** once you know the way: put the steps into a single `iph script -` call (MCP: `iph_script` with `code` and `args`). Loops, conditions and date arithmetic run inside that one call.
3. **Save it** when the user will want the same thing again: write the code to `~/.config/iph/scripts/<name>.js`, first line a `// comment` that says what it does, and run it with `iph run <name> [--arg k=v]` (MCP: `iph_run`). `iph scripts` lists what exists; look there before writing a new one. Personal scripts live in that folder, not in a repository. Run a new script three times before calling it done: one that passes once can still break on a slow screen.

```sh
iph script - <<'EOF'
launch("com.apple.Preferences", { restart: true });
scroll("down", { until: "일반" });
tap("일반");
tap("정보");
return { ios_version: readField({ selector: { label: "iOS 버전" }, take: "value" }) };
EOF
```

The result: `outputs` (what the script returned), `logs`, `calls`, `inputs_sent`. A `tap()` returns the screen it brought up (`elements`), so end a script with `return tap(...)`, or with `return read()` after other commands, to see where it ended; an `iph read` after the script costs another turn.

### What a script can call

A script is the body of a function, so `return` ends it. The commands are functions that take the same arguments and return the same result objects as the CLI:

- `read(opts)`, `find(selector)`, `tap(target, opts)`, `swipe(direction | {from, to}, opts)`, `scroll(direction, {until, max})`, `type(text, {clear, submit})`, `key(name)`, `button(name)`, `launch(app, {restart})`, `apps()`. For example `read({ app: true }).elements`, `tap("일반").screen_changed`, `find("label~=업데이트").count`.
- `tap(selector)` waits up to 5 s for the element and taps once it holds still (a screen that has just come up may still shift its rows); `{timeout_ms, settle: false}` change that. Like the CLI it then waits for the screen to settle; `{no_wait: true}` skips that. `tap([a, b, c])` presses several targets in a row without re-reading, for keypads.
- `waitFor(selector, {timeout_ms})` waits for an element (8 s by default) and sits out a system panel that covers the app for a moment.
- `readField({selector, take, regex})` returns one text. `take`: `value` | `label` | `identifier` | `text`; `regex` keeps its first capture group.
- `readList({row, columns, key, group, stop_below, max_scrolls})` scrolls a list and returns `{rows, scrolls, ended}` with each row once. `columns: {name: {take, regex}}`, or `{name: {value: "…"}}` for a constant. `group: {selector, regex, as}` gives each row the heading it stands under (a date line), and `stop_below: N` stops once a heading's number falls below N. `key: "column"` names the column that identifies a row; use it when rows change while the list is read (a clock, time left).
- `args` holds the `--arg k=v` values as text (`Number(args.n)` for a number). Return an object, or call `output(key, value)`, and it comes back as `outputs`. `log(…)` lines come back as `logs`. `sleep(ms)` waits.
- Any call takes `hint: "…"`: what to tell the person if the script stops there. A screen that waits for Face ID: `waitFor(sel, { timeout_ms: 40000, hint: "폰을 봐 주세요" })`.
- There are no files, no network and no timers. `Date`, `JSON`, `RegExp` and the rest of the language work.

### When a call fails

A failed call throws an `Error` with `code`, `outcome`, `hint` and `result` (the full result object). Leave it uncaught unless the step is truly optional. The script then stops, and its result says where and why: `failed_call` (`cmd`, `line`, `outcome`), `reason` (`code`, `message`), `screen_summary`, `inputs_sent`. Do not wrap a whole script in `try`: one that swallows errors goes on acting on a screen it did not expect.

```js
// Optional: dismiss a notice only if it is there.
try { tap("닫기", { timeout_ms: 1500 }); } catch (e) { if (e.code !== "wait_timeout") throw e; }
```

The `outcome` of a script that stopped:

- `unknown`: input had gone out before it stopped. Running it again would send that input again, so read the screen first. After a call whose own outcome is `unknown` the script is ended and cannot go on, even if it catches the error.
- `not_sent`: nothing had been sent. Fix the cause and run it again.

After `launch`, that app must stay in front; if another one comes up, the script stops with `unexpected_app`.

`iph batch` (a JSON list of steps, MCP `iph_batch`) still works for a short fixed sequence, but a script does the same and more.

## Selectors

- A plain string is an exact label: `"일반"`. A row labelled `"Wi-Fi, HomeNet"` also matches `"Wi-Fi"`.
- `label~="contains"`, `label/regex/`, `role=button`, `value~="…"`, `id=<identifier or element id>`, `within="<selector>"`, `index=N` (counts from 0 in reading order: `index=1` is the second match), combined with spaces: `role=button label~="삭제"`.
- In scripts, MCP and batch an object works too: `{"label": "일반", "role": "button"}`, with `label_contains`, `label_regex`, `value`, `value_contains`, `id`, `id_contains`, `id_regex`, `within`, `index`.
- Several matches are an error, never a guess. Read the `candidates` and narrow.
- `id=` needs identifiers, which arrive about 0.5 s after the labels (`iph read --full`).

## Typing

`iph type "글"` pastes into the field that has the keyboard, so tap the field first. `--clear` replaces the content, `--submit` presses Return. The result has `value` (what the field shows now) and `clipboard_restored`. iph does not judge `value`: apps format, mask and correct what is pasted (`30000` shows as `₩ 30,000`), so you decide whether it is right. A `value` that is still what the field held before means the paste did not happen; before `--submit` sends something that matters, type without it, look at `value`, then `iph key return`. When the user had copied something in an app, it cannot be put back (`clipboard_restored: false`, `clipboard_note`); tell the user. The on-screen keyboard disappears for a moment while typing; that is expected.

## Commands at a glance

`read`, `find`, `tap`, `swipe`, `scroll`, `type`, `key`, `button`, `launch`, `apps` (bundle ids), `screenshot`, `script`, `run`, `scripts`, `batch`, `dnd`, `doctor`, `devices`, `stop`. `iph <command> --help` has the flags; add `--human` to read a result yourself.

## When something is off

- **A reading takes about 20 s once and then things are normal again:** the phone's accessibility service had stopped answering and iph restarted it by itself. Nothing to do. This happens mostly over Wi-Fi.
- **`ax_timeout` keeps coming back:** follow the error's hint. Over Control Center (or the home screen) it says to close it: `iph button home` or `iph launch <app>`, which go out without a reading; Control Center cannot be read at all while the screen is being recorded. Otherwise the phone is most likely locked, its screen is off, or the restart did not help; ask the user to look at the phone, or to lock and unlock it. Do not loop on `iph stop`.
- **`verified: false` with a `note` that the screen could not be read:** a point tap, a swipe or a button went out on the last known screen size without a reading before or after. Read the screen before relying on what it did.
- **`input_failed` or `input_unavailable` come back, or readings take many seconds every time:** stop sending input, because a late reading can show an earlier screen and a tap would then go to the wrong place. Read once more after a moment, and tell the user if it does not clear. Over Wi-Fi everything is slower and less steady than over the cable; if the cable is at hand, suggest plugging it in.
- **The element list looks wrong for what the user describes:** `iph screenshot -o <file>` shows what is really on screen. Banners and system pop-ups are never in the list.
- **The phone is locked:** nothing works until the user unlocks it.
- **The phone stayed in Do Not Disturb after the work:** `iph dnd status` shows whether `iph dnd on` set it; `iph dnd off` puts the earlier Focus back.
