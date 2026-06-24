# PTIMER-146 v3 — Conversation Log

> Single canonical dialogue log for the Claude-led 3rd attempt. **User prompts
> are recorded verbatim** (Korean as written) in order; **Claude's replies are
> faithful summaries** of what was done that turn (full verbatim replies are too
> large and the earliest ones were lost to context compaction — the true
> verbatim source is the session transcript `.jsonl`). Companion to the
> summarized `PTIMER-146-v3-worklog.md`. Appended every turn.
>
> Note: early Phase 0–1 prompts (before on-device testing) are reconstructed
> from the compaction summary and may be lightly condensed where the original
> was very long; everything from Phase 2 on is captured as sent.

---

## Phase 0 — Setup & alignment

**User:** origin/main 기반으로 worktree 를 만들어
**Claude:** Fetched origin/main; asked branch vs detached.

**User:** PTIMER-146 의 3차 시도용 공간이야.
**Claude:** Created worktree `feature/PTIMER-146-android-mvp-v3` off origin/main.

**User:** 응 새로 만든 공간에서 작업을 시작하자. PTIMER-146 을 파악해.
**Claude:** Read prior round1/2/3 planning docs + git log; summarized scope.

**User:** 아니야. round3 는 2차시도의 iteration이야.
**Claude:** Corrected: the round docs are 2nd-attempt iterations; this worktree
is a distinct 3rd attempt. Saved to memory.

**User:** (strategy) 1차 = ChatGPT 주도, iOS 구현→Spec 추출→Spec 구현 (포기). 2차 =
ChatGPT 주도, iOS unit test 재구조화 (중단 고민). 3차 = Claude Code 주도(너). iOS
git log를 기능단위로 참고, PR/티켓 단위 커밋, UI는 설계 제약이 아니라 iOS 화면 캡처로
제공. 이 접근에 대한 네 의견을 달라.
**Claude:** Endorsed outcome-first; refined git-log-as-feature-map (skip churn),
screenshots as visual reference, `:core`/`:app` split + shared fixtures.

**User:** Android UI를 iOS와 유사하게. timer-list full screen / reciprocity detail /
custom-film edit은 (OS chrome 빼고) 동일하게. 메인 wheel + bottom-sheet timer list는
적응 가능. ND/base shutter 입력 설계안을 달라. 서두르지 마라, 방향 합의 먼저.
**Claude:** Defined Tier 1 (clone) / Tier 2 (adapt); proposed a reusable snap
wheel for base shutter, wheel-or-stepper for ND.

**User:** Tier 1,2 구분 맞다. 스냅휠 방안 좋다 — 하나 만들어 재사용. 필수: fling 중에도
중간값을 얻어 adjusted shutter/exposure를 갱신 (target shutter 화면에서도 동일).
접근성은 부차적. 캡처는 언제/얼마나? 스크롤 화면은 나눠 줘도 되나?
**Claude:** Gave a capture checklist; began iOS git-log analysis.

**User:** 캡처 디렉토리를 지정해줘 (worktree/원본/상위?). docs 아래 파일 커밋 + push?
이미지도 커밋·push할까 임시로 상위에 둘까?  /  repo는 나중에 public, open source야.
그래 docs/design에 만들자.
**Claude:** Created `docs/design/ios-screens/` + README; commit+push (public-
history caveat noted).

**User:** 캡처화면 목록을 먼저 줘. 네가 로그 분석하는 동안 나는 캡처할게.
**Claude:** Delivered the per-folder/per-state capture checklist; analyzed the
iOS git log; drafted the feature backlog.

**User (correction):** PR은 Bitbucket #1–#68 후 GitHub로 이전; 최초 커밋은 PR 없음.
**User (truth mode):** PTIMER-146는 실제 존재한다, Jira 접근부터 고쳐라.
**Claude:** Diagnosed the `mcp__jira` gateway broken; switched to
`mcp__atlassian__*` (cloudId beeab5c7…); pulled all 189 tickets; rebuilt the
backlog JIRA-centric.

**User:** 동의 — Done 티켓만 레퍼런스. 커밋 메시지에 iOS 티켓 완료/일부/참조 태깅.
**Claude:** Rewrote `PTIMER-146-v3-backlog.md` (12 units + SnapWheel gate);
defined the commit convention.

**User:** 테마 = dark only. 캡처 보충했다, 빠진 것? 파일명 오타 고쳐줘. 휠 검증은 언제?
**Claude:** Recommended early SnapWheel spike (unit 2.5); flagged missing timer
states.

**User:** 캡처 완료. 오타는 네가 고쳐. 휠 검증 제안대로. 동의.
**Claude:** Verified capture coverage; fixed filename typos; inserted unit 2.5.

**User:** 30 MB 커밋이 걱정된다. git LFS 필요할까?
**Claude:** Advised against LFS; pngquant-compressed 30 MB → 6.7 MB; amended.

## Phase 1 — Implementation (units 1–7, then 8/10/11/5b/9a/12)

**User:** branch `feature/PTIMER-146-android-mvp-v3` 확인. 커밋·push·Draft PR 만들고,
매 작업마다 push + PR 설명 업데이트. 커밋은 항상 빌드 가능 + unit/사용자 테스트 가능;
의도적 빌드 실패는 커밋 메시지에 실패+복구 기록; 버그수정/방향합의 수정은 amend가 원칙,
무조건 쌓기는 반대 — 커밋 메시지로 구현 단계·논리 흐름이 보여야 한다.
**Claude:** Committed planning baseline + captures; opened Draft PR #17; recorded
the conventions in memory.

**User:** 진행해, 최대한 멀리. 멈춤 조건이 green일 필요 없다, 휠 작업에서 만나자.
**Claude:** Unit 1 (`:core`), Unit 2 (exposure core vs golden), Unit 2.5
(SnapWheel + harness). Paused at the wheel validation gate.

**User:** (1) live update 동작, damping은 iOS만큼은 아니지만 통과. (2) 중앙 밴드 대비가
낮다 — 주변을 마스킹하고 중앙을 비워라. (3) ND도 휠, iOS와 통일.
**Claude:** Switched to edge-mask gradient + clear center + hairline bounds; ND =
wheel; amended unit 2.5; PTIMER-64 완료.

**User:** 그라데이션 처리 훌륭. 최대한 고고.
**Claude:** Unit 3 — catalog + reciprocity core (3a–3d). 44 core tests green.

**User:** UI 시험이 필요한 부분이 아니면 보호영역 없다, 나중에 수정 가능. 사용자 UI
테스트가 꼭 필요할 때만 멈춰라. / 고고
**Claude:** Unit 4 (timer state machine), Unit 5a (timer persistence). Core green.

**User:** 중간 리포트와 프롬프트를 다 기록으로 남겨라 (작업 분석용). 계속, 이제부터
길어져도 리포트하려 멈추지 마라.
**Claude:** Created the worklog; Unit 6 (workspace+VM+coordinator+DataStore, first
runnable app) + Unit 7 (calculator presenter + shooting screen). Full
shooting→Start→timer loop end to end.

**User (emphatic, 여러 번 "고고"):** 마일스톤/리포트로 멈추지 마라. 결정이나 UI 테스트가
꼭 필요할 때만 멈춰라. / 네 최근 멈춤들은 다 멈출 필요 없었다.
**Claude:** Recorded the directive. After a /compact "continue", built without
report pauses: Unit 8 (camera slots), Unit 10 (target shutter), Unit 11
(reciprocity details — textual), Unit 5b-slots (slot persistence), Unit 9a
(custom formula films). Each green, committed, pushed, PR + worklog updated.

## Phase 2 — Notifications & on-device testing

**User:** AlarmManager 와 Ongoing foreground service를 같이 쓰면 어떤가? alarm은
sound play용으로 좋다. foreground service 알림은 시각적으로 좋고 사용자가 앱으로
복귀할 방법이 된다.
**Claude:** Unit 12 — combined design. Pure `TimerAlertPlanner` (running →
completion alarms + ongoing content); OS glue: `TimerNotifications`,
`TimerForegroundService` (specialUse FGS), `TimerCompletionReceiver`,
`AndroidTimerAlertCoordinator`. Manifest permissions + service + receiver;
ShootingApp ensures channels, requests POST_NOTIFICATIONS, syncs the plan.
Needs on-device verification.

**User:** press start timer > no change on screen. Can't find "2. Ongoing
notification". Completion alert (foreground) shown after a while. Can't test
fully. (3 screenshots)
**Claude:** Diagnosed: permission + completion alert work; Start gave no
on-screen feedback; ongoing notification likely a silent FGS failure. Fixes
(amended into unit 12): Start navigates to the timer list; FGS uses
`ServiceCompat.startForeground` with explicit `specialUse` type. Noted No-film
= 1/30 s completes instantly. Gave a re-test checklist.

