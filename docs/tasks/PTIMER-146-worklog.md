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
| 11 | Post-Process-Death Alarm Delivery Verification | (latest branch HEAD) | 198 | exact-granted delivery after `am kill` verified on device; docs-only |

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

*Append future passes below this line: instruction scope + full report.*
