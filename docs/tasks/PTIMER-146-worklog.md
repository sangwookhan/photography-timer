# PTIMER-146 Android MVP — Work Log

Running record of the instructions given for the PTIMER-146 Android MVP work and
the report returned for each pass, kept for later work-record use. All work is on
branch `feature/PTIMER-146-android-mvp` / Draft PR #16 (kept draft throughout; no
`ios/` or `shared/` changes in any pass).

> Fidelity note: entries before this file existed are faithful condensed
> summaries (instruction scope + report highlights), reconstructed from the
> session. From the **Exact Alarm Permission** pass onward, the instruction scope
> and the full report are recorded.

## Pass index

| # | Pass | HEAD | Tests | Outcome |
|---|---|---|---|---|
| 1 | iOS Test-Intent Parity Audit + Blocker Implementation | `7778a4f` | 123 | Per-test audit doc; 5 MVP blockers fixed |
| — | `snapshot-source` skill: include Android sources | (skill file, not in repo tree) | — | iOS+Android both archived; build/temp excluded; patches kept |
| 2 | Restore/Persistence Hardening Pass 1 | `2221f9b` | 147 | timer-id collision, stale film/profile, slot-name, custom-id, per-item decode |
| 3 | Restore/Persistence Hardening Pass 2 | `c6a5825` | 159 | malformed-typed-field per-item decode, dup-id ordering, ready guard |
| 4 | Narrow restore catch scope (correction) | `3ee1f77` | 164 | catch = load/decode only; wiring surfaces errors |
| 5 | Catch-scope finish (custom lib construction out of catch, amended) | `df5323a` | 164 | `runCatching` covers only load/decode |
| 6 | End-to-End Restore + Custom Film Verification | `45b0170` | 172 | 8 app-level round-trip tests; on-device kill/relaunch restore confirmed |
| 7 | Background Timer Completion Reliability | `5ccb538` | 184 | scheduler abstraction + AlarmManager best-effort + 12 tests |
| 8 | Background Completion Cleanup | `6d52f0d` | 184 | force-stop wording, completion subtitle, ongoing-notif policy |
| 9 | Exact Alarm Permission + Delivery Verification | `f0b32bf` | 192 | exact-when-permitted + request flow; both paths verified on device |
| 10 | Exact Alarm Settings Return Cleanup | `b4c4c77` | 198 | refresh on resume reschedules + clears notice; round-trip verified on device |
| 11 | Post-Process-Death Alarm Delivery Verification | `103fd0f` | 198 | exact-granted delivery after `am kill` verified on device; docs-only |
| 12 | Compose UI Smoke Test | `5bbf0c1` | 198 JVM + 3 instrumented (env-blocked) | testTags + smoke tests; connected run blocked by Espresso↔API37-preview |
| 13 | Stable Emulator Compose Smoke Retry | `a5cfb90` | 198 JVM; smoke 0/3 verified | stable API emulator unavailable + uncreatable (no image, SDK repo unreachable); docs-only |
| 14 | Robolectric Host-Side Compose Smoke | `f3c8dc7` | 201 JVM (host-side smoke 3/3 green) | Robolectric host-side ShootingScreen smoke added + passing in JVM; not a replacement for connected tests |
| 15 | Recovery before continuing | (latest branch HEAD) | 201 JVM | restored full worklog from f3c8dc7 (a prior pass had compacted it 365→52); removed inventory doc; deleted dummy-test branch; docs-only |