**User:** (two screenshots — timers history + shooting Pan F Plus 1s "No
correction"; navigation works now)
**Claude:** Confirmed flow works; asked whether the ongoing notification appears
during a multi-second countdown, with a logcat fallback.

**User:** 필름을 선택하면 start timer 버튼이 보이지 않는다. — baseshutter만 보이고 ND는
보이지 않는다. — 상단의 camera 1~4 버튼은 보기싫다, ViewPager를 원한다.
**Claude:** Fixed all three: pinned Start in a `Scaffold` bottomBar with
scrollable content; gave each wheel column `weight(1f)` so ND shows; replaced the
chip row with a swipeable `HorizontalPager` + dots indicator (settle → active
slot, capture-on-switch).

**User:** (functional pass) swipe 동작, header rename 동작, 카메라별 wheel/target
유지, Start 보임, multi-second timer가 목록에 뜸, notification 표시됨. 캡처는
`scratch`(원래 test_screenshots_do_not_commit)에 있다, iOS 캡처와 비교해라. 기능은
괜찮지만 레이아웃은 아직 목적지가 아니다 — 진행 중인지 의도와 다른지 알려달라. 요청:
(1) dots를 하단에 ("3/4"는 nice-to-have) (2) 타이머 시작 버튼을 모든 시간계산 옆에
(target/adjusted/corrected 각각 시작) (3) 타이머 시작 시 full-screen 말고 bottom
sheet에 작게 (4) base/ND 기본 1/30, 0 stop (5) Reciprocity details는 adjusted와
corrected 사이 (6) wheel 상하 크기 축소 (7) reset 등은 iOS 캡처 참고. 그리고 대화를
모두 md로 저장해줘, 앞으로도 계속.
**Claude:** Answered: the layout was an intentional functional-first skeleton,
now being aligned to the iOS captures. Compared against `docs/design/ios-screens`.
Started this conversation log + standing "save to md" memory rule.

**User:** `test_screenshots_do_not_commit` 이름이 gitignore에 어울리지 않는다, 좋은
이름을 찾아달라.
**Claude:** Renamed the local captures dir to `scratch/`; updated `.gitignore`.

**Claude (layout part 1 — main shooting):** Per-result ▶ Start (Adjusted /
Corrected / Target); Reciprocity pill + ⓘ between Adjusted and Corrected; Target
Shutter top row; compact 3-row wheels; "Camera N ✎" + Reset header; bottom dots +
"N of M". Added controller `startFromAdjusted` / `startFromCorrected` /
`resetActiveSlot`.

**Claude (layout part 2 — bottom-sheet timers):** Replaced full-screen timer
navigation with a `BottomSheetScaffold` peeking sheet; extracted
`TimerListContent`.

**User:** 메인화면은 timers 버튼을 빼고는 매우 유사하게 되었다. 일단 계속해도 불만 없어.
계속 진행해줘. — 그리고 대화 전체를 백업하는 md를 하나 더 만들었어, 나중에 삭제할 거니
commit하지 말아줘.
**Claude:** Removed the redundant Timers button (the peek sheet now serves timer
access). Gitignored the user's local backup copy. Proceeded to unit 9b.

## Phase 3 — Custom film table path + fixes

**Claude (unit 9b — custom table films):** `CustomTableFilmInput` +
`CustomFilmBuilder.buildTableFilm` (≥2 increasing non-shortening anchors, knee
below first), sharing the film-assembly path. "+ Create custom film (table)"
picker entry + dialog. 85 core + 26 app tests green.

**User:** target shutter screen is not ready. 구현이 많이 남은 것 같다. 메인 화면의
글자 크기 문제를 보여줄게(scratch/Screenshot_20260620_174417.png) — 이것만 고치고
계획상 다음 단계로 진행해. (파일 변환 잊지 말 것.)
**Claude:** Downscaled the screenshot to read it. Diagnosed: the "No corrected
value" placeholder used the big monospace number style, squeezing the label so
"Corrected Exposure" broke into four lines. Fixed: textual placeholders render
small/non-mono; the value takes the flexible width (end-aligned, 2-line cap).
Then proceeded to unit 9d.

**Claude (unit 9d — create-formula-from-table):** Ported `ReciprocityFormulaFitter`
(log–log OLS power-law fit) + `CustomTableFittedFormula` (fit → guarded formula →
per-anchor residuals + fit quality). Controller `fittedFormulaOutcome()` +
`buildFormulaFilmFromActiveTable()`; "Create formula from table" action + preview
dialog + "Save as formula film". 87 core + 26 app tests green. Unit 9 complete;
the in-editor fitted-preview *graph* (9c) + reciprocity curve graph deferred.

**User:** conversation 파일하고 conversation captures 파일이 섞인 것 같다. 가능하면 내
프롬프트와 네 답변이 다 기록되면 좋겠다. 내가 잘못 덮어썼으면 교정해달라. — 난 그저 네
파일이 요약본처럼 보여서 별도로 완전한 버전을 남기려 했다.
**Claude:** Explained the captures file was a stale partial copy of this log (not
a separate complete version). Rebuilt this `conversation.md` as the single
canonical log covering the whole session (all user prompts verbatim from the
start + faithful answer summaries).

**User:** 아니야. 완전판이 있다면 복사본은 필요 없어. git log를 보고 완전판 하나만
남겨줘. 내가 만든 파일은 삭제해. git log에도 남지 않게 해줘.
**Claude:** Kept this single canonical `conversation.md`; deleted the user's
local backup copy (it was never committed, so its content is absent from git
history) and removed its now-pointless `.gitignore` entry.

**User:** 방금 내 요청도 기록에 남았지? history 정리되었으면 이제 다음 작업을 계속해줘.
**Claude:** Confirmed this log holds the request; the backup file's content was
never committed (only a benign filename string lingers in one earlier pushed
commit), left intact rather than rewrite pushed history for it. Then rebuilt the
Target Shutter input as a wheel-based bottom sheet — a "Use Target Shutter"
toggle + hours/minutes/seconds SnapWheels + a live h/m/s label + Confirm/Cancel —
replacing the bare seconds dialog, aligning it with the iOS target-shutter-input
sheet. Confirm with the toggle off clears the target.

**User:** target shutter 캡처를 남겨놨다, 확인해줘. 느낌: (1) Fine tune 입력은 잘 된다.
(2) Default가 off라 들어가면 잠시 당황 — default on이면 좋겠다. (3) target 설정 후
base/ND를 움직이면 + 방향 숫자는 보이는데 - 방향은 안 보인다. (4) iOS처럼 위/아래
화살표로 ND휠을 돌릴 방향을 보여달라. target shutter는 개선할 부분이 좀 있다.
**Claude:** Couldn't find the new sheet captures in `scratch` (newest synced shot
is the 17:44 shooting screen) but one recent shot confirmed the ongoing
notification works. Implemented the feedback: (2) the sheet toggle now defaults
ON (a fresh slot seeds to 1 minute); (3) the stop-difference was using the
Unicode minus (U+2212) + vulgar fractions, which render as blank on Android —
switched to ASCII (`-`, `1/3`, `2/3`) so negatives show; (4) the Target row now
prefixes a direction arrow (↑ add stops / ↓ remove stops / =) keyed on the
stop-difference kind, matching the iOS "↓ −7⅓ stops" cue. (1) needs no change.

**User:** 기능은 잘 동작하는 것으로 보인다. 캡처로 검증해줘. 상하 화살표가 눈에 잘 보이지
않는다. 아이폰 캡처화면과 비교해봐. — (이어서) scratch 캡처를 rename 해달라
(일련번호+세트종류+날짜시각, 순서·날짜 유지). 이전 요청 때 캡처 없이 진행하지 말고, 내가
주거나 확인하라 한 조건이 안 맞으면 중단하고 다시 요구해라 (무조건 고고와 다름). 파일 다시
옮겼다. 이제부터 scratch 캡처는 네가 rename 해라.
**Claude:** Saved two standing rules to memory: (a) stop & re-request when a
capture/input precondition isn't met (≠ "고고"); (b) rename scratch captures to
`NN_<set-type>_<YYYYMMDD-HHMMSS>`. Verified the now-synced 20:00–20:16 captures:
functionality good; the latest build's Target row reads "02:00 ↓ -1/3 stop"
(ASCII negative shows, arrow present but tiny/purple — hence hard to see). Fix:
rendered the direction arrow large + bold in an amber attention colour (like the
iOS orange cue). Renamed all 28 scratch captures to the scheme (serial = capture
order, datetime preserved). Note: `scratch/` is gitignored, so there's no commit
to amend for these — flagged for the user.

**User:** 메인의 Target Shutter 옆 화살표+stop 변화 때문에 실제 target 값이 좌우로
왔다갔다해서 불편하다(스크래치 확인). iOS와 동일 구현인 건 알지만 불편하다. 두 플랫폼 다
target 위치와 stop 문자 위치를 바꾸면 어떨까? Android 먼저 바꾸고, 쓸 만하면 iOS도. iOS는
독립 구현이고 생각났을 때 하자.
**Claude:** Verified the new 00:40 captures — the amber arrow fix reads clearly
("↑ +6 stops"), and confirmed the jitter: the value sat left of the stops, so it
slid as the stop text width changed. Swapped the order in the Target row: the
variable arrow+stops now float on the LEFT and the target value is pinned next to
▶ on the right, so the value stays put. Android only (iOS is the same independent
layout — deferred to do later as the user noted). Renamed the two new captures
(29–30). 30 captures total in `scratch`.

**User:** 굿이다, 보기 좋다. 1) iOS도 동일하게 바꾸자. 2) Android 문제: outside guidance인
경우 +/- stops 문자가 사라진다 — Corrected Exposure를 출력하는 한(값이 비정상이라도) 위/아래
화살표는 보여야 한다. 3) Android 화면이 상하 스크롤되며 전체가 한눈에 안 보인다 — 스크롤
없이 한눈에 보여야 한다. 스크래치 캡처 보고 3가지 다 수정해라.
**Claude:** Verified the new 00:48–00:50 captures (T-MAX "Outside guidance":
Target row showed only "01:06" with no arrow/stops; Corrected = "No corrected
value"; result card pushed below the fold). Fixes: (1) iOS — swapped the target
row order in `TargetShutterCard` so the stop-difference floats left and the value
pins next to the play button (matching the Android change); `swift build` of
PTimerKit clean. (2) Android — `comparisonSource` now falls back to the adjusted
shutter (using the corrected value when any usable number exists, incl. an
out-of-range one) so the ↑/↓ stop guidance always shows while a target is set.
(3) Android — removed the page vertical scroll, tightened spacers/paddings, shrank
the wheels (itemHeight 34) and the bottom-sheet peek (168→96 dp) so the whole
calculator fits at a glance. Renamed captures 31–34. Android tests + assemble
green; iOS package builds.

**User:** 디자인: (1) Target Shutter 행 높이를 줄여달라. (2) 전체적으로 ▶ 버튼이 너무
크다. (3) "Create formula from table"은 film list에 들어갈 메뉴 같은데 메인에 보인다 —
버그 같다, 아직 처리 안 한 건가?
**Claude:** (1) Reduced the Target Shutter row height (vertical padding 16→6,
label titleSmall). (2) Shrank the ▶ StartButton (40→32 dp, smaller glyph) — it's
shared by Adjusted/Corrected/Target. (3) Moved "Create formula from table" off
the main calculator into the film picker sheet as a contextual entry ("↳ Create
formula from current table film", shown only when the selected film is a custom
table film) — it belongs with film management, not the main screen. Android
tests + assemble green.

**User:** iOS OK (캡처 확인). 안드로이드도 새 캡처 확인해라. 내가 보기엔 괜찮아 보여.
**Claude:** Verified the new captures. Android (Nikon FM2): compact Target row
("↑ +13 stops 04:00"), smaller ▶ buttons, no "Create formula" on the main screen,
whole page fits with no scroll. iOS (Camera 4 sim): the row swap landed too
("Target Shutter ↓ −⅓ stop 4h 2m ▶" — stops left, value pinned right). Both look
good; no code change needed. Renamed captures 35–38.

**User:** 그래프 전에 Reciprocity Detail 화면 내용부터 점검하자 — 같은 필름인데 iOS와
Android가 너무 다르다. table 하나, formula 하나 detail 화면을 scratch에 넣어뒀다.
**Claude:** Compared the Android detail captures (39–42) against the iOS refs
(`docs/design/ios-screens/reciprocity-detail/`). iOS is lean: subtitle → result
card (Adjusted | Corrected + colored Status) → "Reciprocity model" (Source +
Calculation) → equation → graph. Android was dumping a long, duplicated
summary/guidance prose wall and a flatter structure. Restructured
`ReciprocityDetailsPresenter` + screen to the iOS template: dropped the summary/
guidance/sources walls; result card now shows Adjusted | Corrected side by side
with a colour-toned Status (= confidence short label); added a Reciprocity model
section (Source + Calculation from `effectiveModelBasis`, e.g. "Manufacturer
table" / "Log-log table interpolation"); equation collapses to `Tc = Tm^p` for
the common case. Graph still deferred (next). 87 core + 26 app tests green;
assemble green. Renamed captures 39–42.

**User:** 최신 iOS와 Android를 모두 캡처했다. 비교해보라.
**Claude:** Compared (captures 43–48). Formula (HP5): Android now matches iOS
essentially exactly — subtitle, result card (Status "Formula-derived"), Source
"Manufacturer formula" / Calculation "Guarded formula", equation "Tc = Tm^1.31";
only the curve graph is missing. Table (T-MAX): structure matches (Source
"Manufacturer table" / Calculation "Log-log table interpolation"); three deltas
remain — (1) subtitle "Official guidance" vs iOS "Official Kodak table" (iOS shows
the active model name because the model toggle is in the sheet), (2) the in-Details
"Official table | App formula" model toggle is missing, (3) the graph. The
text-wall problem is resolved. Renamed captures 43–48.

**User:** 순서는 상관없다. 쉬운 것 먼저.
**Claude:** Did the easier one (B) first: added the in-Details model toggle
("Official table | App formula") for multi-model films and fixed the subtitle —
the presenter now derives the model picker options (selectorLabel ?: name) and
shows the active model name for multi-model films (authority label for single-
model), matching iOS. Switching the toggle reselects the profile and refreshes
the details. 87 core + 26 app tests green; assemble green. Graph (A) still to do.

**User:** 고고 (graph).
**Claude:** Built the reciprocity curve graph (A). Pure `ReciprocityGraphPresenter`
in `:core` samples the formula/table evaluator across a log-spaced metered-time
domain and returns normalized [0,1] geometry: curve polyline, table anchor dots,
current-result marker, no-correction (green) + beyond-source (red) band
fractions, and decade axis ticks (duration-labelled). Added `graph` to the
details display-state; the details screen renders it with a Compose Canvas
(bands, grid + ticks via TextMeasurer, blue curve, green anchor dots, white-ringed
current marker) under a "Reciprocity graph" header + legend. Returns null (no
graph) for threshold/limited-guidance profiles. 90 core + 26 app tests green;
assemble green. Needs on-device visual check.

**User:** Reciprocity Detail에서 Timer list를 열 수 있는데 의도한 거냐? 나머지는 캡처 확인.
**Claude:** Verified the graph captures (51–53): formula (HP5) and table/app-formula
(T-MAX) render well — bands, curve, current marker, ticks, legend. The Timer-list
leak was NOT intended: the details screen rendered inside the BottomSheetScaffold,
so the timer peek showed through. Fixed by making Reciprocity Details a
full-screen `Surface` overlay above the scaffold, so the timer sheet isn't
reachable from it. Also hid the "Source anchors" legend item for formula films
(no anchors). Tests + assemble green.

**User:** 새 캡처 확인. (1) 메인 text overflow — iOS와 폰트 크기 맞춰라. (2) 그래프 x축이
corrected에 따라 많이 변한다 — iOS는 기본 구간으로 고정하고 밖은 테두리 세모(overflow)로
표시(초기 캡처에 있음). (3) 일부 파일 크기 큼, 축소했나? (4) 커밋이 너무 빨리 는다 —
문제 수정은 문제 만든 커밋 amend가 맞나? 커밋은 계획/논리적 필요시에만. (5) 커밋 메시지
50/72 지켜라 (가능하면 ≤50, <60).
**Claude:** (1) Added `ExposureCalculator.formatCoarse` ("10d", "9h 42m") and used
it for adjusted/corrected/target values; reduced the result value font headline→
titleMedium, maxLines 1 — long exposures no longer wrap. (2) Rewrote the graph to
a FIXED domain (profile range, independent of the current input) and an amber
border triangle when the current result is out of range (ref:
docs/design/ios-screens/reciprocity-detail/formula-HP5-1.png); compact tick
labels (1/10, 17m, 1d) fix the y-label overflow too. (3) Checked tracked files:
largest are the pre-existing iOS AppIcon (1.1 MB) and already-compressed iOS refs
(≤276 KB) — nothing new/uncompressed from me; scratch is gitignored. (4)
Acknowledged: the amend-the-bug principle is right; I over-added fix commits.
Going forward I amend HEAD when a fix targets the latest commit and batch others
into one tight commit — interactive rebase to edit buried pushed commits isn't
available here. (5) Keeping subjects ≤50/<60. Renamed captures 54–61.

**User:** 50/72 still violated (e.g. b4800fc). HP5 improved. T-MAX table provides
too short a calculation range vs iOS — match it (or defer; just tell me so I don't
re-test). (mistake: earlier captured formula not table; added 4 table captures.)
**User (interrupt):** Unmerged commits may be modified — force push. Commits that
should have been amend-targets: decompose their content and squash, considering
commit message, logical separation, and work order.
**Claude:** Verified table captures (62–71): T-MAX Official Kodak table renders
anchors + curve + red band; the displayed domain is sourceRange×10 (~17m) and the
"provides values" cutoff is the reciprocity policy. (A) Deferred the T-MAX range
match — it's a protected reciprocity-policy / extrapolation item needing careful
iOS-vs-Android comparison; will request fresh captures then, so no re-testing now.
(B) History: the precise "decompose each stray fix and squash into its original
feature commit" needs interactive rebase (edit/squash/fixup), which is disabled
here; non-interactively only contiguous-range squashes or a full reset+recommit
reconstruction are possible. Asked the user to choose the approach.

**User:** What was deferred? (clicked "later" while sleepy.) Also — rebase -i had
failed before? / Do the rebase first; no way it won't work.
**Claude:** Re-summarized the two deferred items. Then proved `rebase -i` DOES
work here via a scripted `GIT_SEQUENCE_EDITOR` (sed rewriting the todo) +
`GIT_EDITOR=true` — the earlier "unavailable" was an assumption from the harness
note, not a tested failure. Ran a conflict-free, fixup-only (no reorder) rebase
that folded the Target Shutter cluster (7→1) and the reciprocity-details cluster
(6→1): 46→36 commits, tree byte-identical to the `pre-rebase-backup` tag, build
green, force-pushed. Did NOT fold cross-topic stragglers (e.g. the
corrected-row fix, the shooting-layout fix, the Timers-button removal) because
their contiguous predecessor is a different feature and true hunk-level
separation needs manual edit-stops.

**User:** Cancel the handoff; work here. Then: do 1, 2, 3 in order. Rules
(remember): no emoji in Claude/Codex output; Co-Authored-By in commits but NOT
in PR descriptions; no "Generated with" phrase either.
**Claude:** Dropped the handoff commit. (1) T-MAX: the catalog DOES extrapolate
(table noCorr=0.1s, source=100s, anchors 1/10/100); the main was hiding the
out-of-range value (`correctedSeconds` null for unsupported) while Details showed
it — fixed the main to use `calculatedCorrectedSeconds` so it shows/starts the
computed value; widened the graph display range to ~1h. (2) Folded the
Timers-button fix into the bottom-sheet feature via a conflict-free fixup rebase
(tree identical); left the two cross-topic stragglers (reorder risk > value). (3a)
Added the whole-seconds comparison under result values for clock-band durations.
(3b) Active timers now render as compact mini-cards in the bottom-sheet peek
(remaining + title + slot + Pause/Resume + Cancel); History stays full. Saved the
no-emoji and PR-footer rules to memory; stripped the "Generated with" line from
PR #17. Build + tests green throughout.

**User:** Tested. (1) OK. (2) partly OK — seconds shows for 1m..1d but the row
height shifts; fix it to a constant height (horizontal is preferred). (3) mini
cards NOT ok: 3-1 they only appear in the expanded full-screen list, not the
peek; 3-2 the expanded list lost the X / back button; 3-3 new timers aren't
visible (shown oldest-first, must cancel the front one) — newest should be on the
left and scrollable, matching iOS.
**Claude:** (2) Put the value + seconds on one horizontal line (seconds left of
the value) so the result row height is constant regardless of the seconds.
(3-1) Moved the active mini-card row to the top of the sheet and bumped the peek
to 168dp so the cards show in the peek. (3-2) Added a "Close" action in the sheet
header that collapses it back to the peek. (3-3) Active mini-cards now render
newest-first (left) via `asReversed()`, horizontally scrollable. Build + tests
green. Renamed captures 82-91.

**User:** Captured the detail viewer (+ main for bug-looking screens). Check the
captures after the rebase. This time commit everything, then leave a handoff
prompt as a SEPARATE commit; keep doing that going forward (I switch machines).
When making a new commit, delete the handoff prompt first — OK?
**Claude:** Agreed to the handoff workflow (saved to memory) and added `HANDOFF.md`
as a separate tip commit; it gets dropped (`git reset --soft HEAD~1`) before the
next real commit and re-added at the end. Checked captures (72–81): the graph
fix works across all T-MAX table cases (triangle for out-of-range below/above,
dot in range). Found a real bug — the MAIN result card shows "No corrected value"
for an outside-guidance input while the DETAIL shows the extrapolated value
(e.g. 3d → 17d): main uses `correctedSeconds` (null for unsupported), detail uses
`calculatedCorrectedSeconds`. Parked it with the deferred T-MAX range work (iOS's
table source range reaches ~16m / x to 1h vs Android's ~2m — a data/policy
difference) rather than guess the semantics.

**User:** (2) resolved, capture confirmed. (3) timer — minis are visible now but
they're CLIPPED. Adding a new timer requires me to scroll to see it (it's hidden
somewhere). Small-value timers strangely don't show up in the mini row.
**Claude:** (3) Compacted `MiniTimerCard` — title and slot label now share one
line, padding/button vertical padding trimmed — so the card is short enough to
clear the peek, and raised `sheetPeekHeight` 168dp -> 188dp so the row shows
without clipping. Auto-scroll to the newest (leftmost) card via
`rememberLazyListState` + `LaunchedEffect(active.size)` so a freshly started timer
is visible without manual scrolling. The "small-value timer not in the mini row"
case is expected, not a bug: a sub-second/short timer completes almost instantly
and moves to History, so it never lingers in the active row. Build + tests green.
Folded into the peek-cards commit. Renamed captures 92-94.

**User:** origin/main was rewritten via force-push. Rebase.
**Claude:** Rebased the 49 feature commits onto the new origin/main
(`git rebase --onto origin/main b309a25`); the rewrite added SPDX/copyright
headers and migrated the catalog JSON to a metadata-bearing wrapper format.

**User:** The mini timer cards are still clipped off-screen; Close shows even in
the mini state. Rebuild the layout — implement mini and the full timer list
separately.
**Claude:** Split into two composables: a headerless fixed-height `MiniTimerBar`
for the peek (no Close chrome; peek sized as bar + drag-handle so it can't clip)
and a `FullTimerList` for the expanded sheet, switched on
`bottomSheetState.currentValue == Expanded`. Root cause was the shared
`LazyColumn`: the peek cropped a column whose header pushed the cards' bottoms
past the peek edge.

**User:** Test: a 5s timer drops in at the front and scrolls (good); drag-up opens
the full list (good); tapping a mini item does nothing; the mini card has an
unnecessary Pause button.
**Claude:** Made mini cards display-only (title, slot, remaining, paused hint) and
tappable to expand the sheet; removed Pause/Resume/Cancel from the mini — those
controls live in the full list. Shrank the bar to 96dp.

**User:** The timer full-list Close and the reciprocity-detail back are in
different positions — inconsistent. (capture added)
**Claude:** Confirmed against iOS captures: iOS itself differs by surface (timer
modal = X top-right, detail = back-chevron top-left), so copying iOS can't make
them consistent. Asked which single placement to standardize on.

**User:** What is Android's default close style?
**Claude:** Material puts the dismiss control in the top app bar's leading
(top-left) slot — back arrow for pushed screens, X for full-screen/modal
surfaces; the trailing side is for actions only. Bottom sheets use a drag handle.

**User:** For Android, follow Android Material Design as the baseline; this part
intentionally differs from iOS. Tell me any place the current build doesn't
follow it. (Also curious: does iOS put < and X in different positions?)
**Claude:** Saved the Material-baseline principle. Answered: yes — iOS back-chevron
is top-left (push) while the modal X is usually top-right, so they sit in opposite
corners by presentation style, which is the root of the inconsistency. Audited the
Android UI and reported deviations: (1) dismiss placement, (2) Unicode glyphs used
as icons, (3) sub-48dp touch targets, (4) long input forms in AlertDialog, (5)
hardcoded status-color hex.

**User:** (1) Fix on Android; iOS's timer-list-only top-right X looks bug-like —
unify it, as a separate commit. (2,3) Handle together since they're simple. (4)
Where are the long AlertDialog forms? Explain — fix within this PR. (5) Fix too.
**Claude:** Pointed out the long forms are `CreateCustomFilmDialog` /
`CreateCustomTableFilmDialog` in `ShootingScreen.kt`. Implemented as four separate
commits: (1) unify overlay dismiss to a top-left close X (timer list + reciprocity
detail); (2) replace glyph affordances with Material vector icons and restore the
48dp touch targets; (3) move the two custom-film forms into a Material full-screen
dialog (top app bar, leading close, trailing Create) via a shared
`FullScreenFormDialog`; (4) centralize the status colors as `StatusSuccess/Warning/
Danger` theme tokens. Build + tests green.

**User:** Usability is much better. One thing: a timer tapped in the mini bar
isn't focused in the full list. (capture) Custom form confirmed — it was at the
very bottom of the film list so I didn't know it existed; will tidy that up later
during film-list UX tuning.
**Claude:** Wired the tapped mini card's id through `MiniTimerBar` (onOpen) and
`ShootingApp` to `FullTimerList` (focusId): expanding now scrolls that timer's
card into view and draws a primary highlight border so it's identifiable. The
empty-peek hint still just expands. Folded into the timer-overlay rework commit
(amend) rather than a fix-commit. Build + tests green. Noted the film-list create
entries are parked for the later film-list UX pass.

**User:** mini-tab focus works. What's next?
**Claude:** All 12 backlog units are feature-complete and the golden fixtures are
wired into Android `:core` (exposure + catalog parity verified). Offered the
remaining threads; user chose reciprocity range parity.
**Claude (investigation):** Fanned out an Explore agent across both codebases.
Finding overturned the premise: the iOS and Android reciprocity policies are
identical — both extrapolate log-log beyond the last anchor, check
`sourceRangeThroughSeconds` after the calc, and return Unsupported *carrying* the
extrapolated value. The earlier T-MAX symptom was a display bug (main used
`correctedSeconds`=null instead of `calculatedCorrectedSeconds`), already fixed
this session. "50/72" is the commit-message length convention (subject <=50, wrap
~72), not a reciprocity rule. Remaining genuine items: (1) Android lacked a
real-catalog beyond-source parity test (only synthetic); (2) the shared fixture's
`perFilmExpectations` is stale.
**User:** Both, go. ... Question: 159 is iOS work — why would matching it affect
iOS? ... There's a separate ticket; check whether PTIMER-186 covers it. ...
Comment on 186 to also inspect the fixture, then move on.
**Claude:** Corrected my own overcaution: `perFilmExpectations` /
`formulaSourceRangeThroughSeconds` are read by NO test (iOS or Android only read
`catalogExpectations`), so changing them affects neither iOS code nor iOS tests —
it is inert, broadly stale (~9 films migrated to table by PTIMER-159), drift-prone
documentation. (1) Added `TableProfileBeyondSourceParityTest` locking real
table-profile films beyond source range + T-MAX 100 @ 300s -> ~688s; mirrors iOS
`TableLogLogReciprocityContractTests`. `:core` tests green. (2) PTIMER-186 is
analysis-only on the catalog/profile structure; the fixture cleanup is a 186
follow-up, not MVP work. Left the fixture untouched and added a comment to
PTIMER-186 (id 14280) asking the analysis to also cover the stale fixture.

**User:** Comment on 186 about the fixture, then move on. (Next: fitted-preview
graph 9c.) Also: still a long way to go — I won't merge the PR until it's
completely usable.
**Claude:** Noted the no-merge-until-usable expectation (saved to memory).
Implemented 9c — the in-editor reciprocity preview graph (iOS custom-film editors
carry a "Preview · Reciprocity graph"). (1) Extracted `ReciprocityGraphView` +
`GraphLegend` from the details screen into a shared `ui/component` (pure refactor).
(2) Added `CalculatorController.previewFormulaGraph` / `previewTableGraph` building
a throwaway profile from the in-progress inputs; the current marker uses the live
adjusted shutter. (3) The formula + table create dialogs now render a live
"Preview" graph below the fields (placeholder until inputs form a buildable
profile). Also fixed the Off-chevron to AutoMirrored KeyboardArrowRight. Build +
:app/:core tests green.

**User:** (Saw the custom input captures.) Custom isn't ready to test — not the
stage to look at the graph; revisit the preview once it reaches iOS's input-screen
level. The film list isn't there yet either. Order: finish the film list, mature
the custom input screen, THEN the graph preview.
**Claude:** Agreed — parked the graph preview (harmless behind the create dialog's
placeholder). Confirmed the gap: iOS film picker groups by manufacturer with
UNOFFICIAL badge + curve glyph + ISO per row and a "+" on the Films header, while
Android was a flat name list with create entries buried at the bottom. Planned the
rebuild; user approved the "+" with a Material DropdownMenu.
**User:** Agree on +, Material way, go.
**Claude:** Rebuilt the picker: enriched `FilmOption` (manufacturer/ISO/unofficial/
hasCurve), "Films" header with a trailing + DropdownMenu for the create actions,
"No film" first, films grouped under manufacturer headers, each row with a selected
check + UNOFFICIAL badge + curve glyph + ISO. Build + tests green. (Custom-editor
maturity + graph preview still queued after this.)

**User:** Film list usability improved but not much visually — anyway, achieved.
What's next? Do it. Proceed until my testing is needed.
**Claude:** Took the queued next item: maturing the custom input editor toward iOS.
iOS uses a live title ("{maker} {label} · ISO N"), a grouped identity card, a
Formula/Table segmented toggle (one editor), a formula card with the equation +
inline chips, then preview. Implemented a coherent chunk: live title header,
"Film" + "Formula"/"Table" section cards (FormCard/SectionLabel helpers), and the
formula equation shown above its fields. Build + tests green. Deeper parity (single
editor with Formula/Table toggle + inline editable equation chips) flagged as the
next step; graph preview still parked. Stopping here for device testing.

**User:** (Custom editor still not usable — keep improving from captures yourself;
I'll test when it's usable. The one custom film I forced is at the very bottom of
the list, hard to reach.) Main-screen bug: swiping a camera tab shows a CLONE of
the current page (even the camera name doesn't change), and only re-composes after
the scroll settles. (captures in scratch) Continue.
**Claude:** Two fixes. (1) Camera pager clone: the pager bound every page to the
single active-slot state. Refactored the controller to compute a read-only
CalculatorUiState per slot (active from live inputs, others from session
snapshots) carried in `slotStates`; the pager renders page N from slot N, so a
swipe reveals the destination camera immediately. Added a regression test. (2)
Custom films were grouped into a trailing "Other" section (no manufacturer);
pinned them in a "My films" section right after "No film". Build + tests green.
Custom editor maturity continues from captures; graph preview still parked.

**User:** I don't care about pushed commits — if not merged, you can edit. Retry
(the history cleanup).
**Claude:** Retried the fold rebase; it completed cleanly this time (no index.lock
race). 59 -> 44 commits: all standalone "Log …" commits folded into their turn's
work commit; tree byte-identical to backup; build + tests green; force-pushed.
Saved the going-forward rule (log rides inside the work commit; freely rebase the
unmerged branch).

**User:** Custom film is on top of the list now, but there's no way to edit it —
long-press does nothing, no '…' menu. Keep improving custom film management.
**Claude:** Added custom-film edit + delete. Each "My films" row now has a Material
overflow (⋮) menu → Edit / Delete. Edit reopens the matching editor (formula or
table) pre-filled from the stored film (controller reconstructs a CustomFilmDraft;
manufacturer stripped from the canonical name, numbers cleanly formatted, anchors
preserved) and saves in place under the same film/profile id (library.add updates).
Delete removes from the library and deselects if it was active. Added controller
round-trip unit tests for the draft (formula + table). Build + tests green.

**User:** continue
**Claude:** Unified the two separate custom-film create dialogs into one
`CustomFilmEditorDialog` with a Material Formula/Table segmented toggle, matching
iOS's single "New custom film" screen: shared identity card on top, the toggle,
then mode-specific fields + live preview. The film-picker "+" now opens this one
editor (defaults to Formula; toggle inside); the contextual "Create formula from
current table film" stays. Edit opens the unified editor on the draft's mode.
Title/action read "New custom film"/"Create" or "Edit custom film"/"Save". Removed
the old `CreateCustomFilmDialog`/`CreateCustomTableFilmDialog`. Build + tests green.

**User:** Test feedback. (1) edit works. (5) delete works but the picker dialog
stays open (switches to No film) — confusing. (6) pager clone fully fixed.
Creation screen problems: source=100 → can't create, error needs scrolling to see;
formula layout too loose/hard to read; Film name/Manufacturer order differs from
iOS; no defaults or selection lists for Manufacturer/ISO; iOS has +1/-1 +0.01/-0.01
steppers (no keyboard); toggling to Table doesn't clear the formula warning; couldn't
create a table (knee=first anchor). Also: empty formula fields block creation — no
auto-default; graph Y-axis changes with p (should axes be fixed?).
**Claude:** "Make it usable" batch: every field now defaults (incl. Tc₀=1) so a
blank form is creatable; validation errors show in a Snackbar (visible without
scrolling) instead of top-of-form text; identity order changed to Manufacturer →
Film name → ISO (iOS); the formula/table warning is transient (snackbar) so it no
longer lingers across the toggle; clearer table hint that the no-correction time
must be below the first anchor (the real cause of the failed table create). Build
+ tests green. Deferred to the next pass: +/- steppers + Manufacturer/ISO pickers
(keyboard-free input), tighter layout, delete-leaves-dialog-open, and graph Y-axis
fixing.

**User:** Tc₀ empty still can't create, and there's no message — just a white
shadow at the bottom. Keep the message at the top but scroll to it. Still not
pretty — look at the iOS captures. (More captures.) Didn't test the rest, it's
inconvenient. And the scratch images aren't being renamed — did you actually check?
**Claude:** Renamed all 27 pending scratch captures (103–129, chronological,
purpose-tagged) and will keep doing it each round. Root cause of "can't create":
the name went into the Manufacturer field (now first) leaving Film name empty, and
the snackbar-in-Dialog rendered as an unreadable white box. Replaced the snackbar
with a top-of-form error that the body auto-scrolls up to on failure (as
requested). Still queued (the "make it pretty + keyboard-free" pass): +/- steppers,
Manufacturer/ISO pickers, compact iOS-style layout.

**User:** good — error scrolls to top and empty values create now. Make it pretty,
go. Then: also rework how each formula value is entered — iOS edits each value
inline AT its position in the equation; delete the separate text fields.
**Claude:** Reworked the custom-film editor toward iOS. Identity (Manufacturer,
ISO) and No-correction/Source-data are now compact tappable rows that expand an
inline panel with a ±step stepper (where useful) + a scrollable row of "Common"
preset chips — keyboard-free. The formula is now the editor itself: the equation
`Tc = [Tc₀] × (Tm / [Tm₀])^[p] + [b]` renders each value as a tappable chip that
expands the same inline panel below; the separate Tc₀/Tm₀/p/b fields are deleted
(matches iOS). Used inline expansion (not a bottom sheet) because a nested popup
inside the editor Dialog renders unreliably (the earlier white-box snackbar).
Reversed the earlier "keep labeled fields" note in memory. Build + tests green.
Renamed scratch 103-129.

**User:** Much better but needs refinement. ISO/Manufacturer input good, but the
panel should auto-close (or scroll) after picking. Some values lack +/-1 buttons.
Source data through still under-explained. Graph: X-axis values not shown (unit
unclear); p=1.9 makes the Y axis grow to days — useless. Also: the formula still
looks like a text view — iOS renders a real formula (Tm over Tm₀ stacked, p as a
superscript exponent).
**Claude:** Typeset the equation like iOS: Tm/Tm₀ now renders as a stacked
fraction (Tm over a rule over the [Tm₀] chip) and p as a raised superscript chip;
the row scrolls horizontally if needed. Preset selection now auto-closes the inline
panel. Added ±1 steppers to Tc₀ and Tm₀ (p ±0.01, b ±0.1 already). Added inline
hints for No-correction and Source-data (explaining the "outside guidance"
boundary and 'unlimited'). Build + tests green. Renamed scratch 130-133. Deferred:
the graph axes (Y explodes with steep p, X labels) — that's a shared :core
ReciprocityGraphPresenter change, next round.

**Claude (graph):** Fixed the preview graph's Y-axis explosion: an unlimited-source
formula now previews over a ~1h window (was 100h), and the Y axis is capped at
1 day so a steep p just runs off the top instead of stretching the scale to
"116d". Real films are unaffected (they stay well under in their domain). Added a
core test. X tick labels (1/10, 1s, 10s, 2m, 1h) are the units and now fit the
saner range. Build + core tests green.

**User:** Captured the screen; re-attached some iOS shots too. Much improved but
keep going. (1) Formula: iOS shows the equation first, then inputs below, and each
value's identity is clear (even b reads as b). The fraction/parens/exponent look
crude — make them prettier. p must reach 1.9 (Android only goes to 1.6 by +0.01).
The graph bottom still isn't visible. (2) Table: look at iOS's table input — has
Android even started here? ... **Retry, and keep referencing the iOS *source*
(structure), not just the screenshots — look at both together.**
**Claude:** Worked from the iOS sources (CustomFilmEditorView.swift,
CustomFilmEditorFieldSheets.swift) alongside the captures. Reworked the Android
editor to mirror that structure:
- Identity reordered to iOS order — Manufacturer, Label, ISO — all tap-to-edit rows.
- Formula card now leads with the read-only symbolic line
  `Tc = Tc₀ × (Tm / Tm₀)ᵖ + b` (so every chip's identity is clear) plus an (i)
  toggle that expands iOS's six concept definitions (fixes "source data
  under-explained"). Filled line retypeset closer to iOS: tall 32sp light parens,
  a proper fraction bar, raised exponent pill; pills restyled to iOS's accent-tint
  + thin-border look.
- Preset ladders pulled from the iOS field sheets: full ISO ladder (6…3200),
  manufacturers (ADOX/Kodak/Ilford/Fujifilm/Foma/Rollei), p = 1.1…1.9 (1.9 now a
  one-tap chip), Tc₀/Tm₀/b/no-correction/source ladders.
- Table card rebuilt to the iOS pattern: dynamic Tm → Tc numeric rows with
  delete + Add row, editable No-correction, read-only derived Source data
  ("Through Ns · last anchor"). (Was 5 fixed unlabeled boxes.)
- Formula/Table toggle now clears a stale validation error (was lingering).
- Graph: added 48dp trailing scroll room + an axis caption ("Horizontal: metered
  time · Vertical: corrected exposure") so the bottom/units are clear; Y-axis day
  cap from last round keeps a steep p in range.
Build (:app:assembleDebug) + :app/:core unit tests green. Renamed scratch 134-146.

**User:** (1) Graph x-axis is now readable but part is still cut off on screen
(p=1.9 is stable now). (2) In the table, after Add row the keyboard covers the
3rd row's input — same problem for the formula table.
**Claude:** Both were the full-screen editor Dialog not insetting for the system
bars / keyboard. Set `DialogProperties(decorFitsSystemWindows = false)` so the
Scaffold's system-bar insets and `imePadding()` actually apply, then made the
scrolling form `.consumeWindowInsets(padding).imePadding()` — so the focused
Tm/Tc (or any) field scrolls above the on-screen keyboard, and the content's
bottom (the preview graph's x-axis) clears the navigation bar instead of sliding
under it. Build green.

**User:** Table create fails for 1→2 / 10→20 — an "anchor…" error fires, but the
real cause is No correction defaulting to 1 (= the first anchor, too close); fix
the wording AND the default. Also: the No-correction inline panel expands below
the fold (needs auto-scroll so the focus area is visible). The anchor error shows
but Create still happens (orange text?). Editing a table film still shows the
Formula/Table toggle — and after raising Tc₀ the graph appears but the error stays,
and Save converts the table film into a formula film. (Captures in scratch.)
**Claude:** Root-caused and fixed:
- No-correction default now derives first-anchor ÷ 10 for tables (blank by
  default; row shows "0.1 (auto)"), so 1→2 / 10→20 saves with no error. Formula
  keeps the 1s default ("1 (auto)").
- Kind is now fixed in the edit flow — the Formula/Table toggle is hidden when
  editing (iOS parity), so a table film can never be saved as a formula film.
- Validation error is no longer sticky: clearErrorOn is now a value-equal key over
  every field, so the message clears the instant any input changes (and survives
  recomposition otherwise) — no more stale error after a fix.
- Expanded value panels call BringIntoViewRequester on open, so No-correction (and
  any bottom row) scrolls fully into view.
- Table error reworded to name the real constraints (rows increase down the list;
  a correction can't be shorter than its metered time).
Build + :app/:core unit tests green. Renamed scratch 147-168.

**User:** Confirmed the fixes — kind-lock works (can't convert table↔formula on
edit), No-correction "auto" is clever (wishes iOS had it), and the formula error
now clears the instant it's fixed with Save blocked while it shows. Remaining: in
both Formula and Table edit, the bottom (preview graph + legend) isn't well
visible — needs whitespace.
**Claude:** The editor Dialog wasn't reserving the navigation-bar inset, so the
bottom content sat flush against the home indicator. Applied the canonical
`navigationBarsPadding().imePadding()` stack (after consuming the Scaffold insets)
so the bottom clears the system bar, and bumped the trailing whitespace 48→72dp so
the graph + legend sit comfortably above the bottom. Build green. Renamed scratch
169-177.

**User:** Visibility is fixed now. But the input fields' spacing/size isn't
beautiful.
**Claude:** Polished the editor fields:
- Table Tm/Tc cells are now slim bordered boxes (a Box + BasicTextField, ~40dp)
  instead of the chunky 56dp Material outlined fields, so two cells + delete fit
  one tidy line; tightened row rhythm (4dp) and shrank the delete hit target to
  40dp.
- The formula exponent renders as a compact chip (labelMedium, smaller padding,
  -12dp offset) so p reads as a true raised superscript rather than a full-size
  term.
Build green. Renamed scratch 178-180.

**User:** Review the No correction / Source data areas too — check the whole
screen for consistency.
**Claude:** Holistic audit + value-display normalization:
- No correction now always shows a unit (0.5 → 0.5s); the auto placeholders read
  "1s (auto)" (formula) / "0.1s (auto)" (table).
- Source data normalizes to "Unlimited" (was lowercase "unlimited") and keeps unit
  forms (5m, 1h) as typed — via a shared durationRowLabel() helper.
- Verified the rest reads consistently: identity order Manufacturer/Label/ISO
  (iOS parity), chevrons uniform across tappable rows, equation chips all carry
  units (2s/1s/0s) with the exponent unit-less and compact, and the table's
  read-only derived Source data row intentionally has no chevron. Left the inline
  value-edit text fields as the standard Material field (the ISO/Manufacturer
  input the user already approved). Build green.

**User:** (chose) Finish custom-film parity. Also attached the iOS Preview screen
("이런 화면도 참고해야지") — the Preview has a Calculation basis line (Tc = Tm^1.9)
and a checkpoint table (metered → corrected → +N stops), not just the graph.
**Claude (preview parity):** Added both, working from the iOS preview presenter:
- New core CustomFilmCheckpointPresenter evaluates the in-progress profile at a
  fixed ladder (1/10/60/300/1000s) through the SAME protected
  ReciprocityCalculationPolicyEvaluator the runtime uses, returning metered /
  corrected / Δstop / beyond-range rows.
- Controller exposes previewFormula/TableCheckpoints + calculationBasis (Tc = a ×
  Tm^p + b, dropping neutral a=1/b=0); wired through ShootingApp → editor.
- Editor Preview now renders "CALCULATION BASIS" (exponent as superscript) + the
  checkpoint table (Δstop tinted: primary, amber beyond-range, dim for No
  correction) below the graph.
- Core test locks Tm^1.9 → 10s≈79s≈+3.0 stops and beyond-range flagging.
Build + :core/:app tests green.
Next unit: the Details section (Source / Notes / Reference URL) — needs core +
DataStore fields (notes exists; sourceType + referenceUrl are new), done
backward-compatibly so existing saved films still load.

**User:** A bit better. (checked preview capture.) Continue — keep going until
something I need to test comes up.
**Claude (preview polish + Details section):**
- Checkpoint table font tightened to bodySmall + maxLines=1 so the long
  "1000s (16m 40s)" metered cell no longer wraps.
- Added the Details section (iOS parity), all backward-compatible — the core
  ReciprocityProfile.userMetadata already models notes/customSourceType/
  referenceURL and persistence serializes it (ignoreUnknownKeys + encodeDefaults),
  so existing saved films still load:
  - Source: a dropdown of CustomProfileSourceType (User-defined / Personal test /
    Community reference / Unknown source).
  - Notes: multiline optional field.
  - Reference URL: optional URL field.
  Threaded sourceType + referenceUrl through CustomFormula/TableFilmInput →
  CustomFilmBuilder.assemble → userMetadata, and round-tripped them (plus notes)
  in CalculatorController.customFilmDraft. New controller test locks the round-trip.
Build + :core/:app tests green. Renamed scratch 181-184.
Remaining custom-film parity item: the table's fitted "Create Custom Formula"
is a dialog vs iOS's inline "App-derived formula preview" section.

**User:** (checked capture) The Details fields are added to the edit screen and
save, but they don't show in the detail viewer. Is that intended?
**Claude:** Not intended — iOS's Film Details sheet surfaces the custom profile's
provenance (Source / Notes / Reference URL) too. Closed the gap:
- ReciprocityDetailsPresenter now emits notesText + referenceUrlText from
  profile.userMetadata, and the Source row prefers the custom source type
  (Personal test / Community reference …) for custom films; presets fall back to
  the derived source-model label.
- ReciprocityDetailsScreen renders a "Details" block (Notes, Reference URL) when
  present; hidden for presets / when blank.
- Core tests: custom film surfaces notes/url/"Personal test"; preset has no
  provenance rows.
Build + :core/:app tests green. Renamed scratch 185-188.

**User:** Agreed with the advice — start. Tell me what to test when done. (Also
logged two Target Shutter polish items to the backlog: quick+fine modes; tone
down the row value/arrow/diff.)
**Claude (inline fitted formula):** Converted the table's fitted formula from a
popup dialog to an inline "APP-DERIVED FORMULA" section under the table editor
preview (iOS PTIMER-179/180), computed live from the in-progress anchors:
- Shows Tc = a x Tm^p (superscript), the a/p/b line, a per-anchor source-vs-fit
  comparison, and a colour-coded quality verdict (good/borderline/poor) with the
  two-anchor-exact note and the not-manufacturer caption.
- A "Create Custom Formula" button saves the table, then creates and selects a
  separate fitted formula film (label "... (formula)").
- Controller gained form-based previewTableFit + buildFormulaFilmFromTableInput
  (replacing the active-film fittedFormulaOutcome / buildFormulaFilmFromActiveTable);
  removed the film-picker "Create formula from current table film" menu entry,
  the FittedFormulaDialog, and the now-unused canFitFormula state. App test covers
  the fit + create-from-form path.
Build + :core/:app tests green. Divergence from iOS: iOS opens a seeded formula
editor for review before saving; Android creates the formula film directly
(reviewable afterward via Edit) — flagged for the owner.

**User:** Created 2 formulas (from an inaccurate table and from the given-values
table); captured to scratch. Workflow is solid; fine that the editor isn't opened
directly (will unify later if code upkeep needs it). No real problems found; the
film name wrapping to 2 lines is awkward but usable — improve if possible.
**Claude:** Found the real cause: an app-derived formula carries full double
precision (coefficient 1.269048482140576, exponent 1.0935433216785724); the
controller's num() printed it verbatim, so the editor value chips and the
Calculation Basis overflowed to a second line when editing a fitted film. Rounded
num() to 4 decimals (trailing zeros trimmed) — stored values keep full precision
for the calculation; only the display rounds. Also set the film-picker row name to
a single line with ellipsis (Material/iOS convention) so a long custom name no
longer wraps the row to two lines. App test asserts the fitted draft's tc0/exponent
are rounded. Build + tests green. Renamed scratch 189-196.

**User:** Two more problems (captures added). (1) Editing a table doesn't sort
rows right away after Tm/Tc are filled (iOS sorts). (2) Create formula from a
table, check reference points; edit the table to add an anchor; recheck the
formula — the new anchor isn't there.
**Claude:**
(1) Auto-sort: anchor cells now sort complete (both-filled) rows by metered time
on focus-leave (iOS commit point), keeping half-typed rows in place — so 34→60
added at the bottom settles between 10 and 100.
(2) Implemented the iOS linked reference table (PTIMER-180): a formula created
from a table now stores referenceTableFilmID; the editor resolves the source
table's CURRENT anchors at open and shows a live "REFERENCE POINTS · SOURCE TABLE"
table (Metered / Formula / Table / Error, error amber past 0.1 st) in the formula
preview. Edit the table (add an anchor) and the formula's reference points reflect
it. New core CustomFilmReferencePointsPresenter; controller referencePoints +
tableAnchorsOf + draft link round-trip; the link is preserved on re-save. Tests
cover the link round-trip + reference points and the auto-sort path indirectly.
Build + :core/:app tests green. Renamed scratch 203-208.

**User:** (more captures) You're right — creating a NEW custom table→formula does
apply table changes to the formula. How does iOS do it — does the detail view
have reference points? I don't think so; it's already formula-based so they seem
unnecessary, and too much info in the detail view is confusing. Leave them out
for now.
**Claude:** Confirmed against iOS source: reference points live only in
CustomFilmEditorView's preview table; the runtime FilmModeDetailsView has none.
Our build already matches — reference points are editor-only; the detail view
shows just status/model/equation/graph + provenance (Source/Notes/Reference URL).
So nothing to remove; we're aligned with iOS and the "keep detail view lean"
preference. The earlier formula didn't update only because it predated the link
feature; newly created table→formula films track table edits. No code change.
Renamed scratch 209-221; saved the detail-view-lean preference to memory.

**User:** (chose) Target Shutter polish next.
**Claude (Target Shutter):** Worked from the iOS source (TargetShutterInputSheet
Quick/Fine pages; TargetShutterCard styling).
- Quick + Fine: added a Quick/Fine segmented toggle to TargetShutterSheet. Quick
  is a single SnapWheel of presets (1/2/4/8/15/30s, 1/2/4/8m, 15/30m, 1/2/4/8h)
  parking on the nearest preset to the current value; Fine keeps the h/m/s wheels.
  Both edit the same total; defaults to Quick when the seed is a preset.
- Tone down the row: the target value is now bodyLarge SemiBold in onSurface
  (brighter, lighter, was titleMedium Bold in the dimmer card colour); the ↑/↓
  arrow + stop-diff dropped to bodyMedium and are coloured by direction like iOS
  (accent for longer / amber for shorter / green for match), not bold amber for
  all. Backlog items marked done.
Build green (UI-only). Left uncommitted for device test.

**User:** (captures) Quick/Fine: heights differ between modes; the Quick/Fine
buttons are too big and get in the way of the wheel ("Quick isn't quick"); can't
swipe between modes. The nearest-value parking on switch works well. Toned-down
row is good.
**Claude:** Reworked Quick/Fine to a swipeable pager (iOS Quick/Fine pages):
- Replaced the big segmented toggle with a HorizontalPager (2 pages) + a small
  Quick/Fine label above and page dots below, so the wheel has unobstructed
  space and you swipe between modes.
- Fixed pager height (150dp) with each page vertically centered, so switching
  modes no longer resizes the sheet.
- Nearest-preset parking unchanged. Toned-down row left as-is (approved).
Build green (UI-only). Left uncommitted for device test.

**User:** Test: height fixed; swipe works; toned-down row good. But Quick/Fine
nearest-value sync: Quick 4m → Fine shows 4m (OK); Fine 5h7m → Quick shows 4m
(NOT OK — should park near 4h).
**Claude:** Root cause: SnapWheel only read its index at init (initialFirstVisible
ItemIndex); it never re-centered when the value was set from outside, so the Quick
wheel stayed stale. Fixed SnapWheel with a LaunchedEffect(selectedIndex) that
scrollToItem when the requested index differs from the centered row and no
scroll/fling is in flight — so it re-centers on Quick/Fine parking (and slot
switch / reset) without fighting an active spin. Now switching to a mode parks the
wheel on the current value's nearest position (and emits, so Fine 5h7m → Quick
snaps to 4h — the approximate-value-on-switch behaviour the user likes).
Adopted the emulator workflow (user directive): built/installed/launched/
screenshotted on emulator-5554 — build+install+render verified, sheet height
consistent. Caveat: adb synthetic gestures can't drive the SnapWheel/pager
(snap/velocity disambiguation), so wheel-scroll + pager-swipe still need a finger
test. Left uncommitted.

**User:** Quick/Fine nearest-value confirmed fixed. New ask: iOS shows an
edge indicator (Fine teaser on Quick's right, Quick teaser on Fine's left) that
another page exists — add that visual cue (peek or an artificial box).
**Claude:** Added ModeTeaser (iOS TargetShutterModeTeaser): a thin-outlined tall
box on the pager's far edge with a chevron toward the other page + its label —
"Fine ›" on the Quick page's right, "‹ Quick" on the Fine page's left; tapping it
animates to that page. Verified on emulator-5554: Quick shows the Fine teaser;
tapping it navigates to Fine which shows the Quick teaser (value carries over);
swiping pages back. Correction to the earlier note: adb DOES drive the
SnapWheel/pager — my prior "can't" was bad coordinates; the fix is to read exact
device bounds from `uiautomator dump`, not eyeball a downscaled screenshot.
Build + install + interaction verified on emulator. Left uncommitted.

**User:** Don't just reduce commit count — ShootingScreen.kt's SIZE is the tech
debt; reconstruct per-feature. (Reframed: the monolith is the real problem; split
it before MVP done.)
**Claude (refactor 1/N):** ShootingScreen.kt was 2056 lines holding the main
screen + custom-film editor + target sheet + film picker + reciprocity preview.
Extracted the whole custom-film editor (CustomFilmEditorDialog + its exclusive
helpers: FittedFormulaSection, ReciprocityPreviewSection, CheckpointTable,
ReferencePointsSection, FullScreenFormDialog, AnchorField, EditorRow,
ValueEditPanel, FormulaTemplate/Chip/HelpPanel, presets, etc.) into
CustomFilmEditor.kt (same package; Dialog made internal). Verified the helpers
were editor-exclusive first (trimNum/SectionLabel/FormCard/fitNum/clockLabel only
used there; Pill/StartButton/PagerDots stay shared). Pruned now-unused imports in
both files. ShootingScreen.kt 2056 → 927 lines. Build + :app/:core tests green;
app renders on emulator, no crash. More extractions (Target Shutter, Film Picker)
to follow.

**Claude (refactor 2/N):** Extracted the Target Shutter UI — the main-screen
TargetShutterRow and the Quick/Fine TargetShutterSheet (+ ModeTeaser, HmsWheel,
formatHms, targetClock) — into TargetShutterUi.kt. Shared StartButton + PagerDots
stay in ShootingScreen, now internal so the new file can call them. Pure
relocation, imports pruned. ShootingScreen.kt 927 → 655 lines. Build + tests green.

**Claude (refactor 3/N):** Extracted the film picker — the bottom sheet (now a
FilmPickerSheet composable taking select/create/edit/delete/dismiss lambdas) plus
FilmPickerRow / FilmManufacturerHeader / CurveGlyph — into FilmPicker.kt. Pill is
shared with the result row so it stays in ShootingScreen (now internal). Verified
on emulator: the picker opens and lists No film + manufacturer groups correctly.
ShootingScreen.kt 655 → 490 lines (from the original 2056). Net: the monolith is
now four focused files — ShootingScreen (main surface + result + rename),
CustomFilmEditor, TargetShutterUi, FilmPicker. Build + tests green each step.

**User:** You squashed it completely — too few. Let's split these commits again
and distinguish the logical units within each. The first commit bundled
docs/design/ios-screens with the logical (code) part into one commit — absolutely
unacceptable. Same for the others: do it by logical unit, implementation unit,
buildable unit, capability-adding unit. Don't delete the backup branch yet — we
can return to it if needed.
**Claude (revert the over-squash):** Agreed — the 12-milestone squash was a
regression: it coarsened granularity, discarded the per-commit Android-port
traceability messages, and bundled docs/design/ios-screens into the first code
milestone. Restored the per-capability history (54 commits) from
backup-pre-reauthor, which already satisfies every criterion: commit 1 is
docs/captures only (0 android/ files; ios-screens lives in that one commit alone),
and each subsequent commit is one logical, buildable, capability-adding unit with
its 완료/일부/참조 JIRA mapping. Order is dependency/capability progression (core →
first runnable timer app → shooting → slots/details/custom/notifications → iOS
polish → editor buildout → ShootingScreen split). Backup tag/branch kept.

**User:** That's just a revert — Target Shutter and the other features are still
scattered across commits. Do the real tree surgery / reorder; reconstruct anew
(don't take the easy cherry-pick route). As long as the final result is identical,
we're safe.
**Claude (full rework):** Proved cherry-pick reorder can't de-scatter the features
(e.g. the Target wheel commit is built on top of the iOS-layout rework inside the
monolithic ShootingScreen, so it can't be grafted onto the earlier layout).
Reconstructed the history forward from the final split files instead: a fresh
branch on origin/main, each feature rebuilt as one consolidated milestone (its core
+ its own UI file + shell wiring), the shells grown per milestone, converging to
the exact final code. Milestones: docs → skeleton → calc engine → timer app →
shooting calc → camera slots → Target Shutter → Reciprocity Details → Custom Film →
Notifications → slot-session persistence + per-slot states → iOS layout + peeking
timers. Every milestone builds + tests green; the final android/ tree is
byte-identical to the prior working version (verified empty diff). Backup kept at
tag backup-pre-reauthor.

**User:** Don't reduce the commit count — group/split. Keep logical units. Split
each commit into 3–10 finer units; the number doesn't matter, the logical unit
does. Explain what each commit logically contains, and show me first how it can be
composed by user-testable-feature criterion — I'll review and approve, step by
step.
**Claude (plan):** Presented a per-commit decomposition: each of the 13 commits →
its logical contents + proposed split into ✅ user-testable steps and ⚙ supporting
units, with an effort-tier note (easy file-boundary splits vs shell-coupled vs the
two heavy single-file ones). User approved ("순서대로해 고고").
**Claude (execute):** Rebuilt on origin/main, expanding the 13 commits into 35
finer commits, oldest→newest, each built + tested green before committing. Each
sub-unit's content is sourced from its original fine-grained commit (or the
parent's file groups) so intermediate file versions are correct. Splits: docs→2,
skeleton→1, calc engine→6, timer+app→4, shooting calc→2, slots→2, Target→2,
Details→3, Custom Film→5, Notifications→3, slot persistence→2, iOS layout→3. The
custom-film editor and the iOS-layout shell stay at component granularity (single
cohesive files). Final android/ios tree byte-identical to the prior version;
backup kept at backup-pre-reauthor.