Per-test / per-target detail for all passes lives in
`PTIMER-146-ios-test-parity-audit.md` (Passes 1, and the "Restore/Persistence
Hardening", "End-to-End", and "Background … " sections).

---

## Pass 1 — iOS Test-Intent Parity Audit + Blocker Implementation

**Instruction (scope):** Audit all 1,382 iOS test functions at the
individual-test level; record per test the intent/protected invariant + Android
status + decision into `PTIMER-146-ios-test-parity-audit.md`. Then implement only
proven MVP blockers; verify `./gradlew clean :core:test testDebugUnitTest
assembleDebug`; commit in logical chunks; keep PR #16 draft.

**Report (highlights):** Produced the per-test audit (six parallel readers).
Found + fixed 5 MVP blockers: per-film catalog parity test; `apply()` sanitizes
corrupt base/ND/target; unknown persisted film → digital; timer-identity
immutability; custom-library malformed-shape sanitation. Surfaced a fixture
drift (Portra 160/400 threshold max stale vs catalog — iOS-side follow-up).
123 tests green. HEAD `7778a4f`.

## Pass 2 — Restore/Persistence Hardening Pass 1

**Instruction (scope):** Fix restore/persistence blockers: timer-id collision
after restore, stale film/profile sanitation, camera-slot restored-name
sanitation, custom-film id sequencing, per-item corrupt timer snapshot decode.

**Report:** Counter advances past restored ids; `apply()` normalizes stale
film/profile ids; `CameraSlotSession.restore` trims/drops/ignores-unknown names;
`CustomFilmIdSequencer` derives ids from max suffix; `TimerSnapshotCodec` skips
structurally-invalid items. 147 tests. HEAD `2221f9b`.

## Pass 3 — Restore/Persistence Hardening Pass 2

**Instruction (scope):** Malformed typed fields must not drop the whole snapshot;
duplicate-id ordering must keep the valid item; audit/guard ViewModel restore
ordering.

**Report:** `decode()` parses the envelope then each item individually
(`runCatching` per item); dup-id reserved only after validation; `ShootingViewModel`
gained a `ready` flag gating `onEvent`. 159 tests. HEAD `c6a5825`.

## Pass 4 — Narrow restore catch scope

**Instruction (scope):** The fail-safe `runCatching` also wrapped application
wiring (`restoreFromJson`/`session.restore`/`calc.apply`); narrow it to
persistence load/decode so wiring errors surface.

**Report:** `runCatching` now captures only load/decode results; wiring runs
outside the swallowed path; `_ready` still set in `finally`. 164 tests. HEAD
`3ee1f77`.

## Pass 5 — Catch-scope finish (amended)

**Instruction (scope):** Custom-film library construction was still inside the
catch; move `CustomFilmLibrary(...)` out so `runCatching` covers only load/decode.
Amend into `3ee1f77`, force-push with lease.

**Report:** `runCatching` now yields `loadedCustomFilms` (decode only);
`CustomFilmLibrary(it)` constructed outside. Amended; HEAD `df5323a`. 164 tests.

## Pass 6 — End-to-End Restore + Custom Film Verification

**Instruction (scope):** Move from codec/controller confidence to app-level
confidence: add ViewModel↔store↔codec↔controller round-trip tests; verify on
emulator if available.

**Report:** Added `ShootingViewModelEndToEndRestoreTest` (8 round-trip tests:
active/completed timer restore, slot/session, custom formula/table/derived,
delete-fallback, custom-film timer identity). On-device kill/relaunch restored
film/model/ND/reciprocity with no crash. No blocker found. 172 tests. HEAD
`45b0170`.

## Pass 7 — Background Timer Completion Reliability

**Instruction (scope):** Move completion from in-process-only to a scheduled
AlarmManager path behind a testable abstraction; schedule on start/resume, cancel
on pause/remove/complete, reconcile on relaunch; do not overclaim exact/Doze/OEM
reliability.

**Report:** Added `TimerCompletionScheduler` (+ NoOp) and
`AndroidTimerCompletionScheduler` + `CompletionAlarmReceiver` (manifest);
`syncSchedules()` reconciles alarms after timer events and restore. Best-effort:
exact on API < 31, inexact on API 31+ (no `SCHEDULE_EXACT_ALARM` yet). 12
scheduling tests; on-device alarm registration confirmed. 5 reliability targets
1/5 → 4/5. 184 tests. HEAD `5ccb538`.

## Pass 8 — Background Completion Cleanup

**Instruction (scope):** Fix force-stop wording; preserve completion-notification
subtitle; document ongoing-notification reconciliation policy.

**Report:** Scheduler doc corrected (force-stop cancels alarms, not a guarantee);
`postCompletion(id, name, subtitle?)` shows identity as title + source as body
(verified on device); documented that the receiver posts only the done
notification and ongoing reconciliation stays in the ViewModel. 184 tests. HEAD
`6d52f0d`.

## Pass 9 — Exact Alarm Permission + Delivery Verification

**Instruction (scope):** Close or clearly classify the last background-reliability
target: decide an exact-alarm permission policy; implement the smallest safe
flow; use exact when permitted; fall back safely; verify delivery as far as
emulator allows; do not claim force-stop delivery or unverified exact delivery.
Also: keep a work log of instructions + reports (this file).

**Report:**

- **Verdict:** Enumerated 5-target set closed (5/5); MVP still **not** review-ready
  (foreground service + faithful post-process-death delivery remain). PR #16 draft.
- **Exact alarm policy:** declare `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM`);
  exact when `canScheduleExactAlarms()`, else best-effort inexact; dismissible
  in-app request opening `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. Play exact-alarm
  declaration required at publish (documented decision).
- **What changed:** pure `ExactAlarmPolicy` + `ExactAlarmDecision`/`FallbackMode`
  (JVM-tested); `ExactAlarmAvailability` interface (+ Always / Android impls);
  scheduler routes exact/inexact via the policy; manifest declares the permission;
  `ShootingViewModel.exactAlarmPrompt` + `DismissExactAlarmPrompt`;
  `ShootingScreen` compact notice; `MainActivity` opens the settings deep-link.
- **Tests (+8):** `ExactAlarmPolicyTest` (4), `ShootingViewModelExactAlarmPromptTest`
  (4). 192 total (76 core + 116 app), 0 failures.
- **Manual/emulator (emulator-5554, API 37):** `appops … SCHEDULE_EXACT_ALARM deny`
  → notice shown + inexact alarm registered + no crash; `… allow` → no notice +
  alarm registered (exact path). Path selection + registration verified; actual
  post-process-death firing **not** verified; `connectedAndroidTest` not run.
- **Coverage:** before 4/5 = 80% → after 5/5 = 100%; automated 5/5; remaining
  follow-up (outside the 5-target set): foreground service + faithful post-kill
  delivery test.
- **HEAD:** see PR #16 / latest commit on the branch.

---

## Pass 10 — Exact Alarm Settings Return Cleanup

**Instruction (scope):** Close the exact-alarm settings-return gap (narrow pass;
no foreground service / UI redesign / iOS changes). On resume / return from the
exact-alarm settings screen the app must: re-check exact availability, refresh
the prompt, and reschedule running timers when availability changes
denied→granted; keep inexact fallback when still denied; choose a sensible
dismissed-state rule; cover with JVM tests; verify the real round-trip on device
(appops toggle while backgrounded + resume is acceptable if stated). 8
settings-return targets.

**Report:**

- **Verdict:** Settings-return gap closed (8/8 targets); MVP still **not**
  review-ready (post-process-death firing + foreground service remain). PR #16 draft.
- **Audit (before):** exact availability was read only inside
  `refreshExactAlarmPrompt()` which ran only on timer events (via
  `syncSchedules()`); no resume hook; after a settings grant the notice stayed
  stale and running timers stayed on the old inexact path until the next timer
  action; `exactAlarmPromptDismissed` was a permanent flag.
- **What changed:** added `ShootingViewModel.refreshExactAlarmAvailability()`
  (re-reads availability; reschedules via `syncSchedules()` only when changed;
  clears dismissed-suppression on grant); `MainActivity` calls it from
  `LifecycleEventEffect(ON_RESUME)`; `refreshExactAlarmPrompt()` now records
  `lastExactAvailable` for change detection.
- **Tests (+6):** `ShootingViewModelExactAlarmPromptTest` 4 → 10 (grant→hide,
  grant→reschedule, still-denied→no-reschedule, dismissed+denied→no-renag,
  dismissed+granted→hidden+suppression-cleared, granted→denied→fallback+prompt).
  198 total (76 core + 122 app), 0 failures.
- **Manual/emulator (emulator-5554, API 37):** `appops … deny` → start timer →
  notice + inexact alarm; HOME → `appops … allow` → resume → notice cleared,
  alarm rescheduled (exact clock icon), no crash. Used appops-while-backgrounded
  + resume, not the settings UI. Post-process-death firing **not** verified;
  `connectedAndroidTest` not run.
- **Coverage:** settings-return targets 2/8 → 8/8 = 100%; automated 8/8;
  remaining-in-set 0/8. Beyond set: post-kill delivery + foreground service.
- **HEAD:** see PR #16 / latest branch commit.

---

## Pass 11 — Post-Process-Death Alarm Delivery Verification

**Instruction (scope):** Verify whether a running-timer completion notification
actually fires after the app process is killed — **without** `force-stop` (use
`adb shell am kill` or another non-force-stop reclaim; confirm the process is
gone). Test exact-granted, then exact-denied/inexact if practical. Record
commands/evidence in the work log. Classify whether a foreground service is
required for MVP. Apply only a minimal code fix if the delivery path has a clear
bug; otherwise docs-only. No foreground service / iOS changes. 10 targets.

**Report:**

- **Verdict:** Exact-granted post-process-death delivery **VERIFIED** on device;
  no code change needed (delivery path worked). Foreground service is **not a
  blocker** for exact-granted completion delivery. MVP still **not** review-ready.
  PR #16 draft.
- **Preflight:** receiver registered (`exported=false`, correct for own-app alarm
  PendingIntent); RTC_WAKEUP + exact-when-permitted; id/title/subtitle extras
  passed; completion channel created in notifier init (so it exists on a
  cold-start delivery). No issue found.
- **Build:** `clean :core:test testDebugUnitTest assembleDebug` → BUILD
  SUCCESSFUL; 198 tests (76 core + 122 app), 0 failures; APK installed.
- **Exact-granted (emulator-5554, API 37):** `appops … allow`; started a 34.1s
  adjusted timer (ND 10). `dumpsys alarm` → `RTC_WAKEUP window=0
  exactAllowReason=permission` (true exact). `input keyevent HOME`;
  `am kill com.sangwook.ptimer`; `pidof` empty (process gone, alarm survived).
  After the trigger the process cold-started (new pid) and the notification
  posted with **no manual relaunch**: `title="Camera 1 · Fomapan 100 Classic"`,
  `text="Adjusted Shutter · 34.1s"`. Alarm history: "1 wakes 1 alarms" (fired).
- **Exact-denied / inexact:** `appops … deny`; alarm registered inexact
  (`window=+25s, ALLOW_WHILE_IDLE`, no `exactAllowReason`). After `am kill` it
  cold-started + fired within the window on this active emulator — best-effort
  only; can be deferred under real Doze / OEM. Not a guarantee.
- **What changed:** docs/worklog only — `am kill` proved no delivery bug exists.
- **Coverage (post-death delivery, 10 targets):** before 3/10 = 30% → after
  10/10 = 100%; automated 0/10 (OS delivery is device-only; scheduling logic
  JVM-tested elsewhere); manual/device-only 10/10; remaining-in-set 0/10.
- **Bounds:** force-stop unsupported (cancels alarms); single emulator, not real
  OEM/Doze; inexact post-death delivery best-effort.
- **HEAD:** see PR #16 / latest branch commit.

---

## Pass 12 — Compose UI Smoke Test

**Instruction (scope):** Add a small, reliable Compose UI smoke layer proving the
app launches and the minimum shooting flow runs without crashing — not pixel /
visual parity. Add stable testTags only where needed; cover launch/ready,
start-adjusted→active-row with source identity, pause/resume/remove; handle
POST_NOTIFICATIONS without manual tapping; pass whether or not the exact-alarm
notice is present; run `connectedDebugAndroidTest` if a device is available and
do not falsely report it as passing. No UI parity / redesign / iOS changes.

**Report:**

- **Verdict:** Smoke tests **added** and runner-executed, but **not verified
  passing** on the only available emulator (API 37 preview) due to a test-library
  incompatibility — not an app failure. JVM build green (198). MVP **not**
  review-ready; UI parity not attempted. PR #16 draft.
- **Preflight:** Compose test deps present (`ui-test-junit4`, debug
  `ui-test-manifest`, `AndroidJUnitRunner`); no `androidTest` source set existed;
  added `androidx.test:rules` for `GrantPermissionRule`.
- **What changed (code):** `TestTags` + `Modifier.testTag` on ShootingScreen
  content, RestoringOverlay, ExactAlarmNotice, StartAdjustedButton,
  ActiveTimerRow, NdPlusButton (selectors only — no behavior/layout change). New
  `ShootingScreenSmokeTest` (3 instrumented tests).
- **Verification:** `clean :core:test testDebugUnitTest assembleDebug` → BUILD
  SUCCESSFUL, 198 tests (76 core + 122 app), 0 failures. `pm clear` then
  `connectedDebugAndroidTest` on emulator-5554 (Pixel_10, API 37 preview) →
  compiled, installed, launched (no app crash), but all 3 failed in Espresso
  `onIdle` with `NoSuchMethodException: InputManager.getInstance []` (Espresso
  3.6.1 ↔ API 37 preview). Distinguished as a Gradle/test-library environment
  issue, not app behavior.
- **Coverage (10 targets):** before 0/10; authored+compiling 8/10 = 80%
  (targets 1–8); verified-passing-on-device 0/10 (env block); target 9 run,
  target 10 honored. Remaining follow-up: verify on a stable-API emulator or add
  a Robolectric JVM Compose layer.
- **Test counts:** JVM before 198 / after 198 (no JVM tests added; tags don't
  change unit count); instrumented added 3; instrumented run 3; instrumented
  passed 0 (env-blocked).
- **HEAD:** see PR #16 / latest branch commit.

---

## Pass 13 — Stable Emulator Compose Smoke Retry

**Instruction (scope):** Actually attempt to verify the 3 existing Compose smoke
tests on a **stable** API 34/35 emulator (not the API 37 preview): list AVDs +
installed system images; if a stable emulator exists, run
`connectedDebugAndroidTest`; if not, determine whether one can be created; if
creation is impossible, stop and report the environment block. Do not use API 37
preview as the green target; do not change app code unless a minimal test fix is
needed; do not repeat the old Pass 12 report.

**Report — Outcome C (stable emulator unavailable, cannot be created):**

- **Preflight:** `emulator` not on PATH but `ANDROID_HOME=…/Library/Android/sdk`.
  AVDs: **only `Pixel_10`** (the running **API 37 preview**, `ro.build.version.sdk=37`,
  release 17, `sdk_gphone16k_arm64`). Installed system images: **only
  `android-37.0;google_apis_playstore_ps16k;arm64-v8a`**. No API 34/35 image.
- **Creation probe:** `sdkmanager --list` (SDK-repository query) **timed out at
  90s** → the repo is unreachable / network-blocked, so a stable system image
  **cannot be downloaded** and no stable AVD can be created in this environment.
- **Result:** the 3 smoke tests remain **authored (3/3) but 0/3 verified green on
  a stable API**. `connectedDebugAndroidTest` was **not** run this pass (no stable
  target; API 37 preview excluded as a green target by the instruction).
- **What changed:** docs/worklog only — **no app code changed** (per the
  environment-block instruction).
- **Verification:** `clean :core:test testDebugUnitTest assembleDebug` → BUILD
  SUCCESSFUL, 198 tests, 0 failures.
- **Counts:** authored 3; passing before 0/3; stable-API run attempted 0/1
  (uncreatable); passing after 0/3; environment-blocked 1/1 = 100%; remaining
  follow-up 3/3.
- **Next:** run on a stable-API (34/35) emulator where one is installable/available,
  or add a Robolectric host-side Compose smoke layer (future pass).
- **HEAD:** see PR #16 / latest branch commit.

---

## Pass 14 — Robolectric Host-Side Compose Smoke

**Instruction (scope):** Feasibility + minimal implementation of a host-side
(Robolectric) Compose smoke safety net that runs under JVM tests without an
emulator — a fallback for the blocked environment, NOT a replacement for
`connectedDebugAndroidTest`. Prefer rendering the stateless `ShootingScreen`
(avoid MainActivity full stack); add minimal deps only if needed; assert
selectors + (optionally) active-row identity; keep product behavior unchanged;
document what it does/doesn't prove. If deps can't be downloaded, stop + report.

**Report — feasible and implemented (green in JVM):**

- **Feasibility:** `ShootingScreen` is **stateless** (plain state + `onEvent`
  lambda, no ViewModel) → renderable with fakes (Option A). Robolectric 4.16.1 +
  compose `ui-test-junit4`/`ui-test-manifest` are cached; `android-all`
  runtimes cached for SDK 11/12/13/16 (NOT 14/15), so pinned `@Config(sdk = 33)`.
  Maven resolution works (distinct from the blocked SDK-image repo).
- **What changed:** `app/build.gradle.kts` — `testOptions.unitTests.isIncludeAndroidResources=true`
  and `testImplementation` for Robolectric 4.16.1 + compose `ui-test-junit4` +
  `ui-test-manifest` (+ compose BOM on the test classpath). New
  `ShootingScreenHostSmokeTest`. **No product code changed** (one test-only
  scroll fix so the Result row composes on Robolectric's small screen).
- **Tests (+3):** `hostSmoke_rendersReadyShootingScreen`,
  `hostSmoke_rendersAdjustedStartAction`, `hostSmoke_rendersActiveTimerRowWithSourceIdentity`
  — all pass under `./gradlew testDebugUnitTest`. JVM suite 198 → 201.
- **What it proves / doesn't:** proves the screen composes, smoke selectors
  exist, and an active row renders with title + source line. Does **not** prove
  real interaction/behavior (fake `onEvent` no-op), the MainActivity/DataStore/
  alarm/permission stack, or visual parity. **Does not replace** instrumented
  connected smoke (still emulator-blocked: API 37 preview Espresso issue; no
  stable emulator).
- **Verification:** `clean :core:test testDebugUnitTest assembleDebug` → BUILD
  SUCCESSFUL, 201 tests, 0 failures. `connectedDebugAndroidTest` not run
  (unchanged, still blocked).
- **Counts:** host-side targets — feasibility 10/10, implemented 10/10, passing
  in JVM 3/3 host-side tests; environment-blocked 0/10 (host path works);
  remaining follow-up = real interaction smoke on a stable emulator.
- **HEAD:** see PR #16 / latest branch commit.

---

## Pass 15 — Recovery before continuing

**Instruction (scope):** Recover PR #16 to a clean state before any
implementation (no UI parity yet, no iOS/shared changes, keep PR draft). A prior
pass had compacted this worklog (365→52 lines) and added
`PTIMER-146-ui-parity-inventory.md`. Restore the full Pass 1–14 worklog from the
safe `f3c8dc7` state; decide whether to keep or remove the inventory doc; ensure
no `dummy-test` branch exists; run `clean :core:test testDebugUnitTest
assembleDebug`.

**Report:**

- **Assessment:** remote PR tip was `62774ec` (2 docs-only commits past the safe
  `f3c8dc7`: `5b074b1` compacted the worklog, `62774ec` added the inventory
  doc). No `ios/`, `shared/`, or `android/app/src` code was touched by those
  commits; the whole PR diff still has **no iOS/shared** changes.
- **Worklog restored** from the `f3c8dc7` blob — full Pass 1–14, ending with the
  append marker (byte-identical to the safe version), replacing the compacted
  52-line version.
- **Inventory doc removed** (`PTIMER-146-ui-parity-inventory.md`). Decision:
  delete and redo cleanly later. It was honest about its limits but was produced
  in the same damaged pass (no Gradle run, no iOS-source fetch, connector-only),
  and the defined safe state contains no inventory doc; a fresh inventory will be
  done in a proper pass with real iOS source + Gradle.
- **`dummy-test` branch deleted** (was present on the remote).
- **Recovery is forward-fix** (a new docs-only commit on top of `62774ec`,
  preserving PR history) — no history rewrite, no force-push.
- **Verification:** `clean :core:test testDebugUnitTest assembleDebug` →
  BUILD SUCCESSFUL, 201 tests, 0 failures. PR #16 stays draft/open. No Details
  UI parity implementation started (deferred until recovery is confirmed clean).
- **HEAD:** see PR #16 / latest branch commit.

---

*Append future passes below this line: instruction scope + full report.*
