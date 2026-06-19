# PTIMER-146 Android MVP — iOS Test-Intent Parity Audit

Individual-test-case audit of the iOS suite against the Android MVP, plus
the MVP-blocker list and the blockers implemented this pass.

- **iOS suite audited**: 1,382 `func test…` functions across ~130 files
  (`PTimerCoreTests`, `PTimerKitTests`, app-hosted `PTimerTests`).
- **Audit method**: six parallel readers (A Exposure, B Reciprocity,
  C Catalog+Custom, D Timer+Persistence+Notification, E Slots+Target+Film,
  F Presentation) read the iOS sources test-by-test and recorded each test's
  intent and protected invariant. This document assigns each a parity
  **Status** and **Decision** against the Android implementation
  (`android/`, branch `feature/PTIMER-146-android-mvp`, Draft PR #16).
- **Truth rule applied**: *covered* means Android has a test that would fail
  if the same protected behavior regressed. Anything that holds only "by
  construction" (no asserting test) is marked **partial**, not covered.
- This supersedes the coarse area map in
  `PTIMER-146-android-test-intent-map.md` (kept as the area-level companion).

## Status / Decision legend

| Status | Meaning |
|---|---|
| ✅ covered | Android test fails if the behavior regresses |
| 🟡 partial | covered by construction or partially asserted, not pinned by a dedicated test |
| ❌ missing | no Android coverage |
| N/A | not applicable to the Android MVP (iOS-only surface or deliberate design divergence) |

| Decision | Meaning |
|---|---|
| **blocker→done** | MVP blocker; closed this pass (code and/or test added) |
| **already-covered** | behavior parity already held and is asserted; no change needed |
| **android-replacement** | Android intentionally realizes this differently (e.g. whole-stop steppers vs the iOS 1/3-stop wheel) |
| **ios-only** | no Android equivalent surface (ActivityKit, lock-screen, RecordReplay, SwiftUI dock/shell/theme) |
| **follow-up** | real parity gap, but out of MVP scope — post-MVP ticket |

---

## Verdict

The Android MVP holds **functional parity for every protected-behavior area**:
exposure calculation, the reciprocity policy evaluator (formula / log-log table
/ threshold+limited-guidance), per-film catalog constants, the timer
state-machine and restore contract, camera-slot isolation, per-source start
actions, and Target Shutter. Where iOS coverage is *not* mirrored it is by
deliberate design divergence (the 1/3-stop wheel and the rich Reciprocity
Details graph/vocabulary surfaces) or an explicitly deferred follow-up
(notification background delivery / foreground service), not an unaudited gap.

Five MVP blockers were found and closed this pass (see below). This audit is
**complete at the individual-test level** for the protected areas; the
deferred-presentation and iOS-only surfaces are audited at file+intent level
with a per-file verdict (every test's intent is listed; their Status/Decision
is uniform within a file and stated once).

---

## MVP blockers found and implemented

| # | Blocker | iOS invariant | Android fix | Test |
|---|---|---|---|---|
| 1 | Per-film catalog calc parity untested | `LaunchPresetFilmCatalogTests` pins each film's formula params / threshold band / provenance | new `CatalogPerFilmParityTest` drives the shared fixture's `perFilmExpectations` against the loaded catalog | `core` `CatalogPerFilmParityTest` (4 tests) |
| 2 | `CalculatorController.apply()` did not sanitize a corrupt persisted **target** | `CameraSlotSessionPersistence.testCorruptedPersistedTargetIsSanitisedAtDecodeTime` | target now passes the same `isFinite() && > 0` gate as `setTarget()` | `applyingSnapshotSanitizesCorruptTargetAndOutOfRangeNd` |
| 3 | `apply()` did not sanitize a corrupt persisted **base shutter** or out-of-range **ND** | `CalculatorContextPersistence.testRelaunchWithInvalidStoredNumericValuesFallsBackToDefaultCalculatorInputs` | base falls back to default when non-finite/≤0; ND coerced to `0..30` | `applyingSnapshotWithCorruptBaseFallsBackToDefaultShutter`, same target/ND test |
| 4 | No test pinning **unknown persisted film id → digital fallback** | `CameraSlotSessionPersistence.testInvalidFilmReferenceInPersistedSlotRestoresAsNoFilm` | behavior already held (`film()` resolves `null`); added a regression test | `applyingSnapshotWithUnknownFilmFallsBackToDigital` |
| 5 | No test pinning **timer-identity immutability** / **custom-library malformed-shape sanitation** | `BottomSheetWorkspaceSnapshotFactoryTests…IndependentFromLaterCalculatorEdits`; `CustomFilmTableProfileFlowTests` drop-cases | behavior already held; added regression tests | `timerIdentityIsImmutableAcrossLifecycleAndLaterStarts`, `libraryRejectsMalformedCustomShapes` |

Blockers 4–5 were *coverage* gaps (the behavior held by construction but no
test would have caught a regression); blockers 2–3 were genuine *behavior*
gaps in the restore path; blocker 1 was both (untested + a finding, below).

### Finding: shared fixture drift (iOS-side, out of PTIMER-146)

`shared/test-fixtures/catalog-validation-cases.json` carries a **stale
`thresholdNoCorrectionMaxSeconds = 1`** for `kodak-portra-160` and
`kodak-portra-400`. The authoritative catalog
(`LaunchPresetFilmCatalog.json`) and current iOS behaviour use **10s**
("Portra beyond 10s → limited guidance"). Per the accepted Round-2 decision
the catalog JSON is authoritative, so `CatalogPerFilmParityTest` validates the
no-correction band's *min* against the fixture and validates the *max* via
band-driven policy behavior using the catalog value. The two stale fixture
entries should be reconciled on the iOS side (separate ticket); they are **not**
an Android defect.

---

## Restore / Persistence Hardening — Pass 1

A source-level review found five restore/persistence risks. All are fixed and
pinned by tests. These were genuine robustness gaps in the Android restore paths
(not iOS-parity copies); the iOS suite protects the same intents via its
persistence suites (`TimerManagerPersistenceRestoreTests`,
`CameraSlotSessionPersistence`, `CalculatorContextPersistence`,
`CustomFilmLifecycleCorrectnessTests`).

| # | Risk | Fix | Tests |
|---|---|---|---|
| 1 | **Timer id collision after restore** — `timer-${counter++}` did not advance past restored ids, so a new timer could re-mint `timer-0` and overwrite a restored timer | `restoreFromJson` advances the counter past the max restored id matching `timer-<n>`; `nextId()` also loops until the id is unused (guards non-generated/custom ids) | `TimerWorkspaceControllerTest`: `startAfterRestoringTimerZero…`, `…SparseIdsContinuesPastTheMax`, `…NonMatchingIdsStillProducesAUniqueId` |
| 2 | **Stale film/profile id on calculator restore** — unknown film id / foreign or primary-as-explicit profile id kept in state, could blank the model picker, resolve a wrong film's alternate, or be recaptured | `apply()` now `sanitizeFilmSelection()`: unknown film clears both ids; explicit-primary or non-alternate profile id normalizes to the primary convention (null); only a known alternate of the selected film survives | `CalculatorControllerTest`: `applyingSnapshotWithUnknownFilm…` (capture cleared), `…UnknownProfileNormalizesToPrimaryModel`, `…ExplicitPrimaryProfileIdNormalizesToNull`, `…KnownAlternateKeepsItSelected`, `activeFilmModelSelectionAlwaysHasExactlyOneSelectedOption` |
| 3 | **Camera-slot restore name sanitation** — names restored raw (blank/whitespace/unknown-slot survived; stale entries retained) | `restore()` keeps only known slot ids, trims, drops blanks, and replaces (no stale carryover); `setCustomName()` ignores unknown slot ids | `CameraSlotSessionTest`: `restoreTrimsCustomNames`, `restoreDropsBlankCustomNames`, `restoreIgnoresUnknownSlotIds`, `restoreReplacesPriorCustomNamesWithoutRetainingStaleEntries`, `setCustomNameIgnoresUnknownSlotIds` |
| 4 | **Custom film id reuse after delete/relaunch** — `customSeq = lib.size` could re-mint an existing id and overwrite a persisted profile | new pure `CustomFilmIdSequencer` derives the next sequence from the max existing numeric suffix (+1), never list size; wired into `ShootingViewModel` | `CustomFilmIdSequencerTest` (5 tests, incl. restore-no-overwrite for formula and table ids) |
| 5 | **Corrupt timer snapshot item sanitation** — whole-snapshot corruption was handled, but a single invalid item could flow into restore | `decode()` skips only the structurally-impossible item (blank/duplicate id, non-finite/≤0 duration, missing start, negative paused remaining) and keeps valid siblings; items merely lacking reconcilable detail (running w/o expected, paused w/o freeze) are kept and **safely completed** by the core restore contract — never resurrected as phantom active timers | `TimerSnapshotCodecTest`: 6 tests incl. skip-corrupt-keep-sibling, running-missing-expected→completed, never-throws-on-malformed-fields, plus `TimerWorkspaceControllerTest.startAfterRestoringSnapshotWithCorruptItemSkipsItAndAvoidsCollision` |

**Audit-status effect (no overclaim):** these close the previously-implicit gaps in
the D (timer/persistence) and E (slots) areas. The D/E verdicts are now
genuinely **already-covered** for restore robustness *including* id generation,
per-item decode sanitation, and slot-name sanitation. No new parity claim beyond
restore/persistence is made; the deferred/divergent/iOS-only surfaces below are
unchanged.

---

## Restore / Persistence Hardening — Pass 2

A second review found that Pass 1's corrupt-snapshot handling was still not
fully robust, and that the ViewModel restore ordering was unexamined. Three
issues, all fixed and pinned by tests.

| # | Risk | Fix | Tests |
|---|---|---|---|
| 1 | **A malformed typed field could still drop the whole snapshot** — `decode()` parsed the entire collection in one `decodeFromString<CollectionDto>`, so a type mismatch in one item (e.g. `durationSeconds:"oops"`) threw before per-item sanitation, dropping valid siblings | `decode()` now parses only the envelope (`JsonObject`/`schemaVersion`/`timers` array) and decodes **each item individually** with `runCatching`; a per-item type mismatch skips that item only. Fully-malformed / non-object JSON still returns empty; decode never throws | `TimerSnapshotCodecTest`: `badDurationTypeInOneItem…`, `badStartEpochType…`, `badPausedRemainingType…`, `badStatusTypeOrUnknownStatus…`, `badSourceMetadataType…`, `fullyMalformedOrNonObjectJsonReturnsEmptyWithoutThrowing` |
| 2 | **Duplicate-id tracking ran before validation** — a corrupt item could reserve an id, then a later valid item with the same id was dropped as a duplicate | id is reserved (`seen.add`) only **after** structural validation succeeds; blank ids never reserve | `TimerSnapshotCodecTest`: `corruptDuplicateFirstThenValidDuplicateSecondRestoresTheValidOne`, `twoValidDuplicatesKeepTheFirst`, `blankIdItemDoesNotAffectALaterValidItem` |
| 3 | **ViewModel restore-ordering race** — restore runs async on `viewModelScope`; an early user intent could mutate default state and then be clobbered by restore (lost update) | `ShootingViewModel` exposes a `ready: StateFlow<Boolean>` (false until restore completes) and `onEvent` ignores intents while not ready | `ShootingViewModelRestoreOrderingTest` (plain-JVM via `Dispatchers.setMain` + `StandardTestDispatcher`): `notReadyUntilRestoreCompletes`, `intentBeforeRestoreCompletesIsIgnored`, `intentAfterRestoreCompletesIsApplied` |

**ViewModel restore ordering (Issue 3 outcome):** the race was **real** (async
restore overwrites calculator/slot state). Fixed with the smallest safe guard —
a readiness flag that gates `onEvent` — and it **is** tested at the JVM level
(the architecture allowed a `StandardTestDispatcher`-driven test without
Robolectric, using the existing `InMemoryTimerStore`). No ViewModel rewrite, no
intent queueing (intents during the sub-second restore window are dropped, not
buffered — acceptable for restore-from-cold-start). The guard gates the whole
intent surface; a future refinement could allow read-only intents (e.g. open
details) during restore, but that is not needed for the MVP.

**Audit-status effect (no overclaim):** corrupt timer-snapshot decoding is now
robust against malformed *typed* fields (not just malformed envelopes), and the
ViewModel restore-ordering race is closed and tested. No parity claim beyond
restore/persistence is added.

---

## Restore / Persistence Hardening — Pass 3

Pass 2 added a `ready` guard but two gaps remained: a throwing store load could
leave the app permanently not-ready, and `ready` was not surfaced to the UI.
Both are now closed.

| # | Risk | Fix | Tests |
|---|---|---|---|
| 1 | **A failing/throwing store load could strand restore** — if `timerStore`/`customStore`/`sessionStore` `load()` threw, the init coroutine could exit before `_ready = true`, leaving `onEvent` inert forever (recoverable only by app restart / data clear) | each store's **load + decode** runs behind its own `runCatching` with a documented fallback (timers→none, custom→empty library, session→defaults) and `_ready = true` is set in a `finally`, so a failed load can never strand the app. Custom films still load **before** session application, so a session referencing a custom film resolves it (or falls back to digital via `CalculatorController` sanitation if absent) | `ShootingViewModelRestoreFailSafeTest` (5 JVM tests via `StandardTestDispatcher`): timer/custom/session each-throws-still-ready-and-usable, all-three-throw, and custom-loads-before-session-apply (valid custom film resolves) |
| 1a | **Catch scope was too wide** (review correction) — the Pass-3 `runCatching` blocks also wrapped application wiring (`timer.restoreFromJson`, `session.restore`, `calc.apply`), so a genuine programmer error there would be silently swallowed, contradicting the stated intent | the `runCatching` now captures only the load/decode result (`timerJson` / `loadedCustomFilms` / `restoredSession`); all application wiring — including `CustomFilmLibrary(...)` construction — runs **outside** the swallowed path, so wiring errors surface as real failures. Fail-safe load behavior and `_ready`-in-`finally` are unchanged | covered by the same 5 `ShootingViewModelRestoreFailSafeTest` cases (still green after the narrowing). No direct "wiring throws" test — see note below |
| 2 | **`ready` not visible in UI** — input during restore was silently ignored with no feedback | `MainActivity` collects `viewModel.ready`; `ShootingScreen` takes a `ready` param and shows a simple blocking *Restoring…* overlay (scrim + label, swallows input) while not ready | not instrumented (see note); the gating behavior is covered by the ViewModel JVM tests |

**Verification scope (no overclaim):** the fail-safe restore behavior is covered
by plain-JVM tests. The UI `ready` wiring (overlay + `MainActivity` collection)
is a minimal, non-pixel change and is **not** covered by an instrumented Compose
test — `connectedAndroidTest` was **not** run this pass. Restore load failures
now fall back safely and the ready state is surfaced to the UI; the overlay's
on-device appearance is unverified.

**Why no direct "wiring error not swallowed" test (1a):** the restore
controllers (`timer`, `session`, `calc`, `customLib`) are constructed internally
by `ShootingViewModel`; the only injectable seam is the three `TimerStore`s.
A store can influence only the load/decode inputs, which are fail-safe by design
(`TimerSnapshotCodec`/`SlotSessionCodec` decode never throws; the custom decode
is caught), so it cannot drive a wiring method to throw. Manufacturing a genuine
wiring exception would require injecting the controllers or a fault hook — an
invasive seam the surgical scope of this pass disallows. The correction is
therefore structural (application wiring is lexically outside the swallowed
`runCatching`), and the five existing fail-safe tests confirm the user-facing
behavior is preserved.

---

## End-to-End Restore + Custom Film Verification — Pass 4

Prior passes proved restore at the codec/controller level. This pass adds
**app-level** (ViewModel ↔ stores ↔ codecs ↔ controllers) round-trip coverage
in `ShootingViewModelEndToEndRestoreTest`: the same `InMemoryTimerStore`
instances (DataStore stand-ins) are shared between a "before" and an "after
relaunch" ViewModel so persisted JSON round-trips through the real
save→load→decode→apply path, driven on a `StandardTestDispatcher` with
`runCurrent()` (no Robolectric). The restore order was audited and is correct:
load/decode → `timer.restoreFromJson` → custom library → id sequencer →
`setCustomFilms` → session restore → `calc.apply` → finally(`ready = true`);
custom films are applied **before** the session so a session's custom-film
reference resolves.

**Coverage counts — 34 end-to-end targets:**

| Bucket | Count | % |
|---|---|---|
| Covered by **existing** tests (ready/guard + store-failure) | 9 | 26.5% |
| Covered by **new** tests (active/completed/slot/custom/identity round-trips) | 23 | 67.6% |
| **Automated total** | **32** | **94.1%** |
| Manual / instrumented-only (Compose UI) | 2 | 5.9% |
| Remaining uncovered | 0 | 0% |

- **New (23):** active-timer restore + usable countdown + no-collision-new-timer + source identity (4); completed-timer restore + Start-again + Remove + identity (4); slot/session — selected slot, trimmed name, base, ND, film, model, target (7); custom film — formula reload, table reload, table-created-formula reload, stays-selected, affects-calc, delete-falls-back (6); custom-film corrected timer identity survives restore (2).
- **Existing (9):** `ShootingViewModelRestoreOrderingTest` (ready false before / intents ignored / ready true after = 4 of group 6) + `ShootingViewModelRestoreFailSafeTest` (timer/custom/session/multiple failure + always-ready = 5 of group 7).
- **Manual-only (2):** "UI receives ready state" and "ShootingScreen shows a loading indicator while not ready" — these are Compose-UI assertions requiring instrumentation. The `ready` param + `RestoringOverlay` exist in code and were observed **not to trap** the UI on device (overlay cleared, controls interactive), but the overlay being *displayed during* the sub-second restore window was not directly captured.

**On-device check (emulator-5554):** installed the debug APK, launched, force-stopped, relaunched. The app rendered the real shooting screen and, across the kill/relaunch, **restored the selected preset film (Fomapan 100 Classic), the selected model (Official FOMA table), ND stops (8), and the reciprocity result (Table-derived, 8.5s)** via real DataStore, with no crash and no trapped "Restoring…" overlay. On-device custom-film and running-timer restore were **not** exercised this pass (no such state present); they are covered by the JVM round-trip tests above.

**No blocker found.** All eight new round-trip tests passed on the first run, so no restore/custom fix was required this pass.

---

## Background Timer Completion — Pass 5

Before this pass, completion was **in-process only**: the `viewModelScope` tick
loop posted the notification, so once the app process was no longer alive
(backgrounded-and-reclaimed or killed) completion never fired. This pass adds a
**scheduled completion alarm** behind a testable abstraction.

- **`TimerCompletionScheduler`** (`:app`) — `schedule(snapshot,title,subtitle)` /
  `cancel(id)` / `cancelAll(ids)`. `NoOpTimerCompletionScheduler` is the default
  and the JVM-test stand-in; `:core` stays pure Kotlin.
- **`AndroidTimerCompletionScheduler`** — AlarmManager + `CompletionAlarmReceiver`
  (registered in the manifest, `exported=false`). Stable timer id is the
  PendingIntent request key; only immutable id/title/subtitle is encoded, so the
  receiver never reads live state. **Exactness is honestly bounded:** exact
  (`setExactAndAllowWhileIdle`) on API < 31; on API 31+ exact only if
  `canScheduleExactAlarms()` is already true, otherwise **best-effort inexact**
  `setAndAllowWhileIdle` (this pass does not request `SCHEDULE_EXACT_ALARM`).
- **`ShootingViewModel.syncSchedules()`** reconciles alarms after every timer
  event and after restore: cancels alarms for no-longer-running timers,
  (re)schedules running ones (idempotent — same id replaces, so no duplicates),
  and is wrapped so a scheduler failure cannot break the timer workflow.
- **Relaunch policy:** the core restore reconciles an overdue running timer to
  *completed* (silently); on relaunch we do **not** re-post its completion —
  the scheduled alarm is the background-delivery path, and re-posting on every
  launch would double-notify. Pending (future) running timers are re-scheduled.

**Background reliability targets: 5**
```
Covered before this pass: 1/5 = 20%   (in-process completion notification)
Covered after this pass:  4/5 = 80%
Automated coverage:        4/5 = 80%   (scheduler contract via fake, JVM)
Manual/device-only:        1/5 = 20%   (actual post-kill alarm delivery timing)
Remaining follow-up:       1/5 = 20%   (exact-alarm permission flow / foreground service)
```
- Target 1 (schedule at expectedCompletionAt) — ✅ automated + on-device alarm registration confirmed.
- Target 2 (cancel on pause/remove/completion) — ✅ automated.
- Target 3 (relaunch reconciles overdue) — ✅ automated.
- Target 4 (permission / exact-alarm fallback is safe) — ✅ code falls back to inexact and is wrapped against failure; the *exact-alarm permission flow itself* is the deferred follow-up.
- Target 5 (scheduler behavior covered by JVM tests) — ✅ `ShootingViewModelSchedulingTest` (12 tests) via a fake.

**Tests:** `ShootingViewModelSchedulingTest` — 12 JVM tests (start schedules; pause/remove cancel; resume reschedules; completed not scheduled; Start-again fresh id; restore pending schedules; restore overdue reconciles + not scheduled; identity immutable across rename; custom-film corrected identity; scheduler-failure no-crash; no duplicate after restore round-trip).

**On-device check (emulator-5554, API 37):** installed the new APK, started an 8.5s
adjusted timer; `dumpsys alarm` showed a registered `RTC_WAKEUP` alarm with action
`com.sangwook.ptimer.TIMER_COMPLETION` and a broadcast PendingIntent. On completion
(app foreground), a notification was posted (channel `ptimer_completion`, title
"Timer done"), and exactly one completion alarm remained — matching the one
still-running restored timer (consistent with cancel-on-completion +
schedule-for-running). **Not verified on device:** actual alarm firing after
process death — API 37 uses the inexact path (no `SCHEDULE_EXACT_ALARM`), whose
delivery is delayed/opportunistic, and `am force-stop` cancels alarms so is not a
faithful kill test. `connectedAndroidTest` was **not** run (no instrumented tests
exist). The AlarmManager/receiver code is **assemble-only** (framework, not
JVM-unit-tested); its logic is exercised through the fake scheduler.

---

## Background Completion Cleanup — Pass 6

Three small follow-ups from review of the Pass-5 scheduler (no exact-alarm /
foreground work in this pass).

1. **Force-stop wording corrected.** The `TimerCompletionScheduler` doc no longer
   implies alarms survive force-stop. Precise framing: completion can still be
   delivered when the app is backgrounded or its process is later reclaimed; an
   explicit **force-stop cancels the app's pending alarms**, so delivery then
   resumes only on next launch — force-stop is **not** a supported delivery
   guarantee. (Exactness still bounded: exact on API < 31, best-effort inexact
   `setAndAllowWhileIdle` on API 31+ without `SCHEDULE_EXACT_ALARM`.)

2. **Completion notification preserves source identity.** The scheduled alarm
   already encoded title **and** subtitle, but the notification displayed title
   only. `TimerNotifier.postCompletion` now takes an optional `subtitle`;
   `AndroidTimerNotifier` shows the timer **identity as the title** and the
   **source line as the body** (e.g. "Camera 1 · Fomapan 100 Classic" /
   "Adjusted Shutter · 8.5s"); `CompletionAlarmReceiver` passes `EXTRA_SUBTITLE`
   through and the in-process path passes `subtitleOf(id)`. So a corrected /
   custom / limited-guidance source line is not lost when a timer completes via
   the alarm receiver. Covered by `ShootingViewModelSchedulingTest` (the
   custom-film corrected case now asserts the scheduled subtitle carries
   "Corrected Exposure") and confirmed on-device.

3. **Ongoing-notification reconciliation policy (documented; no code change).**
   PTIMER supports multiple running timers but the notifier exposes only a single
   global ongoing notification (`showOngoing`/`clearOngoing`, one id). Policy:
   - `CompletionAlarmReceiver` posts only the **completed** timer's done
     notification from immutable extras; it deliberately does **not** call
     `clearOngoing` (that would hide a still-running sibling timer).
   - Ongoing-notification reconciliation remains tied to live ViewModel state
     (`ShootingViewModel.updateOngoing` → representative running timer) and runs
     while the app is alive. The receiver does **not** reconcile ongoing
     notifications. Per-timer ongoing notifications and a foreground service that
     reconciles them in the background remain a later notification/foreground
     pass — not claimed here.

**On-device check (emulator-5554, API 37):** after allowing notifications, started
the adjusted-shutter timer; on completion the notification showed
`title="Camera 1 · Fomapan 100 Classic"` and `text="Adjusted Shutter · 8.5s"`
(`dumpsys notification`), confirming the identity + source-line display.
`connectedAndroidTest` was **not** run.

---

## Exact Alarm Permission — Pass 7

Pass 5 used exact alarms only when already permitted and never requested the
permission, so on API 31+ it always fell to the inexact path. This pass adds the
exact-alarm permission policy + a user path, closing the enumerated
background-reliability target set.

**Policy decision:** declare `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM` —
eligibility/Play-policy risk) and request it via the system settings deep-link.
Exact is used when permitted; otherwise the app stays on the best-effort inexact
path. Using `SCHEDULE_EXACT_ALARM` requires a Play Console exact-alarm
declaration at publish time — a deliberate, documented MVP decision; if that
becomes a blocker the permission can be dropped and the app remains on inexact.

- **`ExactAlarmPolicy`** (pure, JVM-tested) — `decide(sdkInt, canScheduleExact,
  promptDismissed)` → `shouldUseExact` / `shouldShowPermissionPrompt` /
  `fallbackMode`. API < 31 → exact, no prompt; API 31+ permitted → exact, no
  prompt; API 31+ denied → inexact + offer prompt (until dismissed).
- **`ExactAlarmAvailability`** — interface (`AlwaysExactAlarmAvailability`
  default/test stand-in; `AndroidExactAlarmAvailability` queries
  `canScheduleExactAlarms()`), injected into the ViewModel.
- **`AndroidTimerCompletionScheduler`** now routes its exact/inexact choice
  through `ExactAlarmPolicy`. Manifest declares `SCHEDULE_EXACT_ALARM`.
- **In-app prompt:** `ShootingViewModel.exactAlarmPrompt` is true only when a
  timer is running, exact is not permitted, and the user has not dismissed it.
  `ShootingScreen` shows a compact dismissible notice ("For more reliable
  background timer alerts, allow exact alarms." / "Open settings" / "Not now");
  `MainActivity` opens `Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. Timer use
  is never blocked; the notice does not reappear after dismissal.

**Background reliability targets: 5**
```
Covered before this pass: 4/5 = 80%
Covered after this pass:  5/5 = 100%
Automated coverage:       5/5 = 100%
Manual/device-only:       0/5 = 0%    (target 4 ALSO confirmed on device, both paths)
Remaining follow-up:      0/5 = 0%    (within this 5-target set)
```
- Target 1 schedule, 2 cancel, 3 relaunch-reconcile, 5 JVM coverage — unchanged ✅.
- Target 4 (permission / exact-alarm fallback safe) — ✅ closed: exact-when-permitted, inexact fallback, user request path, pure policy JVM-tested, both paths confirmed on device.

**Beyond this 5-target set (still open, not claimed closed):** a **foreground
service** for guaranteed delivery, and a **faithful post-process-death delivery
test** (this pass verified exact/inexact *path selection* + alarm *registration*
on device, not actual firing after the process is gone). Force-stop still cancels
alarms and is not a supported guarantee.

**Tests (+8):** `ExactAlarmPolicyTest` (4 — below-31 exact, 31+ permitted exact,
31+ denied inexact+prompt, denied+dismissed no-prompt) and
`ShootingViewModelExactAlarmPromptTest` (4 — no prompt without a running timer,
prompt when running+unavailable, no prompt when available, dismissal prevents
re-nagging). Targets 1/2/3/6/7/8 from the scheduler set remain covered by the
existing `ShootingViewModelSchedulingTest`.

**On-device check (emulator-5554, API 37):** with `appops … SCHEDULE_EXACT_ALARM
deny`, starting a timer showed the notice and registered the (inexact) alarm with
no crash; with `… allow`, a running timer showed **no** notice and registered the
alarm (exact path selected). **Not verified:** actual alarm firing after process
death; `connectedAndroidTest` was **not** run; the AlarmManager/receiver +
settings-intent code remain assemble-only (their decision logic is JVM-tested via
`ExactAlarmPolicy` and the prompt tests).

---

## Exact Alarm Settings Return — Pass 8

Pass 7 read exact availability only on timer events, so granting the permission
in settings and returning did not refresh the notice or upgrade already-running
timers to the exact path until the next timer action. This pass closes that gap.

- **`ShootingViewModel.refreshExactAlarmAvailability()`** re-reads
  `ExactAlarmAvailability`; if it changed since the last observation it runs
  `syncSchedules()` (reschedules running timers through the now-current
  exact/inexact policy — idempotent, so unchanged availability does not
  reschedule) and refreshes the notice. A fresh **grant** also clears the
  dismissed-notice suppression so a later denial can prompt again.
- **`MainActivity`** calls it from `LifecycleEventEffect(ON_RESUME)`, i.e. on
  return from the exact-alarm settings screen (and any resume). Guarded until
  restore completes.
- **Dismissed-state rule:** dismissal suppresses the notice while exact stays
  denied; a grant clears suppression and hides the notice; a later
  denied-while-running can prompt again.

**Exact-alarm settings-return targets: 8**
```
Covered before this pass: 2/8 = 25%   (targets 1 & 8 — prompt visibility only)
Covered after this pass:  8/8 = 100%
Automated coverage:       8/8 = 100%
Manual/device-only:       0/8 = 0%    (round-trip ALSO confirmed on device)
Remaining follow-up:      0/8 = 0%    (within this set)
```
- 1 denied schedules inexact + prompt, 8 no-prompt-without-running — already covered.
- 2 grant→refresh hides prompt, 3 grant→refresh reschedules, 4 still-denied→no
  reschedule, 5 dismissed+denied→no re-nag, 6 dismissed+granted→hidden+suppression
  cleared, 7 granted→denied→fallback+prompt — added this pass.

**Tests (+6):** `ShootingViewModelExactAlarmPromptTest` extended from 4 to 10
(adds the six settings-return cases above, using a flippable `MutableExact`
availability and a `CountingScheduler` to assert reschedule counts).

**On-device check (emulator-5554, API 37):** `appops … SCHEDULE_EXACT_ALARM deny`,
launch, start timer → notice shown + (inexact) alarm registered. Then HOME, grant
via `appops … allow` while backgrounded, resume → `ON_RESUME` fired
`refreshExactAlarmAvailability`: the notice cleared, the alarm stayed registered
(rescheduled; an exact-alarm clock icon appeared in the status bar), no crash.
This used an `appops` toggle while backgrounded + resume (not the system settings
UI navigation). **Not verified:** actual alarm firing after process death.
`connectedAndroidTest` was **not** run.

---

## Not implemented, and why (deferred / divergent / iOS-only)

| Area | iOS tests | Why not an MVP blocker |
|---|---|---|
| Fully-guaranteed background completion (exact-alarm permission flow + foreground service) | `TimerManagerNotificationSchedulingTests`, `…CompletionAlertTests` | Android now schedules a **best-effort completion alarm** (`AndroidTimerCompletionScheduler`: exact on API < 31, inexact `setAndAllowWhileIdle` on API 31+ where `SCHEDULE_EXACT_ALARM` is not requested) plus the in-process notification. An exact-alarm permission flow and/or a foreground service for guaranteed, OEM-proof delivery remain post-MVP (see *Background Timer Completion — Pass 5*). |
| 1/3-stop fractional-ND exposure mode (PTIMER-79) | `ExposureScaleTests`, `ExposureScaleModeUITests`, `OneThirdStopExposureModeTests` (~40) | Android base/ND are whole-stop steppers by design (Compose has no iOS-equivalent wheel base component). Full-stop / camera-ladder snap **is** covered via `exposure-golden.json`. **android-replacement.** |
| Custom-film **editor UI** suite (`[editor-ui]` ~150) — token editor, anchored-formula form, input modes, live-check, reset/revert, preview graph, inline validation, save-disabled reasons | `CustomFilmEditor*Tests` | Android ships a simpler custom-film create/edit flow (deliberately demoted in priority per owner). Domain validation/sanitation **is** covered. **follow-up / android-replacement.** |
| Reciprocity **Details graph** + Source-reference/Guidance-boundary section split + secondary-guidance formatter + stop-signal/not-recommended vocabulary + source-reference row sorting | `*GraphPresenterTests`, `Converted/GuardedFormulaPresentation*`, `NotRecommendedBoundary*`, `ReciprocitySecondaryGuidance*`, `SourceReferenceRowSorting*` | Android `DetailsPresenter` is a reduced flat-row model (source/model/basis/corrected/range + fitted comparison), no graph. Region/basis **policy** is covered in `core`. **follow-up / android-replacement.** |
| Lock-screen / ActivityKit / RecordReplay / BottomSheet dock-shell-theme-layout | `LockScreenTimerCoordinatorTests`, `B4TimerLifecycleBaselineTests`, `BottomSheetWorkspace*`, `RecordReplay*`, `PTimerComponentThemeTests`, `ResultValueRowTests`, `TimerActionMetricsTests` | iOS-only surfaces. Representative-timer **selection** logic is covered (`RepresentativeTimerSelector`). **ios-only.** |
| Coarse long-duration formatter (≈mo/≈y) | `…FormatReciprocityDurationCoarse…` | Android uses simpler remaining/"Ends HH:mm:ss" formatting in the MVP. **follow-up.** |

---

## Coverage summary by area

| Area | iOS tests (≈) | Protected behavior parity | Android tests |
|---|---|---|---|
| A — Exposure core | 87 | ✅ full-stop/camera-ladder/snap/format via golden fixture; 1/3-stop wheel = android-replacement | `ExposureCoreTest`, `SharedFixtureGoldenTest` (core) |
| B — Reciprocity policy | ~210 | ✅ formula / log-log table / threshold+limited / OLS fitter / no-shortening guard / basis & confidence mapping | `ReciprocityCoreTest`, `…PolicyTest`, `…FitterTest`, `CatalogPerFilmParityTest`, `ConfidencePresentationTest` (core) |
| C — Catalog + custom domain | ~190 | ✅ 37-film load/shape/provenance/per-film params; ✅ custom domain sanitation; editor-UI = follow-up | `CatalogCoreTest`, `CatalogPerFilmParityTest`, `CustomFilmTest` |
| D — Timer + persistence | ~110 | ✅ state machine / pause-resume-complete / restore / ordering / clone / identity; notifications = follow-up; lock-screen/RecordReplay = ios-only | `TimerStateTest`, `TimerRuntimeTest`, `TimerSnapshotCodecTest`, `TimerWorkspaceControllerTest`, `RepresentativeTimerSelectorTest` |
| E — Slots + Target + Film | ~140 | ✅ 4-slot isolation / rename / per-slot target & restore / film-selection / start-action model | `CalculatorControllerTest`, `SlotSessionCodecTest`, slot/session tests |
| F — Presentation | ~120 | ✅ region/basis policy + representative selection; graph/vocabulary/dock = follow-up/ios-only | covered via core policy + selector tests |

---

# Appendix — per-test intent and parity (by area)

Each file carries a one-line **[verdict]** that applies to every test in it
unless an inline tag overrides. `intent` is the protected behavior the iOS
test guards. See `PTIMER-146-android-test-intent-map.md` for the area-level
companion and the user-test corrections to the start-action model.

## A — Exposure core (87 tests)

**[verdict]** ✅ **already-covered** for full-stop / camera-ladder / snap /
doubling / format behavior — pinned by Android `ExposureCoreTest` and the
cross-platform `SharedFixtureGoldenTest` (`exposure-golden.json`).
Files `ExposureScaleTests`, `ExposureScaleModeUITests`,
`OneThirdStopExposureModeTests` protect the iOS **1/3-stop fractional-ND**
wheel mode (PTIMER-79) → **android-replacement** (Android uses whole-stop
ND steppers; only the whole-stop path is in scope). The coarse
`…DurationCoarse` year/month formatter → **follow-up**.

| iOS file · test | intent / invariant |
|---|---|
| ExposureCalculatorTests · testCalculateRepresentativeExposureCases  | calculate() + parseBaseShutter() produce correct result/base/stop for representative cases: 1/30+6→2, 1/125+3→1/15, 0.5+10→512 |
| ExposureCalculatorTests · testStopBasedCalculationMatchesRepresentativeCases  | calculate(seconds:stop:) correctness: 1/30+6→2, 1/8+10→128, 1+0→1 |
| ExposureCalculatorTests · testCalculateRejectsNonPositiveInput  | parseBaseShutter("0") throws .nonPositiveBaseShutter |
| ExposureCalculatorTests · testCalculateRejectsEmptyAndInvalidInputs  | parseBaseShutter("")→.emptyBaseShutter, "abc"→.invalidBaseShutter, calculate(stop:-1)→.nonPositiveND |
| ExposureCalculatorTests · testParseBaseShutterSupportsFractionAndSecondsSuffix  | parse "1/30"→1/30, "2s"→2, "0.5"→0.5 |
| ExposureCalculatorTests · testStopBasedInterfaceHandlesLargeStops  | 1s+20stops→1,048,576 |
| ExposureCalculatorTests · testFormatShutterReturnsExpectedReadableStrings  | formatShutter: 2→"2s", 2.1→"2.1s", 1/30→"1/30s", 1/125→"1/125s" |
| ExposureCalculatorTests · testFormatTimeDisplayReturnsExpectedReadableStrings  | formatTimeDisplay primary/secondary across ranges: 0/-3→"0s", sub-min decimals, mm:ss, hh:mm:ss, day/month/year units, fractional-seconds clock (128.25→"02:08.250") |
| ExposureCalculatorTests · testSnapToFullStopClampsToCanonicalBounds  | 1/8000+0stops stays 1/8000 (clamp to canonical bounds) |
| ExposureCalculatorTests · testCameraFullStopBehaviorPreservesFifteenAndThirtySeconds  | camera-scale snap: 1s+3→8, +4→15, +5→30 |
| ExposureCalculatorTests · testLongExposureUsesExactDoublingBeyondThirtySeconds  | beyond 30s switches to exact doubling: 1/30+10→30,+11→64; 1s+5→30,+6→64,+7→128,+8→256 |
| ExposureCalculatorTests · test24StopFromOneSecond  | 1s+24stops→2^24 (no snap at high stops) |
| ExposureCalculatorTests · testLargeStopDoublingSequence  | stops 7..12 from 1s each exactly double the previous |
| ExposureCalculatorTests · testSubSecondToLargeStopChain  | 1/30+24stops→524,288 |
| ExposureCalculationAccuracyTests · testFullStopMatrixFromOneThirtiethMatchesCameraScale  | full-stop matrix 1/30 + stops 1..10 matches camera ladder (1/15,1/8,1/4,1/2,1,2,4,8,15,30) |
| ExposureCalculationAccuracyTests · testCriticalCaseOneEighthPlusTenStopsReturnsOneHundredTwentyEightSeconds  | 1/8+10stops→128 (critical case) |
| ExposureCalculationAccuracyTests · testBoundaryValuesClampToCanonicalRange  | 1/10000+0→1/8000 (clamp to fastest canonical) |
| ExposureCalculationAccuracyTests · testOneSecondTransitionsFromCameraStopsToExactDoubling  | camera-stops→exact-doubling transition: 1s+3→8,+4→15,+5→30,+6→64,+7→128,+20→1,048,576; 1/30+10→30,+11→64 |
| ExposureCalculationAccuracyTests · testNoIntermediateSnapDriftAbove30  | above 30s no snap drift: result(1/30,12) == result(1/30,11)*2 |
| ExposureCalculationAccuracyTests · testDoesNotSnapToNearestPowerOfTwo  | 1/30+11→64 and result < raw(base·2^11); does not snap up to nearest power of two |
| ExposureCalculationAccuracyTests · testHighStopDoesNotSnap  | 1s+24→2^24 (high stop unsnapped) |
| ExposureCalculationAccuracyTests · testResultMonotonicIncreaseAcrossStops  | result strictly increases for stops 0..15 from 1/30 |
| ExposureCalculationAccuracyTests · testExactPowerOfTwoSequenceFromOneSecond  | from 1s, stops 7..15 each exactly double previous |
| ExposureCalculationAccuracyTests · testInverseConsistencyUsingReconstructedStops  | log2(result/base) reconstructs stop for unsnapped cases (1,6),(1,10),(1,20),(1/8,10) |
| ExposureCalculationAccuracyTests · testInverseConsistencyAtSnapBoundary  | at snap boundary 1/30+10→30, reconstructed stop is in (9.75,10) i.e. slightly below 10 due to snap |
| ExposureScaleTests · testDefaultScaleIsOneThirdStop  | ExposureScale.default.mode == .oneThirdStop |
| ExposureScaleTests · testFullStopShutterLadderMatchesShippingFullStopSpeeds  | .fullStop shutterSteps equal ExposureCalculator.fullStopShutterSpeeds (count + values within epsilon) |
| ExposureScaleTests · testFullStopNDLadderSpansZeroThroughThirty  | .fullStop ndSteps = 0..30 whole stops, all isWholeStop with matching wholeStops |
| ExposureScaleTests · testFullStopModeStopsPerStepIsOne  | ExposureScaleMode.fullStop.stopsPerStep == 1.0 |
| ExposureScaleTests · testOneThirdStopModeStopsPerStepIsOneThird  | ExposureScaleMode.oneThirdStop.stopsPerStep == 1/3 |
| ExposureScaleTests · testOneThirdStopShutterLadderEmbedsFullStopBoundaries  | 1/3-stop shutter ladder contains every full-stop shutter value |
| ExposureScaleTests · testOneThirdStopShutterLadderDensifiesByExactlyTwoStepsBetweenFullStops  | 1/3-stop ladder count == fullStopCount*3-2 (2 inserted steps per gap) |
| ExposureScaleTests · testOneThirdStopShutterLadderUsesGeometricMeanRatios  | 1/3-stop neighbors of 1/30 are 1/30·2^(1/3) and 1/30·2^(2/3) |
| ExposureScaleTests · testOneThirdStopNDLadderIsWholeStopOnly  | 1/3-stop ndSteps = 31 entries (0..30), all whole-stop, identical to fullStop ND ladder |
| ExposureScaleTests · testNDStepWholeStopsRoundTripsForIntegerValues  | NDStep(0/3) isWholeStop with wholeStops 0/3 |
| ExposureScaleTests · testNDStepWholeStopsIsNilForFractionalValues  | NDStep(1/3,2/3,1+1/3) not whole-stop, wholeStops nil |
| ExposureScaleTests · testNDStepFactoryProducesWholeStopEntry  | ExposureScale.ndStep(forWholeStops:6) → stops 6, wholeStops 6 |
| ExposureScaleTests · testCalculatorModelDefaultsToOneThirdStopScale  | CalculatorModel default scale .oneThirdStop; pickerShutterStepSeconds count = 1/3 ladder; pickerWholeNDStops = 0..30 |
| ExposureScaleTests · testCalculatorModelAcceptsReservedFullStopScale  | CalculatorModel(exposureScale:.fullStop) yields fullStop pickers; default ctor stays .oneThirdStop (per-instance scale) |
| ExposureScaleTests · testCalculatorModelStaticShutterSpeedsRemainFullStopForLegacyCallers  | CalculatorModel.shutterSpeeds static == fullStopShutterSpeeds (legacy/persistence sanitizer) |
| ExposureScaleTests · testFullStopScaleDoesNotChangeCalculatorOutput  | engine sanity unchanged: 1/30+6→2, 1+5→30, 1+6→64 |
| ExposureScaleModeUITests · testDefaultViewModelExposesOneThirdStopShutterAndWholeStopND  | VM default scale .oneThirdStop; shutter picker = 1/3 ladder count; ND picker 31 whole stops (0..30), no fractional; pickerWholeNDStops 0..30 |
| ExposureScaleModeUITests · testShippingNDPickerOptionsAroundSevenAreWholeStopsOnly  | ND picker labels around 7 are 6,7,8 (no "7 1/3"/"7 2/3", no "/" in any label) |
| ExposureScaleModeUITests · testEngineFractionalShutterInOneThirdStopDoesNotSnap  | in .oneThirdStop, fractional base shutter + whole ND applies exact factor, no snap (incl ND=0 not collapsing to 1/30) |
| ExposureScaleModeUITests · testEngineWholeStopCallsStillSnapInReservedFullStopMode  | legacy stop: overload and explicit .fullStop ndStep overload still snap: 1/30+6→2 |
| ExposureScaleModeUITests · testViewModelReservedFractionalPathsCalculateWithoutSnapping  | VM reserved fractional paths: fractional base+ND0 passes through; 1s+ND(1/3)→2^(1/3), ndStep preserved |
| ExposureScaleModeUITests · testDefaultShutterPickerKeepsAllSubSecondValuesAsFractions  | camera labels: 1/30 1/3-neighbors→"1/25","1/20"; sub-1s anchors stay 1/N ("1/3","1/2.5","1/2","1/1.6","1/1.3"); ≥1s decimal ("1s","1.3s","1.6s") |
| ExposureScaleModeUITests · testDefaultShutterLabelSequenceMatchesNikonLadderAroundOneSecond  | 23-row slow→fast window around 1s matches verbatim Nikon Z7 label sequence (15s..1/10) |
| ExposureScaleModeUITests · testDefaultShutterLadderIndexAdvanceMatchesStopArithmetic  | 1/10 + 9 ladder positions (=3 whole stops) lands on "1/1.3" |
| ExposureScaleModeUITests · testDefaultShutterLabelsContainNoDecimalSecondsBelowOne  | every sub-1s ladder label is "1/..." fraction with no "s" suffix |
| ExposureScaleModeUITests · testFractionalNDStepWriteEmitsObjectWillChange  | writing fractional NDStep(1/3) emits objectWillChange (>0) for SwiftUI redraw |
| ExposureScaleModeUITests · testFormatNDStopRendersWholeAndReservedFractionalValues  | formatNDStop: 0→"0",1→"1",6→"6",1/3→"1/3",2/3→"2/3",1+1/3→"1 1/3",1+2/3→"1 2/3" |
| ExposureScaleModeUITests · testUpdateLiveNDStepDrivesEffectiveCalculationWithoutMutatingCommitted  | updateLiveNDStep(1/3) drives result=1/30·2^(1/3) while committed ndStep stays NDStep(0) |
| ExposureScaleModeUITests · testRelaunchRestoresScaleAndNDFromSnapshot  | snapshot w/ scale+ndStopThirds=1 restores fractional NDStep; legacy snapshot (no scale, ndStop=4) restores .oneThirdStop + ndStop 4 |
| ExposureScaleModeUITests · testRelaunchDecodesLegacyJSONWithoutScaleModeFieldAsOneThirdStop  | raw JSON lacking exposureScaleMode → snapshot.exposureScaleMode nil, restoredScaleMode .oneThirdStop |
| ExposureScaleModeUITests · testResetFilmModeWorkingContextRestoresShippingOneThirdStop  | reserved fractional ND drift makes canReset true; reset clears film/ND → scale .oneThirdStop, ndStop 0, ndStep 0, canReset false |
| OneThirdStopExposureModeTests · testFractionalNDStepDoesNotSnapToFullStopLadder  | calculate(ndStep:) fractional: 0→×1,1/3→×2^(1/3),2/3→×2^(2/3); 1/3 result ≠ 1/30 and ≠ 1/15 (no snap) |
| OneThirdStopExposureModeTests · testWholeStopNDStepPreservesLegacySnapToFullStopBehavior  | NDStep(6)/NDStep(5) overload equals legacy stop: overload byte-for-byte (1/30+6, 1+5) |
| OneThirdStopExposureModeTests · testFractionalNDStepRejectsNonPositiveInputsLikeWholeStopOverload  | calculate(ndStep:) rejects base 0→.nonPositiveBaseShutter, ND -1/3→.nonPositiveND |
| OneThirdStopExposureModeTests · testExposureCalculationResultStopAccessorRoundsFractionalToNearestInt  | result.stop rounds NDStep(1/3)→0; ndStep.stops stays 1/3, wholeStops nil (canonical identity is ndStep) |
| OneThirdStopExposureModeTests · testCalculatorModelOnReservedFractionalNDPathDoesNotSnap  | CalculatorModel (.oneThirdStop) ndStep=1/3 → result 1/30·2^(1/3), ndStep preserved, wholeStops nil |
| OneThirdStopExposureModeTests · testCalculatorModelReservedFullStopScaleStillSnaps  | CalculatorModel(.fullStop) ndStop=6 → result 2, ndStep NDStep(6), stop 6 (snap retained) |
| OneThirdStopExposureModeTests · testCalculatorModelScaleModeFlipReSnapsCommittedNDOntoActiveLadder  | flipping model scale 1/3→fullStop collapses fractional ND(1/3) onto whole stop (wholeStops 0) |
| OneThirdStopExposureModeTests · testViewModelDefaultScaleModeIsOneThirdStop  | VM default .oneThirdStop; whole-stop 1/30+ND6 → 1/30·2^6, ndStep NDStep(6) |
| OneThirdStopExposureModeTests · testViewModelReservedFractionalNDPathRoutesIntoCalculation  | VM ndStep=2/3 → result 1/30·2^(2/3), ndStep preserved |
| OneThirdStopExposureModeTests · testViewModelReservedFractionalNDTimerDurationMatchesResult  | VM 1s+ND(1/3) startTimer → timer.duration == 2^(1/3) (not truncated) |
| OneThirdStopExposureModeTests · testViewModelReservedFractionalNDTimerLabelPreservesFraction  | timer basisSummary (and name for 1/3) retains fractional ND label "1/3"/"1 2/3" |
| OneThirdStopExposureModeTests · testPersistedSnapshotEncodesReservedFractionalAndWholeStopND  | fractional ND saves via ndStopThirds=1 (ndStop nil, scale nil); whole ND6 saves via ndStop=6 (ndStopThirds nil) |
| OneThirdStopExposureModeTests · testRelaunchRestoresNDFromThirdStopCountOrLegacyInteger  | snapshot ndStopThirds=2 → NDStep.fromThirdStopCount(2); legacy ndStop=4 → NDStep(4) + ndStop 4 |
| OneThirdStopExposureModeTests · testRelaunchDecodesPTIMER79JSONPayloadWithoutThirdStopField  | raw PTIMER-79 JSON (ndStop=4, no ndStopThirds) → ndStop 4, ndStopThirds nil, restoredNDStep NDStep(4) |
| ExposureCalculatorViewModelFormatTests · testCoarseLongDurationFormatterSuppressesSubdayNoiseForDayScaleValues  | formatReciprocityDurationCoarse: 1d boundary→"1d", <1d delegates to fine formatter, 1-29d raw "Nd", ≥30d coarsens to ≈mo/≈y (e.g. 33554432→"≈1y", 24099248→"≈9mo 8d", →"≈229y","≈1610y") |
| ExposureCalculatorViewModelFormatTests · testCanStartTimerDependsOnValidCalculationInputs  | canStartTimer true with valid base 1/30 + ND6 |
| ExposureCalculatorViewModelFormatTests · testFormatTimerClockUsesLeadingZeroMinutesAndSeconds  | formatTimerClock: 0/5/59→"Ns", 60→"01:00", 65→"01:05", 3599→"59:59", 3600→"01:00:00", day/mo/yr units |
| ExposureCalculatorViewModelFormatTests · testFormatTimerClockClampsSubsecondAndNegativeValuesToZero  | formatTimerClock 0.9→"0.9s", -3→"0s" |
| ExposureCalculatorViewModelFormatTests · testFormatTimeDisplayAlwaysShowsRawSecondsAndClock  | formatTimeDisplay primary clock + secondary raw seconds: 0/-3→"0s", 5→"5s", 128→("02:08","128s") |
| ExposureCalculatorViewModelFormatTests · testFormatTimeDisplayBoundaryCases  | formatTimeDisplay boundaries 0..year: sub-min decimals, 60→01:00/60s, 3599/3600, 86399/86400 day rollover, month/year units |
| ExposureCalculatorViewModelFormatTests · testFormatTimeDisplayPrecisionPolicy  | precision: 128.25→"02:08.250", 12.345→"12.345s", 0.033→"0.033s" |
| ExposureCalculatorViewModelFormatTests · testTimerDisplayHandlesLargeDurationsInReadableFormat  | formatTimeDisplay 2592000→"1mo 00:00:00", 31536000→"1y 00:00:00" |
| ExposureCalculatorViewModelFormatTests · testTimerDisplayPrecisionDoesNotShowExcessiveDecimals  | secondary: 128→"128s" (no ".000"), 21.158→"21.158s" |
| ExposureCalculatorViewModelFormatTests · testFormatDateTimeAndTimerContextSemanticsIncludeDate  | timerTimeContext: running→"Ends <date>", paused→"Paused <date>", completed→"Completed <date> · just now" |
| ExposureCalculatorViewModelFormatTests · testNDStopSelectionUpdatesCalculationImmediately  | (fullStop) ndStop 6→result 2, then 10→30 recalculated immediately |
| ExposureCalculatorViewModelFormatTests · testLiveNDStopPreviewFeedsCalculationBeforeSettledSelection  | updateLiveNDStop(10) over committed 6 → result stop 10, 30s before settle |
| ExposureCalculatorViewModelFormatTests · testLiveBaseShutterPreviewFeedsCalculationBeforeSettledSelection  | updateLiveBaseShutter(1/15) → result base 1/15, stop 6, 4s |
| ExposureCalculatorViewModelFormatTests · testSettledNDStopClearsMatchingLivePreview  | after settling ndStop=10 then clearLiveNDStopPreview, result stays stop10/30s |
| ExposureCalculatorViewModelFormatTests · testSettledBaseShutterClearsMatchingLivePreview  | after settling base 1/15 then clearLiveBaseShutterPreview, result stays 1/15/stop6/4s |
| SharedFixtureGoldenTests · testExposureGoldenFixtureCasesMatchCalculator  | shared exposure-golden.json: fixture fullStop ladder matches calculator ladder; each case base+ndStops→expectedCalculatedSeconds within tolerance (cross-platform parity gate) |
| SharedFixtureGoldenTests · testLaunchCatalogMatchesSharedFixtureExpectations  | shared catalog-validation-cases.json: LaunchPresetFilmCatalog film count, canonicalStockName order, and ids match fixture expectations |
## B — Reciprocity policy (~210 tests)

**[verdict]** ✅ **already-covered** for the protected policy core: formula
(modified-Schwarzschild) evaluation, log-log table interpolation, the OLS
power-law fitter (inspection-only), the no-shortening guard, the policy
evaluator order (formula→table→threshold→limited→unsupported), region/basis
classification, and the confidence-presentation mapping with its constrained
vocabulary. Pinned by core `ReciprocityCoreTest`, `…PolicyTest`,
`…FitterTest`, `ConfidencePresentationTest`, and the new
`CatalogPerFilmParityTest`. Rows tagged `[presentation]` exercise the iOS
Details **graph / vocabulary / source-reference** surfaces → **follow-up /
android-replacement** (Android Details is a reduced flat-row model); their
underlying numeric/basis claims are covered by the policy tests above.
`…PerformanceTests` (XCTMeasure) → **ios-only** (no perf harness on Android).

Recorded intent (iOS file · test — intent):

- AppDerivedFormulaAlternateTests · testAcceptedFilmsExposeExactlyOneAppFormulaAlternate | T-MAX 100 & CHS 100 II each expose exactly one app-derived formula alternate (by profileID), enrolled as app-derived
- AppDerivedFormulaAlternateTests · testRejectedCandidatesGainNoAlternate | borderline/poor-fit films (tmax-400, fomapan-200/400, rpx-100/400) ship NO formula alternate
- AppDerivedFormulaAlternateTests · testRestoreResolvesAcceptedAlternatesByID | accepted alternates resolve by profileID for session restore
- AppDerivedFormulaAlternateTests · testDefaultProfileRemainsTableInterpolation | default profile stays table-interpolation (.tableLogLogDerived), reproduces published anchor exactly (T-MAX 100 10→15, CHS 8→20)
- AppDerivedFormulaAlternateTests · testAppFormulaStaysWithinEvaluatedResidualAtEveryAnchor | app formula at every anchor .formulaDerived and |stop error| ≤ worstStopError (0.055/0.041)
- AppDerivedFormulaAlternateTests · testAppFormulaKeepsTableBoundaries | app formula keeps coeff/exponent/no-correction band/source range; below band → no-correction; past range → unsupported w/ numeric continuation
- AppDerivedFormulaAlternateTests · testAppFormulaIsLabeledAppDerivedNotManufacturer | app formula name not "Official", contains "App"; modelBasis source=.manufacturerTable, calc=.guardedFormula
- AppDerivedFormulaAlternateTests · testAppFormulaSurfacesAppDerivedComparisonAgainstPublishedRows | [presentation] comparison section lists each published metered row + "Not manufacturer-published guidance." disclaimer
- AppDerivedFormulaAlternateTests · testComparisonSourceColumnPrefersExplicitCorrectedTime | [presentation] Source column anchors on explicit corrected time: T-MAX 10s→15.00/app 15.58/+0.054 stop (not 14.14); CHS 8s→20.00/19.73
- AppDerivedFormulaEvaluationTests · testCandidateListCoversAllUnshippedMigratedTableProfiles | evaluation record = PTIMER-168 migrated table profiles minus already-shipped (Tri-X 400, Fomapan 100)
- AppDerivedFormulaEvaluationTests · testFreeFitConstantsAndResidualsMatchEvaluationRecord | live-anchor free log-log fit coeff/exponent/worst-stop-error match recorded values
- AppDerivedFormulaEvaluationTests · testDecisionsFollowStopErrorPolicy | ship decision: ≤0.1 add, ≤0.25 borderline-doc-only, >0.25 poor-fit-doc-only
- AppDerivedFormulaEvaluationTests · testRetiredFreeFitConstantsReproduceFromCurrentAnchors | 5 retired free-fit constants reproduce from current anchors (preserve-in-fixtures)
- AppDerivedFormulaEvaluationTests · testRetiredTmaxFormulasRemainExecutableRecords | two T-MAX retired fits preserved as executable records pinned at anchors; T-MAX 400 retired 1s threshold → .noCorrection at 1s
- BarePowerLawReciprocityContractTests · testProfileIsNoSourceRangeBarePowerLaw | ILFORD/HARMAN bare power-law (x12 films): coeff 1, ref 1, 1s threshold, per-film exponent, nil source range, empty source evidence
- BarePowerLawReciprocityContractTests · testAtAndBelowThresholdReturnsOfficialNoCorrection | at/below 1s (0.5,1.0) → officialThresholdNoCorrection, corrected==metered (x12)
- BarePowerLawReciprocityContractTests · testAboveThresholdIsFormulaDerivedBarePowerValue | above 1s (2,8,30) → formulaDerived, corrected==Tm^exponent (x12)
- BarePowerLawReciprocityContractTests · testLongExposureStaysFormulaDerivedWithoutBeyondSourceClassification | 600s stays formulaDerived (never beyond-source; no bounded source range), value on Tm^p curve (x12)
- BarePowerLawReciprocityContractTests · testNoSourceRangeProfileSuppressesSourceReferenceArtifacts | [presentation] summary "Formula-based correction on the active curve"; no source markers/not-recommended/beyond-source; formula text present; no Source reference/Guidance boundary sections (x12)
- ConstantMultiplierFormulaProfileTests · testBoundaryAt120SecondsAppliesHalfStopFormulaNotNoCorrection | Acros II @120s → formulaDerived (start of +1/2 stop range), corrected=120·√2, not no-correction
- ConstantMultiplierFormulaProfileTests · testInsideFormulaRangeAppliesConstantHalfStop | inside 120–1000s (120,150,240,500,750,1000) → formulaDerived, corrected=Tm·√2
- ConstantMultiplierFormulaProfileTests · testFormulaUsesConstantMultiplierForm | formula exponent 1, coeff √2; note "numeric continuation" not "extrapolation"
- ConstantMultiplierFormulaProfileTests · testAbove1000SecondsBecomesBeyondSourceNumericGuidance | >1000s (1100,2000,5000) → .unsupportedOutOfPolicyRange, numeric +1/2 stop continuation (Tm·√2)
- ConstantMultiplierFormulaProfileTests · testSourceEvidenceIsPreservedAsRangeNotFabricatedExactPoints | single source evidence row as range 120–1000s with +0.5 stop delta, not fabricated exact points
- ConstantMultiplierFormulaProfileTests · testDetailsSurfaceShowsRangeSourceReference | [presentation] Source reference surfaces 120 & 1000 bounds; no legacy Reference, no Guidance boundary
- ConstantMultiplierFormulaProfileTests · testSourceReferenceThresholdRowReadsAsStrictlyBelow120Seconds | [presentation] threshold row renders "< 120" (strict), not "<= 119.999999"/"<= 120"
- ConstantMultiplierFormulaProfileTests · testFormulaGraphRendersWithoutPerSecondSourceMarkers | [presentation] graph kind .formula, no source markers/not-recommended boundary; beyondSourceRangeStart=1000.000001
- ConstantMultiplierFormulaProfileTests · testFormulaGraphTextRendersConstantMultiplierWithoutSpuriousExponent | [presentation] formula text = "Tc = 1.4142 × Tm" (^1 omitted)
- ConstantMultiplierFormulaProfileTests · testAbove1000SecondsDetailAndExplanationSurfaceSourceRangeWording | [presentation] @2000s detail & graph unsupportedExplanation contain "source range"
- ConvertedFormulaDetailsPresentationTests · testDetailsSplitsSourceReferenceAndGuidanceBoundarySections | [presentation] Provia 100F: Source reference has 2.5G & "No correction range" not "Not recommended"; Guidance boundary has "Not recommended" not 2.5G; no Reference/Profile/Formula sections; graph formula has "1.3676"
- ConvertedFormulaDetailsPresentationTests · testGraphCarries240SecondSourceReferenceMarker | [presentation] graph 240s source marker, corrected≈302.4s (+1/3 stop), label "240s"
- ConvertedFormulaDetailsPresentationTests · testGraphCarriesNotRecommendedBoundaryAt480Seconds | [presentation] graph notRecommendedBoundary=480s (metered 60,240,600)
- ConvertedFormulaDetailsPresentationTests · testGraphSourceReferenceMarkersExclude480SecondBoundary | [presentation] 480s never a source-reference marker
- ConvertedFormulaDetailsPresentationTests · testGraphCurrentResultMarkerPersistsAlongsideReferenceElements | [presentation] current point persists alongside markers/boundary; style .formulaDerived at 240s
- ConvertedFormulaDetailsPresentationTests · testInSourceRangeGraphHasNoDuplicateDescriptionLines | [presentation] in-source-range (240s) graph descriptionLines empty
- ConvertedFormulaDetailsPresentationTests · testBeyondSourceRangeProducesSingleSourceRangeNote | [presentation] 600s → single description line containing "source range"
- ConvertedFormulaDetailsPresentationTests · testBeyondVisibleRangeProducesSingleVisibleRangeNote | [presentation] 500000s → single description line containing "beyond the visible"
- ConvertedFormulaDetailsPresentationTests · testDetailsSectionOrderIsSourceReferenceGuidanceBoundarySources | [presentation] section order = [Reciprocity model, Source reference, Guidance boundary, Sources]
- ConvertedFormulaDetailsPresentationTests · testCurrentResultStatusTextIsShortAndStateAware | [presentation] status: 240→"Formula-derived", 600→"Beyond source range"(.unsupported), 60→"No correction", 500000→"Beyond source range", 1/30→"No correction"
- ConvertedFormulaDetailsPresentationTests · testNoCorrectionUsesComparisonLayoutLikeEveryOtherCase | [presentation] no-correction (60s) uses .comparison layout, no legacy note, status "No correction"
- ConvertedFormulaDetailsPresentationTests · testAllCasesShareSameLayoutAndProduceStatusText | [presentation] all cases (60/240/600) use .comparison layout with expected status
- ConvertedFormulaDetailsPresentationTests · testBeyondVisibleNumericResultDoesNotDoubleApproximateMarker | [presentation] 1000000s corrected display starts "≈" not "≈≈"
- ConvertedFormulaDetailsPresentationTests · testBeyondVisibleStatusStaysOnBasisWhileGraphFlagsTrip | [presentation] 1000000s: graph.isBeyondVisibleRange true, status & badge "Beyond source range"
- ConvertedFormulaDetailsPresentationTests · testSubSecondInputStatusReadsAsNoCorrection | [presentation] 1/30s: not below visible, status "No correction"
- ConvertedFormulaDetailsPresentationTests · testMainBadgeAndDetailStatusUseTheSameWording | [presentation] badge & status text identical (60/240/600)
- ConvertedFormulaDetailsPresentationTests · testSourcesAreAnUnlabeledListWithoutReferenceCitationLabels | [presentation] Sources section = unlabeled rows (no Reference/Citation labels), includes manufacturer text & citation
- ConvertedFormulaProfileTemplateTests · testTemplateCaseListCoversEveryConvertedFormulaProfileInCatalog | allCases covers exactly catalog converted-formula films, one converted profile per film
- ConvertedFormulaProfileTemplateTests · testOnlyFormulaPlusSourceEvidenceProfilesAreConverted | isConvertedFormulaProfile true only for formula+source-evidence (Provia 100F true; HP5 Plus, Portra 400 false)
- ConvertedFormulaProfileTemplateTests · testEveryConvertedProfileIsFlaggedAsConvertedFormula | every allCases film isConvertedFormulaProfile==true
- ConvertedFormulaProfileTemplateTests · testEveryConvertedProfileCarriesAFormulaRule | every converted profile carries a formula rule
- ConvertedFormulaProfileTemplateTests · testEveryConvertedProfileBelowThresholdSampleIsOfficialNoCorrection | below-threshold sample → officialThresholdNoCorrection, corrected==metered (per-film)
- ConvertedFormulaProfileTemplateTests · testEveryConvertedProfileInsideRangeSummaryReadsAsFormulaDerived | [presentation] inside-range summary = "Formula-based correction on the active curve"
- ConvertedFormulaProfileTemplateTests · testEveryConvertedProfileAboveSourceRangeSummaryIsBeyondSourceRange | [presentation] above-source-range summary = "Beyond source range"
- FilmDetailsGraphKindInvariantTests · testEveryCatalogStockHasAGraphKindExpectation | [presentation] every catalog stock has a graph-kind expectation (no missing/stale)
- FilmDetailsGraphKindInvariantTests · testEachStockRendersTheExpectedDetailGraphKind | [presentation] each stock renders expected Detail graph kind (.formula or absent) — table/formula films .formula, color/limited-guidance absent
- FilmDetailsGraphKindInvariantTests · testFormulaProfileCalculationCurveExtendsThroughNoCorrectionBand | [presentation] CMS 20 II curve samples through no-correction band (corrected==metered), no visual gap
- FilmDetailsGraphKindInvariantTests · testEveryFormulaProfileWithNoCorrectionBandSamplesIdentityThroughIt | [presentation] every formula profile samples identity (Tc=Tm) inside its no-correction band @0.1s
- FilmModeDetailsGraphPresenterTests · testFormulaProfileGraphReturnsFormulaKindAndFormulaDerivedCurrentPointAtFormulaInput | [presentation] Provia 240s → kind .formula, currentPoint style .formulaDerived at 240s
- FilmModeDetailsGraphPresenterTests · testFormulaProfileGraphMarksCurrentPointNoCorrectionInsideThreshold | [presentation] Provia 60s → currentPoint .noCorrection, caption "Adjusted shutter equals corrected exposure within the no-correction range"
- FilmModeDetailsGraphPresenterTests · testFormulaProfileGraphMarksCurrentPointBeyondSourceRangeAtUnsupportedNumeric | [presentation] Provia 600s → currentPoint .beyondSourceRange, beyondSourceStart 240, notRecommended 480, source-range wording, caption "Formula prediction outside the manufacturer-supported boundary"
- FilmModeDetailsGraphPresenterTests · testFormulaProfileSourceReferenceMarkersIncludePublished240SecondAnchor | [presentation] Provia 240s marker label "240s", corrected≈302.4s
- FilmModeDetailsGraphPresenterTests · testFormulaProfileSourceReferenceMarkersExcludeNotRecommendedBoundary | [presentation] 480s not a source-reference marker
- FilmModeDetailsGraphPresenterTests · testFormulaEquationTextRendersFourDecimalExponentAndAnchor | [presentation] Provia formula text contains "1.3676" and "128"
- FilmModeDetailsGraphPresenterTests · testFormulaProfileSupportedInputHasNoDescriptionLines | [presentation] Provia 240s supported → empty descriptionLines
- FilmModeDetailsGraphPresenterTests · testFormulaProfileWithoutSourceEvidenceLeavesSourceArtifactsEmpty | [presentation] HP5 Plus: kind .formula, empty markers, nil not-recommended/beyond-source, empty descriptions, caption "Adjusted shutter vs corrected exposure on the active calculation curve"
- FilmModeDetailsGraphPresenterTests · testFormulaEquationTextRendersExponentOnlyForNoSourceRangeFormulaProfile | [presentation] HP5 Plus formula text = "Tc = Tm^1.31"
- FilmModeDetailsGraphPresenterTests · testLimitedGuidanceProfileReturnsNilGraph | [presentation] Portra 400 (no formula rule) → nil graph
- FilmModeDetailsGraphPresenterTests · testFailureCalculationResultReturnsNilGraph | [presentation] failed calculation result → nil graph
- FilmModeDetailsGraphPresenterTests · testZeroResultShutterCalculationReturnsNilGraph | [presentation] zero result shutter → nil graph
- FormulaGraphScalePolicyTests · testScalePolicySelectsT1ForValuesUpToOneHour | [presentation] tier T1 for max ≤3600s (1,600,3600)
- FormulaGraphScalePolicyTests · testScalePolicySelectsT2ForValuesAboveOneHourUpToTenHours | [presentation] tier T2 for 3601–36000s
- FormulaGraphScalePolicyTests · testScalePolicySelectsT3ForValuesAboveTenHoursUpToOneHundredHours | [presentation] tier T3 for 36001–360000s
- FormulaGraphScalePolicyTests · testScalePolicyKeepsT3ForValuesBeyondOneHundredHoursAndReportsOverflow | [presentation] >360000s stays T3, isBeyondVisibleRange true (false at 360000)
- FormulaGraphScalePolicyTests · testScalePolicyAxisLabelsArePhoneWidthFriendly | [presentation] axis ticks ≤8 (T1/T2), ≤6 (T3), within bounds, sorted ascending
- FormulaGraphScalePolicyTests · testUsesT1ForNormalInputs | [presentation] Provia 240s → T1, xRange/yRange 0.01–3600, not beyond visible
- FormulaGraphScalePolicyTests · testUsesT2OrT3WhenFormulaPredictionExceedsOneHour | [presentation] Provia 3000s → tier T2 or T3 (not T1), not beyond visible
- FormulaGraphScalePolicyTests · testBeyondOneHundredHoursStaysAtT3WithOverflowIndicator | [presentation] Provia 500000s → T3, ranges capped 0.01–360000, isBeyondVisibleRange true
- FormulaGraphScalePolicyTests · testFormulaCurveDoesNotExceedSelectedTier | [presentation] curve max sample ≤ T3 upper bound
- FormulaGraphScalePolicyTests · testSourceMarkersAndBoundaryStayWithinSelectedTier | [presentation] source markers & boundary stay within selected tier range
- FormulaGraphScalePolicyTests · testAxisTicksExtendTierTicksWithSubSecondLabels | [presentation] axis ticks include "1h" + all tier labels + sub-second tick (count > tier labels)
- FormulaGraphVisibilityTests · testSubSecondInputSitsInsideVisibleNoCorrectionBand | [presentation] Provia 1/30s: not below visible, T1, xRange lower <1, upper 3600
- FormulaGraphVisibilityTests · testOneSecondInputDoesNotTripBelowVisibleRange | [presentation] Provia 1s not marked below-visible
- FormulaGraphVisibilityTests · testCalculationCurveStartsAtViewportLowerBoundAsIdentitySegment | [presentation] curve min sample == xRange lower bound; identity samples (≤threshold) corrected==metered
- FormulaGraphVisibilityTests · testGraphCarriesFormulaDisplayTextWithFourDecimalExponent | [presentation] Provia 240s formula text contains "1.3676" and "128"
- FormulaGraphVisibilityTests · testGraphCarriesBeyondSourceRangeStartAt240Seconds | [presentation] beyondSourceRangeStart=240 (metered 60,240,600)
- FormulaGraphVisibilityTests · testBeyondVisibleSuppressesInRangeCurrentMarker | [presentation] 500000s: isBeyondVisibleRange true, currentPoint still non-nil
- FormulaGraphVisibilityTests · testSubSecondInputKeepsCurrentMarkerVisibleInsideViewport | [presentation] 1/30s: not below visible, currentPoint .noCorrection, xRange lower < current metered
- FormulaGraphVisibilityTests · testNoCorrectionInputStillRendersGraphWithIdentityCurrentPoint | [presentation] 60s: graph kind .formula, currentPoint .noCorrection on identity line
- FormulaGraphVisibilityTests · testGraphCarriesNoCorrectionRangeUpperBound | [presentation] noCorrectionRangeUpperBound=128 (metered 60,240,600)
- FormulaGraphVisibilityTests · testFormulaSegmentBeyondThresholdLeavesIdentityForPredictedCurve | [presentation] sample past 128s threshold has corrected > metered (curve lifts off identity)
- FormulaGraphVisibilityTests · testNoCorrectionGraphCaptionReferencesNoCorrectionRangeNotCalculationCurve | [presentation] 60s caption references "no-correction", not "calculation/formula curve"
- FormulaGraphVisibilityTests · testUnsupportedNumericInputRendersBeyondSourceRangeCurrentPoint | [presentation] 600s: not guide-only, currentPoint .beyondSourceRange at 600s
- FormulaGraphVisibilityTests · testUnsupportedNumericEnablesCorrectedExposurePlayButton | 600s: corrected display .quantified/≈ (not ≈≈); action canStartTimer, targetSeconds=corrected, isOutsideManufacturerGuidance true
- GuardedFormulaEvidenceContractTests · testSourceEvidencePreservesPublishedRows | converted guarded films preserve exact published rows (filter/stopDelta/correctedTime/notRecommended/rangeNote/sourceEvidenceOnly) — Velvia 50/100, Provia 100F, CMS 20 II, RETRO 80S, SUPERPAN 200
- GuardedFormulaEvidenceContractTests · testFormulaTracksPublishedQuantifiedRowsWithinTolerance | formula tracks published quantified rows within 0.05 stop (RETRO 80S/SUPERPAN 200 @4/8/15/30s)
- GuardedFormulaFitContractTests · testFormulaParametersMatchPublishedFit | converted guarded films' exponent/coeff/reference/noCorrection/sourceRange/note keywords/publisher/authority match published fit (6 films)
- GuardedFormulaPresentationContractTests · testDetailsSplitsSourceReferenceAndGuidanceBoundary | [presentation] Source reference contains/excludes tokens, Guidance boundary present/absent per film; no legacy Reference (Velvia 50/100, RETRO 80S, SUPERPAN 200)
- GuardedFormulaPresentationContractTests · testGraphCarriesSourceMarkersAndBoundaries | [presentation] graph source markers, notRecommended boundary, beyondSource start per film
- GuardedFormulaPresentationContractTests · testPublishedUpperBoundarySummaryStaysFormulaDerived | [presentation] Velvia 100 @240s summary="Formula-based correction on the active curve" (not Beyond source range)
- GuardedFormulaPresentationContractTests · testBeyondSourceRangeWordingUsesSourceRangeNotExtrapolated | [presentation] beyond-source detail/graph explanation avoids "extrapolated", uses "source range" (Velvia 50 @100, Provia 100F @600)
- GuardedFormulaPresentationContractTests · testUnsupportedNumericResultEnablesCalculatedExposure | Provia 100F @600s: hasCalculatedExposureTime, category=.unsupported, returnsCalculatedExposureTime, badge=.unsupported
- GuardedFormulaRegionBasisContractTests · testAtThresholdBoundaryReturnsOfficialNoCorrection | at inclusive threshold → officialThresholdNoCorrection, corrected==threshold (Velvia 50/100, Provia 100F, CMS 20 II)
- GuardedFormulaRegionBasisContractTests · testInsideSourceRangeIsFormulaDerived | inside source-backed range → formulaDerived
- GuardedFormulaRegionBasisContractTests · testAtPublishedUpperBoundaryIsFormulaDerivedWithExactValue | published upper row stays formulaDerived w/ exact continuation value (Velvia 100/Provia 100F @240)
- GuardedFormulaRegionBasisContractTests · testAboveSourceRangeIsBeyondSourceWithFormulaContinuation | above source range → unsupportedOutOfPolicyRange w/ formula continuation (incl RETRO 80S/SUPERPAN 200 @90)
- GuardedReciprocityFormulaTests · testLegacyBarePowerLawMatchesLegacyOutput | Tc=Tm^1.31 == pow(metered,1.31) within source range
- GuardedReciprocityFormulaTests · testLegacyCoefficientFormulaPreservesCorrectedExposure | Tc=a×Tm^p preserves a×pow(Tm,p) above no-correction
- GuardedReciprocityFormulaTests · testNoCorrectionGuardIsInclusiveAtTheBoundary | noCorrectionThroughSeconds inclusive: 0.001 & 1 → noCorrection, 1.0001 leaves band
- GuardedReciprocityFormulaTests · testNonDefaultReferenceTimeProducesScaledFormula | Tc=a×(Tm/Tref)^p (coeff 128, ref 128, exp 1.3676) @200 = 128×(200/128)^1.3676
- GuardedReciprocityFormulaTests · testNonZeroOffsetIsAddedAfterPowerTerm | Tc=a×(Tm/Tref)^p+b @20 = 10×(20/10)^1.45+0.3
- GuardedReciprocityFormulaTests · testSourceRangeThroughSecondsIsConfidenceBoundaryNotCalculationStop | @500 (past sourceRange 100) → beyondSourceRange w/ value 2×500^1.45
- GuardedReciprocityFormulaTests · testNilSourceRangeAlwaysClassifiesAsWithinSourceRange | nil sourceRange → all in-formula inputs withinSourceRange (2/100/8192)
- GuardedReciprocityFormulaTests · testEvaluatorClassifiesBeyondSourceFormulaAsUnsupportedWithPrediction | evaluator: bounded formula @500 → unsupportedOutOfPolicyRange w/ prediction
- GuardedReciprocityFormulaTests · testInvalidFormulaParametersAreRejectedAsInvalidFormula | non-positive coeff/ref, sourceRange<noCorrection, non-finite coeff → .invalidFormula
- GuardedReciprocityFormulaTests · testNonPositiveMeteredInputIsInvalidInput | metered 0/-1/nan/infinity → .invalidInput
- GuardedReciprocityFormulaTests · testFormulaThatWouldShortenExposureSurfacesAsUnsafeShortening | Tc=Tm^0.5 @4 → .unsafeShorteningFormula (runtime safety, not data error)
- GuardedReciprocityFormulaTests · testEvaluatorSurfacesInvalidFormulaAsUnsupported | invalid formula via evaluator → unsupportedOutOfPolicyRange, nil corrected
- GuardedReciprocityFormulaTests · testEvaluatorClampsUnsafeFormulaToNoCorrection | unsafe-shortening via evaluator @4 → officialThresholdNoCorrection, corrected=4 (Tc≥Tm)
- GuardedReciprocityFormulaTests · testFormatterOmitsNeutralValuesForPlainPowerLaw | [presentation] formatter "Tc = Tm^1.31"
- GuardedReciprocityFormulaTests · testFormatterRendersCoefficientWhenNonNeutral | [presentation] "Tc = 2.2457 × Tm^1.4515"
- GuardedReciprocityFormulaTests · testFormatterRendersReferenceTimeWhenNonNeutral | [presentation] "Tc = 2s × (Tm / 10s)^1.45"
- GuardedReciprocityFormulaTests · testFormatterRendersOffsetWhenNonZero | [presentation] "Tc = 2s × (Tm / 10s)^1.45 + 0.3s"
- GuardedReciprocityFormulaTests · testFormatterDropsExponentOneForConstantMultiplierForm | [presentation] "Tc = 1.4142 × Tm"
- GuardedReciprocityFormulaTests · testShippedFormulaProfilesRenderThroughTheNewFormatter | [presentation] Pan F Plus "Tc = Tm^1.33", Provia 100F "Tc = 128s × (Tm / 128s)^1.3676"
- GuardedReciprocityFormulaTests · testOpenBoundaryNoCorrectionNoteUsesStrictlyBelowWording | [presentation] Acros II note "< 120 sec" (open boundary), not "≤ 120 sec"
- GuardedReciprocityFormulaTests · testInclusiveNoCorrectionBoundaryNoteUsesLeqWording | [presentation] HP5 Plus note "≤ 1 sec" (inclusive boundary)
- GuardedReciprocityFormulaTests · testEveryShippedFormulaProfileDeclaresModifiedSchwarzschildFamily | every shipped formula profile formulaFamily==.modifiedSchwarzschild
- GuardedReciprocityFormulaTests · testFormulaFamilyRoundTripsThroughCodable | formulaFamily round-trips through Codable
- GuardedReciprocityFormulaTests · testDecoderRejectsFormulaJSONWithoutFormulaFamilyDiscriminator | JSON missing formulaFamily fails to decode
- GuardedReciprocityFormulaTests · testEveryShippedFormulaProfilePassesSafetyAtRepresentativePoints | every shipped formula profile: basis in allowed set, never limited-guidance; corrected finite/positive, Tc≥Tm at representative points
- GuardedReciprocityFormulaTests · testEveryShippedFormulaArithmeticIsSelfSafeAtRepresentativePoints | shipped formula curve self-safe (Tc≥Tm, no invalid/unsafe) except known fit-gap films (RPX 100/RETRO 80S/SUPERPAN 200) just-above-threshold
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceProfilesDoNotCarryFormulaRules | Kodak limited-guidance films carry no formula rule, not converted (Ektar 100, Portra 160/400, Gold 200, Ultra Max 400, Ektachrome E100)
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceProfilesCarryNoSourceEvidence | sourceEvidence empty (no quantified anchors)
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceProfilesStayNoCorrectionInsideThresholdBand | inside threshold → officialThresholdNoCorrection, corrected==metered
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceProfilesLandOnLimitedGuidanceJustPastTheOfficialUpperBound | upper+0.001 → limitedGuidanceNoQuantifiedPrediction, nil corrected, rangeStatus=beyondLastRepresentativePoint
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceProfilesStayLimitedGuidanceFarPastTheUpperBound | far past upper (×10/60/600) → limitedGuidance, nil corrected
- LimitedGuidanceReciprocityContractTests · testColorFilterGuidanceStaysAdviceNotCorrectedTimeAnchor | Ektachrome E100 CC10R@120s carried as filter advice (named, note "120"), no exposure adjustment, anchor stays limitedGuidance/nil
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceBeyondThresholdSurfacesNoQuantifiedPredictionWording | [presentation] past threshold badge="No quantified prediction", detail has "No official quantified prediction is available"
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceWithinThresholdSurfacesNoCorrectionWording | [presentation] at upper bound badge="No correction"
- LimitedGuidanceReciprocityContractTests · testLimitedGuidanceProfilesSuppressGraphWhenNoQuantifiedPredictionExists | [presentation] past threshold graph suppressed (nil)
- LogLogFormulaProfileSpecificTests · testAtOneOverThousandSecStaysNoCorrectionDespiteSourceEvidenceRow | CMS 20 II @0.001s → officialThresholdNoCorrection, corrected=0.001 (despite +1/2 stop evidence row)
- LogLogFormulaProfileSpecificTests · testFormulaAnchorAtOneSecondMatchesPublishedHalfStop | CMS @1.0001s → formulaDerived, corrected≈1.4142136 (+1/2 stop)
- LogLogFormulaProfileSpecificTests · testFormulaAnchorAtTenSecondsMatchesPublishedFullStop | CMS @10s → formulaDerived, corrected≈20 (+1 stop)
- LogLogFormulaProfileSpecificTests · testBetweenAnchorsReturnsFormulaDerivedValue | CMS @1.7s≈2.604, @6.8s≈12.83 formulaDerived (log-log fit)
- LogLogFormulaProfileSpecificTests · testBeyondTenSecondsCarriesFormulaPredictionAsBeyondSource | CMS 14/27/54/100s → unsupportedOutOfPolicyRange w/ formula continuation
- LogLogFormulaProfileSpecificTests · testAbove100SecondsRemainsBeyondSourceWithFormulaPrediction | CMS 120/200/500/1000s → unsupported w/ 1.4142136×Tm^1.150515
- LogLogFormulaProfileSpecificTests · testGraphIsFormulaKindAndCarriesNoCorrectionBandUpToOneSecond | [presentation] CMS graph kind=.formula, noCorrection band upper=1s
- LogLogFormulaProfileSpecificTests · testGraphSourceReferenceMarkersIncludeOneSecondAndTenSecondsOnly | [presentation] CMS markers exactly 1s & 10s
- LogLogFormulaProfileSpecificTests · testGraphExcludesOneOverThousandSecMarkerEvenThoughEvidenceIsPreserved | [presentation] CMS 1/1000s never a graph marker (markers >0.1)
- LogLogFormulaProfileSpecificTests · testGraphExposesOneHundredSecondNotRecommendedBoundaryAcrossInputs | [presentation] CMS notRecommended boundary=100 across 0.5/5/50/200s
- LogLogFormulaProfileSpecificTests · testGraphBeyondSourceRangeStartsAtTenSecondsAtSourceBoundary | [presentation] CMS beyondSourceStart=10 (100 is separate warning marker)
- LogLogFormulaProfileSpecificTests · testGraphSupportedRangeUpperBoundIsTenSeconds | [presentation] CMS supportedRangeUpperBound=10
- LogLogFormulaProfileSpecificTests · testViewportAndAxisAreStableAcrossInputs | [presentation] CMS viewport/axis ticks/anchors input-independent across 8 inputs
- LogLogFormulaProfileSpecificTests · testCurrentMarkerInsideNoCorrectionBandSitsOnIdentity | [presentation] CMS sub-1s current point style=.noCorrection on identity (0.053/0.423/1.0)
- LogLogFormulaProfileSpecificTests · testCurrentMarkerInSourceBackedRangePlotsAtFormulaValue | [presentation] CMS 1.7/6.8s current point style=.formulaDerived at formula value
- LogLogFormulaProfileSpecificTests · testAboveTenSecondsPlotsBeyondSourceMarker | [presentation] CMS >10s current point style=.beyondSourceRange (14..500)
- LogLogFormulaProfileSpecificTests · testDetailsSplitsSourceReferenceAndGuidanceBoundarySections | [presentation] CMS Source reference has No correction range + * evidence-only footnote, excludes Not recommended; Guidance boundary has 100s Not recommended
- LogLogFormulaProfileSpecificTests · testSourceReferenceRowsAreSortedByMeteredExposureAscending | [presentation] CMS rows: no-correction band first (no *), 1/1000s * second, 1s third, 10s fourth
- LogLogFormulaProfileSpecificTests · testBeyondOneHundredSecondsUsesBeyondSourceRangeWordingWithValue | [presentation] CMS @200s summary="Beyond source range", graph explanation has "source range"
- NotRecommendedBoundaryPresentationTests · testStopSignalMessagesFireOnceBoundaryIsReached | classifier returns verbatim stop signal at/past boundary, empty below (Velvia 50@64, Provia 100F@480, CMS@100)
- NotRecommendedBoundaryPresentationTests · testProfilesWithoutStopSignalRowsStaySilent | Acros II/Velvia 100/RETRO 80S/SUPERPAN 200/HP5 Plus emit no stop signal @10000s
- NotRecommendedBoundaryPresentationTests · testVelvia50InfoTextLeadsWithStopSignalAtBoundary | [presentation] Velvia 50 @64 info leads "Manufacturer guidance: 64 sec is not recommended."; badge="Beyond source range"
- NotRecommendedBoundaryPresentationTests · testVelvia50InfoTextStaysGenericBelowBoundary | [presentation] Velvia 50 @32 info no "Manufacturer guidance:" prefix
- NotRecommendedBoundaryPresentationTests · testProviaAndCmsInfoTextLeadWithStopSignalAtBoundary | [presentation] Provia 100F@480/CMS@100 info leads with stop signal message
- NotRecommendedBoundaryPresentationTests · testStopSignalDoesNotSurfaceOnQuantifiedInRangeResults | quantified in-range result (boundary inside source range) stays silent, category=.formulaDerived
- NotRecommendedBoundaryPresentationTests · testOnlyFirstReachedStopSignalSurfaces | classifier reports all reached in order; presenter surfaces only first ("20 sec...")
- NotRecommendedBoundaryPresentationTests · testVelvia50SummaryDetailLeadsWithStopSignalAtBoundary | [presentation] Velvia 50 @64 summary detail leads stop signal + keeps "beyond the manufacturer source range"
- NotRecommendedBoundaryPresentationTests · testVelvia50SummaryDetailStaysGenericBelowBoundary | [presentation] Velvia 50 @32 summary detail nil
- OfficialTableMigrationInvariantTests · testMigratedProfilesDefaultToTableLogLogModel | 8 migrated films: sourceModel manufacturerTable (Tri-X manufacturerGraphTable), calc tableLogLogInterpolation, usesTableInterpolation
- OfficialTableMigrationInvariantTests · testMigratedProfilesCarryNoFormulaRule | migrated films carry no formula rule, not converted-formula
- OfficialTableMigrationInvariantTests · testMigratedProfilesPreserveOfficialSourceEvidence | migrated films keep sourceEvidence, authority=official, kind=manufacturerPublished
- OfficialTableMigrationInvariantTests · testMigratedProfilesReproducePublishedAnchorsExactly | each anchor → tableLogLogDerived, corrected reproduces published exactly
- OfficialTableMigrationInvariantTests · testMigratedProfilesTableRuleBoundariesMatchSource | table rule noCorrection/sourceRange/anchors match published per film
- OfficialTableMigrationInvariantTests · testTrueManufacturerFormulaFilmRemainsFormula | HP5 Plus stays manufacturerFormula/guardedFormula, not table; @4=formulaDerived
- OfficialTableMigrationInvariantTests · testLimitedGuidanceColorFilmsStayLimitedGuidanceAfterMigration | 6 Kodak color films stay limitedGuidance, no table model
- OfficialTableMigrationInvariantTests · testPtimer169SpecialCasesAreNotMigrated | Acros II/Velvia 50/100/Provia 100F/RETRO 80S/SUPERPAN 200/CMS 20 II not table-migrated, still carry formula rule
- ReciprocityCalculationPolicyPerformanceTests · testFormulaDerivedEvaluationPerformance | [presentation] perf: formula-derived eval 1000× (XCTMeasure)
- ReciprocityCalculationPolicyPerformanceTests · testFormulaBoundedBeyondSourceRangeEvaluationPerformance | [presentation] perf: bounded beyond-source eval 1000×
- ReciprocityCalculationPolicyPerformanceTests · testThresholdNoCorrectionPerformance | [presentation] perf: threshold no-correction eval 1000×
- ReciprocityCalculationPolicyPerformanceTests · testLimitedGuidanceEvaluationPerformance | [presentation] perf: limited-guidance eval 1000×
- ReciprocityCalculationPolicyPerformanceTests · testMixedPickerScrollWorkloadPerformance | [presentation] perf: mixed picker-scroll workload across 4 profile shapes
- ReciprocityCalculationPolicyTests · testThresholdRangeReturnsNoCorrectionBasis | @0.5 limited-guidance → officialThresholdNoCorrection, corrected=0.5, currentOfficial/withinStatedRange/none, note=thresholdGuidanceOnly
- ReciprocityCalculationPolicyTests · testThresholdHandoffWithFormulaUsesNoCorrectionBasis | bare power-law @0.5 → officialThresholdNoCorrection, corrected=0.5
- ReciprocityCalculationPolicyTests · testFormulaProfileWithinSupportedRangeIsFormulaDerived | bare power-law @100 → formulaDerived, withinStatedRange, corrected=100^1.31
- ReciprocityCalculationPolicyTests · testFormulaProfileWithoutExplicitMaxRemainsQuantifiedAtVeryLongInputs | unbounded formula @8192 stays formulaDerived, corrected=8192^1.31
- ReciprocityCalculationPolicyTests · testFormulaProfileBecomesUnsupportedPastSupportedRange | bounded formula @601 → unsupportedOutOfPolicyRange, still numeric=601^1.31, notes=[beyondOfficialQuantifiedRange,unsupportedByPolicy]
- ReciprocityCalculationPolicyTests · testFormulaProfileBeyondSourceRangeStillCarriesPrediction | PTIMER-160 bounded formula @1000 past sourceRange carries 1000^1.31, unsupportedOutOfPolicyRange (no hard-stop nil)
- ReciprocityCalculationPolicyTests · testLimitedGuidanceBeyondThresholdReturnsNoQuantifiedPrediction | limited-guidance @4 → nil corrected, limitedGuidanceNoQuantifiedPrediction, beyondLastRepresentativePoint, notes=[limitedGuidanceContinuationOnly,beyondOfficialQuantifiedRange]
- ReciprocityCalculationPolicyTests · testProfileWithNoApplicableRuleIsUnsupported | empty rules @10 → unsupportedOutOfPolicyRange, nil corrected, note=unsupportedByPolicy
- ReciprocityCalculationPolicyTests · testArchivalOfficialProfilePropagatesAuthorityImpact | archivalOfficial formula @100 → authorityImpact=archivalOfficial, last note=archivalOfficialSource
- ReciprocityCalculationPolicyTests · testUnofficialSecondaryProfilePropagatesAuthorityImpact | unofficialSecondary formula @100 → authorityImpact=unofficialSecondary, note=unofficialSecondarySource, warning=caution
- ReciprocityCalculationPolicyTests · testFormulaOnlyProfileBelowNoCorrectionThroughSecondsReturnsNoCorrection | formula-only (noCorrectionThrough=1) @0.5 → officialThresholdNoCorrection, corrected=0.5 (guard owned by formula)
- ReciprocityCalculationPolicyTests · testCorrectedNeverShorterThanMetered | Tc=Tm^0.5 @2 → safety reclassifies to no-correction, corrected=2 (never shortens shutter)
- ReciprocityConfidencePresentationTests · testThresholdNoCorrectionMapsToTrustedNoCorrectionPresentation | [presentation] no-correction → category/resultKind .noCorrection, level high, badge .trusted, warn none, "No correction", returnsTime, token thresholdGuidanceOnly
- ReciprocityConfidencePresentationTests · testFormulaDerivedMapsToMeasuredFormulaDerivedPresentation | [presentation] formula → .formulaDerived, level medium, badge .measured, warn none, "Formula-derived", returnsTime, token formulaDerived
- ReciprocityConfidencePresentationTests · testLimitedGuidanceMapsToLimitedGuidancePresentation | [presentation] limited → .limitedGuidance, level none, badge .limitedGuidance, warn note, "No quantified prediction", !returnsTime, tokens limitedGuidanceContinuationOnly/officialRangeExceeded, excludes unsupportedByPolicy
- ReciprocityConfidencePresentationTests · testBoundedFormulaPastSupportedRangeMapsToUnsupportedPresentation | [presentation] unsupported → .unsupported, level none, badge .unsupported, warn strong, "Outside guidance", returnsTime, tokens unsupportedByPolicy/beyondPolicyLimit
- ReciprocityConfidencePresentationTests · testArchivalOfficialPropagatesShortLabelPrefixAndExplanationToken | [presentation] archivalOfficial → "Archival formula", level medium, token archivalOfficialSource
- ReciprocityConfidencePresentationTests · testUnofficialSecondaryPropagatesShortLabelPrefixAndExplanationToken | [presentation] unofficialSecondary → "Secondary formula", level low, badge caution, token unofficialSecondarySource
- ReciprocityConfidencePresentationTests · testUserDefinedPropagatesShortLabelPrefixAndExplanationToken | [presentation] userDefined → "Custom formula", level veryLow, badge caution, token userDefinedSource
- ReciprocityConfidencePresentationTests · testDecodingRejectsContradictoryPresentationCategoryAndResultKind | decoder rejects category=.unsupported w/ resultKind=.limitedGuidance ("resultKind must remain aligned with category")
- ReciprocityConfidencePresentationTests · testDecodingRejectsPresentationThatClaimsCalculatedExposureWithoutOne | decoder rejects calculatedExposureReturned token w/ returnsTime=false
- ReciprocityConfidencePresentationTests · testDecodingRejectsUnsupportedPresentationWithNonUnsupportedBadgeStyle | decoder rejects category=.unsupported w/ badge=.limitedGuidance ("unsupported badge styling")
- ReciprocityDomainTests · testFormulaRuleRoundTripsThroughJSON | formula rule JSON round-trip; exponent 1.31, coeff 1, refTime 1, offset 0, noCorrThrough 1, sourceRange nil
- ReciprocityDomainTests · testLimitedGuidanceRuleRoundTripsThroughJSON | threshold+limitedGuidance round-trip; kinds [threshold,limitedGuidance], appliesWhenMetered min 1, note preserved
- ReciprocityDomainTests · testSourceEvidenceRowsRoundTripThroughJSON | converted-formula profile w/ 2 sourceEvidence rows (exactSeconds, stopDelta+colorFilter, notRecommended) round-trip; isConvertedFormulaProfile
- ReciprocityDomainTests · testSourceEvidenceOnlyFlagRoundTripsThroughJSON | isSourceEvidenceOnly=true round-trips
- ReciprocityDomainTests · testSourceEvidenceOnlyFlagDefaultsToFalseWhenAbsent | absent isSourceEvidenceOnly decodes false
- ReciprocityDomainTests · testReciprocityRuleKindRawValuesMatchTheJSONDiscriminator | rule-kind raw values threshold/formula/limitedGuidance
- ReciprocityDomainTests · testDecoderRejectsUnknownReciprocityRuleKind | decoder rejects unknown kind "tableLegacy"
- ReciprocityModelReviewFixtureTests · testOfficialReferenceTableMatchesPublishedRows | FOMA official anchors pinned: (1,2,2)/(10,8,80)/(100,16,1600)
- ReciprocityModelReviewFixtureTests · testOfficialAnchorCorrectedMatchesMeteredTimesMultiplier | each official anchor corrected==metered×multiplier
- ReciprocityModelReviewFixtureTests · testCommunityTableMatchesPublishedBlogRows | Ohzart 7-row community table pinned ((1,1.9)…(60,795))
- ReciprocityModelReviewFixtureTests · testAppDerivedFormulaStillCarriesReviewedFormulaConstants | Fomapan100 app-derived formula a=2.2457,p=1.4515; basis manufacturerTable/guardedFormula
- ReciprocityModelReviewFixtureTests · testCurrentAppFormulaOutputsMatchReviewNumbers | app formula @1=2.2457, @10≈63.5114, @100≈1796.1878
- ReciprocityModelReviewFixtureTests · testCurrentAppFormulaResidualsAgainstOfficialTableMatchReviewSummary | per-anchor residuals vs official: +12.3%/+0.167, -20.6%/-0.333, +12.3%/+0.167
- ReciprocityModelReviewFixtureTests · testCommunityFormulaImagePassesOfficialReferenceAnchors | community formula Te=tm[(log10 tm)²+5log10 tm+2] hits FOMA anchors exactly
- ReciprocityModelReviewFixtureTests · testCommunityFormulaImageIsNotEquivalentToCommunityPracticalTable | community formula vs Ohzart table differ by ≥ min stop gap @2/4/8/15/30/60s (0.40/0.60/0.60/0.50/0.30/0.05)
- ReciprocityModelReviewFixtureTests · testCommunityFormulaImagePercentGapAgainstCommunityPracticalTableStaysAboveFivePercent | community formula >5% above Ohzart rows at 2/4/8/15/30/60s
- ReciprocityMultiModelCoexistenceTests · testFilmStockShipsOneCatalogProfileWithAlternatesOffCatalog | Fomapan100: single catalog stock/profile; alternate IDs not top-level catalog entries
- ReciprocityMultiModelCoexistenceTests · testDefaultProfileStaysOfficialAndAlternatesAreOffCatalog | default manufacturerTable/tableLogLog/official; alternates in order, round-trip by id
- ReciprocityMultiModelCoexistenceTests · testAlternateProfileIdentityMatchesItsProvenance | Ohzart alternate: practicalCommunityGuidance/tableLogLog, unofficial, conf medium, label "Ohzart", not app-derived, usesTableInterpolation, not converted
- ReciprocityMultiModelCoexistenceTests · testAlternateInRangeInterpolationStaysBetweenBracketingAnchors | Ohzart @10s interpolates strictly between 35 and 90
- ReciprocityMultiModelCoexistenceTests · testSelectingAlternateReadsAsItsProvenanceNotOfficialNorAppDerived | [presentation] selecting Ohzart @8s → active alt, badge "Table-derived", Source "Practical / community guidance", Calc "Log-log table interpolation", keeps Source reference, no App-derived comparison, forbidden strings absent, caveat "Not FOMA-published data"
- ReciprocityMultiModelCoexistenceTests · testDefaultProfileStillReadsAsOfficialWhenAlternatesExist | [presentation] default @10s active=profile[0], default summary, Source "Manufacturer table"
- ReciprocityMultiModelCoexistenceTests · testActiveFilmRowSubtitleForAppDerivedAlternateIsNotOfficialGuidance | [presentation] app-derived alternate → filmSelection secondaryText "App-derived formula", ≠"Official guidance"
- ReciprocityMultiModelCoexistenceTests · testAlternateBeyondSourceNoteIsSourceNeutralNotManufacturer | Ohzart @120s beyond-source note "Source table ends at 60 sec.", not "Manufacturer table"
- ReciprocityMultiModelCoexistenceTests · testDefaultBeyondSourceNoteIsSourceNeutral | default @1000s beyond-source note "Source table ends at 100 sec.", not "Manufacturer table"
- ReciprocityProfileModelBasisTests · testBundledProfilesDeclareExpectedModelBasis | HP5(formula/guarded), Tri-X(graphTable/tableLogLog), Fomapan100(table/tableLogLog), Ektar100(limitedGuidance/limitedGuidance) declare expected basis
- ReciprocityProfileModelBasisTests · testModelBasisMetadataDoesNotChangeCalculation | basis metadata additive: HP5@4=4^1.31/.formulaDerived, Tri-X@1=2 & @10=50/.tableLogLogDerived, Ektar@30=nil/.limitedGuidance
- ReciprocityProfileModelBasisTests · testProfileWithoutExplicitBasisDecodesUnchanged | FP4 Plus has nil modelBasis (additive-field contract)
- ReciprocityProfileModelBasisTests · testEffectiveModelBasisInfersManufacturerFormulaForBareFormulaProfile | FP4 bare formula infers manufacturerFormula/guardedFormula
- ReciprocityProfileModelBasisTests · testEffectiveModelBasisInfersManufacturerTableForFormulaWithSourceEvidence | formula+sourceEvidence, no basis infers manufacturerTable/guardedFormula
- ReciprocityProfileModelBasisTests · testEffectiveModelBasisInfersLimitedGuidanceForThresholdPlusLimitedGuidanceProfile | threshold+limitedGuidance, no basis infers manufacturerLimitedGuidance/limitedGuidance
- ReciprocityProfileModelBasisTests · testExplicitModelBasisRoundTripsThroughJSON | explicit basis (manufacturerTable/guardedFormula) round-trips
- ReciprocityProfileModelBasisTests · testAbsentModelBasisDecodesAsNil | absent basis decodes nil; effective infers manufacturerFormula/guardedFormula
- ReciprocityProfileModelBasisTests · testCustomUserDefinedFormulaProfileDecodesWithoutModelBasisField | PTIMER-84 custom profile no basis → infers userDefined/guardedFormula; calc @4=4^1.34
- ReciprocityProfileModelBasisTests · testLoaderRejectsExplicitGuardedFormulaBasisOnLimitedGuidanceProfile | loader rejects guardedFormula calc on limited-guidance profile ("requires a formula rule")
- ReciprocityProfileModelBasisTests · testLoaderRejectsExplicitLimitedGuidanceBasisOnFormulaProfile | loader rejects limitedGuidance calc on formula profile ("requires a limited-guidance rule")
- ReciprocityProfileModelBasisTests · testLoaderRejectsTableLookupCalculationModelAsUnimplemented | loader rejects calc=.tableLookup ("not yet implemented")
- ReciprocityProfileModelBasisTests · testLoaderRejectsUnsupportedCalculationModelAsUnimplemented | loader rejects calc=.unsupported
- ReciprocityProfileModelBasisTests · testLoaderRejectsPracticalCommunitySourceModelForOfficialBundledCatalog | loader rejects source=.practicalCommunityGuidance on official catalog
- ReciprocityProfileModelBasisTests · testLoaderRejectsUserDefinedSourceModelForOfficialBundledCatalog | loader rejects source=.userDefined on official catalog
- ReciprocityProfileModelBasisTests · testLoaderRejectsExplicitUnknownSourceModelForBundledCatalog | loader rejects source=.unknown ("omit modelBasis to rely on inferred fallback")
- ReciprocityProfileModelBasisTests · testLoaderAcceptsManufacturerRangeGuidanceSourceModelOnFormulaProfile | loader accepts source=.manufacturerRangeGuidance/.guardedFormula on formula profile
- ReciprocityProfileModelBasisTests · testManufacturerRangeGuidanceSourceModelRoundTripsThroughJSON | basis(manufacturerRangeGuidance/guardedFormula) round-trips
- ReciprocityResultCodableTests · testQuantifiedRoundTripsThroughTaggedFormat | .quantified result tagged round-trip (metered 100, corrected 437.4, basis formulaDerived)
- ReciprocityResultCodableTests · testLimitedGuidanceRoundTripsThroughTaggedFormat | .limitedGuidance result tagged round-trip (basis limitedGuidanceNoQuantifiedPrediction, note)
- ReciprocityResultCodableTests · testUnsupportedRoundTripsThroughTaggedFormat | .unsupported result round-trip w/ corrected 50000, basis unsupportedOutOfPolicyRange
- ReciprocityResultCodableTests · testUnsupportedRoundTripsWithoutCorrectedExposure | .unsupported round-trip w/ corrected nil
- ReciprocityResultCodableTests · testDecoderRejectsPayloadWithMismatchedBasis | decoder rejects kind=limitedGuidance payload w/ basis=officialThresholdNoCorrection
- ReciprocityResultCodableTests · testDecoderRejectsQuantifiedPayloadWithThresholdMismatch | decoder rejects kind=quantified w/ threshold basis but corrected≠metered (1.5 vs 1)
- ReciprocitySecondaryGuidanceCatalogMappingTests · testCatalogSecondaryGuidanceMapsToExpectedRows | [presentation] catalog adjustments map to rows: Velvia50(5M/7.5M+stopWarn), Provia100F(2.5G+stopWarn), EktachromeE100(CC10R+detail), Tri-X(dev -10/-20/-30%, no color); severities/titles per kind
- ReciprocitySecondaryGuidancePresentationTests · test5MFormatsAsNeutralColorCorrection | [presentation] 5M → kind colorCorrection, title "Color correction", value "5M", severity neutral
- ReciprocitySecondaryGuidancePresentationTests · testColorFilterNotationIsPreservedVerbatim | [presentation] color-filter notation preserved verbatim (7.5M/2.5G/CC10R)
- ReciprocitySecondaryGuidancePresentationTests · testNegativeTenPercentDevelopmentFormatsAsDevelopmentAdjustment | [presentation] "-10% development" → kind developmentAdjustment, value preserved, not colorCorrection
- ReciprocitySecondaryGuidancePresentationTests · testNotRecommendedWarningMapsToStopSeverity | [presentation] notRecommended warning → kind warning, value nil, severity stop, detail=message
- ReciprocitySecondaryGuidancePresentationTests · testFreeTextNoteRemainsNoteWithoutInventedNumericValue | [presentation] free-text note → kind note, value nil, detail=text, severity caution
- ReciprocitySecondaryGuidancePresentationTests · testEmptyAndExposureOnlyInputsProduceNoSecondaryRows | [presentation] empty & exposure-only inputs → no secondary rows
- ReciprocitySecondaryGuidancePresentationTests · testMixedSecondaryGuidancePreservesInputOrderAndKinds | [presentation] mixed adjustments preserve input order/kinds [colorCorrection,warning,developmentAdjustment,note]
- SourceReferenceRowSortingTests · testRowKindRawValuesGivePointAnchorBeforeRangeBeforeBoundaryBeforeNote | [presentation] SourceReferenceRowKind raw order pointAnchor<range<boundary<note
- SourceReferenceRowSortingTests · testRowKindOrderingIsTransitiveAndStableAcrossAllPairs | [presentation] kind ordering transitive/stable across all 4×4 pairs
- SourceReferenceRowSortingTests · testKeysOrderBySortValueAscendingWhenKindsAndOffsetsAreEqual | [presentation] equal kind/offset → sort by sortValue asc; [10,0.001,1]→[0.001,1,10]
- SourceReferenceRowSortingTests · testKeysWithSameSortValueOrderByKindPriority | [presentation] tie on sortValue(0.001) → kind priority decides → [pointAnchor,range,boundary,note]
- SourceReferenceRowSortingTests · testKeysWithSameSortValueAndKindPreserveCatalogOrder | [presentation] tie on sortValue+kind → catalogOffset asc → [0,1,2,5]
- SourceReferenceRowSortingTests · testKeysSortAcrossAllThreeDimensions | [presentation] mixed 3-dimension sort → catalogOffset order [2,1,3,4,0]
- SourceReferenceRowSortingTests · testPointAnchorSortsAboveRangeRowAtSameSortValueThroughPresenter | [presentation] CMS 20 II @5s rendered rows[0]="No correction" band, rows[1]=1/1000s point anchor (* marker)
- SourceReferenceRowSortingTests · testGuidanceBoundaryRowsStayOutOfSourceReferenceSection | [presentation] CMS 20 II 100s Not-recommended absent from Source reference, present in Guidance boundary
- SourceShapeModelBasisTests · testTargetProfilesDeclareExplicitModelBasis | 13 PTIMER-169 targets declare explicit modelBasis matching expected source+calc models
- SourceShapeModelBasisTests · testEffectiveModelBasisHonorsExplicitDeclarations | effectiveModelBasis returns declared shape (not inference) for all 13 targets
- SourceShapeModelBasisTests · testAcrosIIDeclarationOverridesTableInference | Acros II effectiveModelBasis.sourceModel==.manufacturerRangeGuidance (not inferred table)
- SourceShapePreservationBaselineTests · testSpecialShapeProfilesReproduceCurrentQuantifiedValues | 11 pinned in-range evals stay .formulaDerived w/ exact corrected (Acros II/Velvia/Provia/Rollei/CMS)
- SourceShapePreservationBaselineTests · testSpecialShapeProfilesReproduceCurrentBeyondRangeValues | 4 beyond-range evals stay .unsupported w/ exact formula-continuation values
- SourceShapePreservationBaselineTests · testSpecialShapeProfilesKeepNoCorrectionBands | 7 no-correction pins stay .officialThresholdNoCorrection returning metered unchanged
- SourceShapePreservationBaselineTests · testLimitedGuidanceProfilesStayValueLessBeyondThreshold | 6 limited-guidance films past threshold stay .limitedGuidance, nil corrected, no calculated time
- SourceShapePreservationBaselineTests · testLimitedGuidanceProfilesKeepThresholdNoCorrection | 6 limited-guidance films @0.5s stay .officialThresholdNoCorrection
- SourceShapePreservationBaselineTests · testNotRecommendedBoundaryRowsRemainPresent | Velvia 50/Provia 100F/CMS 20 II keep notRecommended boundary rows w/ exact published messages
- SourceShapePreservationBaselineTests · testRolleiRangeValuedRowsAreNotFlattenedIntoExactAnchors | RETRO 80S/SUPERPAN 200 1s+2s rows stay note-only ranges, no exposure adjustment
- SourceShapePreservationBaselineTests · testSpecialShapeProfilesKeepFormulaCalculationInPhase1 | 7 special-shape stocks keep .formula rule, no table-interpolation in Phase 1
- TableInterpolationModelTests · testNoCorrectionWithinThreshold | metered ≤ threshold(0.5) → .noCorrection (0.5,0.25)
- TableInterpolationModelTests · testNoCorrectionBoundaryTolerance | 0.1s rule: 0.084/0.1/0.102/0.11 → .noCorrection (nominal 1/10s tolerance ×1.10)
- TableInterpolationModelTests · testValuesAboveToleranceRemainCorrected | 0.12/0.15 above tolerance → .withinSourceRange, corrected>metered
- TableInterpolationModelTests · testToleranceDoesNotExpandBandTowardOneSecond | 0.5 threshold: 0.55→noCorrection, 0.7+1.0→withinSourceRange (relative tolerance)
- TableInterpolationModelTests · testAnchorsReproduceExactly | anchors 1→2,10→80,100→1600 reproduce exactly
- TableInterpolationModelTests · testIntermediateUsesLogLogInterpolation | Tm=31.62 (log-midpoint 10↔100) → ≈357.8s, between 80 and 1600
- TableInterpolationModelTests · testBeyondLastAnchorStillReturnsAValue | 1000s past 100s → .beyondSourceRange ≈32010s (extrapolates last segment, never dead-ends)
- TableInterpolationModelTests · testInvalidInput | metered 0/-1 → .invalidInput
- TableInterpolationModelTests · testInvalidRuleParameters | single-anchor bad rule → !hasValidParameters, evaluate → .invalidRule
- TableLogLogReciprocityContractTests · testDefaultProfileCarriesTableRuleAndNoFormulaRule | 9 table films carry .tableInterpolation rule, no .formula rule post-migration
- TableLogLogReciprocityContractTests · testDefaultProfileModelBasisIsManufacturerTableLogLog | 9 films: source .manufacturerTable (Tri-X .manufacturerGraphTable), calc .tableLogLogInterpolation
- TableLogLogReciprocityContractTests · testSummaryInsideSourceRangeDescribesLogLogInterpolation | [presentation] @10s summary == "Log-log interpolation of the official table"
- TableLogLogReciprocityContractTests · testSummaryBeyondSourceRangeReadsBeyondSourceRange | [presentation] beyond-source sample → summary == "Beyond source range"
- TableLogLogReciprocityContractTests · testGraphExplanationBeyondSourceRangeSurfacesSourceTableWording | [presentation] beyond-source graph unsupportedExplanation contains "source table"
- TableProfileMultiModelTests · testBetweenTenthAndOneSecondIsTableDerivedNotNoCorrection | Tri-X 400 0.2–0.9s → .tableLogLogDerived, metered<corrected<2; 0.672s≈1.192s
- TableProfileMultiModelTests · testHasThreeModels | Tri-X 400 default id=graph-table; 2 alternates official-table, app-formula
- TableProfileMultiModelTests · testModelPickerOrderAndLabelsDistinguishTableModels | [presentation] picker order [official-table,graph-table,app-formula]; labels [Official table,Graph table,App formula]
- TableProfileMultiModelTests · testGraphTableShowsElevenSourceMarkersOfficialTableThree | [presentation] graph-table 11 markers (8 graph-sampled noted)+graph legend; official-table 3 markers no legend; T-MAX 100 no graph legend
- TableProfileMultiModelTests · testOfficialTableAlternate | official-table: 3 anchors (1→2,10→50,100→1200), threshold 0.1, manufacturerTable/tableLogLog, anchors exact+.tableLogLogDerived
- TableProfileMultiModelTests · testAppFormulaAlternate | app-formula: .formula rule, 1s→2s/10s→49s/100s→1200s, 0.05s→noCorrection, isAppDerivedModel true
- TableProfileMultiModelTests · testAppFormulaIsNotLabeledManufacturerFormula | app-formula name not "Official"/contains "App"; basis manufacturerGraphTable/guardedFormula; enrolled app-derived
- TableProfileMultiModelTests · testSourceReferenceNoCorrectionRowEndsAtTenthSecond | [presentation] Tri-X 400 source ref "No correction range" "<= 0.1s", not stale "< 1s"
- TableProfileMultiModelTests · testDevelopmentLegendStillSurfacesAfterMigration | [presentation] Tri-X 400 keeps "Development adjustment: Dev -10% means..." legend line
- TableProfileShortExposureExclusionTests · testShort1Over10000ExposureIsNotALongExposureTablePoint | T-MAX 100 @1/10000s → .officialThresholdNoCorrection identity; no sourceEvidence row near that value
- TableProfileShortExposureExclusionTests · testShortExposureGuidanceIsPreservedAtCatalogLevelOnly | T-MAX 100 profile.notes archives 1/10,000 short-exposure +1/3 stop guidance
- TableProfileShortExposureExclusionTests · testProfileNotesDocumentNoCorrectionRangeAndShortExposureExclusion | T-MAX 100 ≥2 notes referencing table/interpolation and short-exposure exclusion
- TableProfileSourceDataContractTests · testTableRuleParametersAndStoredAnchorsMatchPublished | per-film table thresholds/sourceRange/anchors match published (12–14 cases)
- TableProfileSourceDataContractTests · testAtAndBelowThresholdReturnsOfficialNoCorrection | below-threshold samples → .officialThresholdNoCorrection, corrected==metered
- TableProfileSourceDataContractTests · testNominalThresholdToleranceClassifiesNoCorrection | nominal 1/10s (~0.102) → no-correction; clearlyCorrected → .tableLogLogDerived corrected>metered
- TableProfileSourceDataContractTests · testInsideSourceRangeIsTableLogLogDerived | inside samples → .tableLogLogDerived
- TableProfileSourceDataContractTests · testAnchorsReproducePublishedCorrectedTimesExactly | each anchor reproduces published corrected time exactly (1e-4)
- TableProfileSourceDataContractTests · testAboveSourceRangeIsBeyondSourceWithExtrapolation | above samples → .unsupportedOutOfPolicyRange, extrapolation > last anchor
- TableProfileSourceDataContractTests · testSourceEvidencePreservesPublishedRows | source-evidence rows match metereds + per-row corrected/stopDelta/dev/multiplier/isApproximate
- TableProfileSourceDataContractTests · testSourceProvenanceMatchesPublished | source kind/authority/publisher/title match published when set
- TableProfileSourceDataContractTests · testProfileIdentityMatchesPublished | profile name + id suffix match published when set
- TableProfileSourceDataContractTests · testModelBasisMatchesPublished | modelBasis source/calc match (manufacturerTable / practicalCommunityGuidance)
- TableProfileSourceDataContractTests · testDetailsSurfaceShowsSourceReferenceRows | [presentation] Source reference contains detailTokens; no legacy Reference/Guidance boundary
- TableProfileSourceDataContractTests · testGraphCarriesSourceReferenceMarkers | [presentation] graph kind .formula, source markers match per-film, no notRecommended boundary, beyond-source start matches
- TableProfileSourceDataContractTests · testTableGraphLegendChipsMatchExpected | [presentation] required legend chips present, forbidden chips absent across sub/in/beyond samples
- TableProfileSourceDataContractTests · testGraphCurrentPointStyleAndStatusReflectRegion | [presentation] noCorrection sample → .noCorrection/"No correction"; beyond → .beyondSourceRange/"Beyond source range"
- UnofficialPracticalProfilesShapeTests · testRegistryResolvesTheUnofficialPracticalProfile | registry resolves kodak-portra-400 → id kodak-portra-400-unofficial-practical
- UnofficialPracticalProfilesShapeTests · testRegistryReturnsNilForUnknownFilmID | unknown film id → nil
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileCarriesUnofficialAuthority | source.authority==.unofficial
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileSourceKindIsThirdPartyPublication | source.kind==.thirdPartyPublication
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileCarriesFormulaRule | profile carries ≥1 .formula rule
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileHasNoLimitedGuidanceRule | profile has no .limitedGuidance rule
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileContainsOnlyKnownRuleVariants | exhaustive switch over rule variants (compiler-enforces .table absence)
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileUsesEmptyPublisherAsSourcePendingMarker | publisher=="" + nil citation/title as source-pending marker
- UnofficialPracticalProfilesShapeTests · testUnofficialPracticalProfileIsNotPartOfLaunchCatalog | unofficial profile id absent from LaunchPresetFilmCatalog
- ReciprocityFormulaFitterTests · testTwoAnchorPowerLawRecoversGeneratingConstants | Tc=2×Tm^1.4 sampled at 1s/100s → fit recovers coeff 2, exp 1.4 (1e-9)
- ReciprocityFormulaFitterTests · testMultiAnchorCleanPowerLawRecoversConstants | clean power-law a=1.2102 p=1.3423 over 4 anchors → recovers constants (1e-6)
- ReciprocityFormulaFitterTests · testFitIsDeterministicAcrossRepeatedCalls | repeated fit() on same anchors returns identical PowerLawFit
- ReciprocityFormulaFitterTests · testFitIsIndependentOfAnchorOrder | ascending vs shuffled anchors fit equally (order-independent)
- ReciprocityFormulaFitterTests · testSingleAnchorIsInsufficient | 1 anchor → .failure(.insufficientAnchors)
- ReciprocityFormulaFitterTests · testEmptyAnchorsAreInsufficient | [] → .failure(.insufficientAnchors)
- ReciprocityFormulaFitterTests · testNonPositiveMeteredIsRejected | metered=0 anchor → .failure(.nonPositiveAnchors)
- ReciprocityFormulaFitterTests · testNonFiniteCorrectedIsRejected | corrected=.nan → .failure(.nonPositiveAnchors)
- ReciprocityFormulaFitterTests · testDegenerateEqualMeteredAnchorsAreRejected | two anchors same metered=10 → .failure(.degenerateAnchors)
- UserEditableMetadataCodableTests · testReferenceTableFilmIDRoundTrips | PTIMER-180 referenceTableFilmID encodes/decodes round-trip, full equality
- UserEditableMetadataCodableTests · testLegacyPayloadWithoutLinkDecodesNil | legacy JSON lacking field → referenceTableFilmID nil, referenceURL preserved
- ReciprocityModelTests · testEvaluateProducesNoCorrectionResultForThresholdInput | bare power-law @0.5s → basis officialThresholdNoCorrection, corrected≈0.5
- ReciprocityModelTests · testEvaluateProducesFormulaDerivedResultForFormulaRangeInput | bare power-law @100s → basis formulaDerived, corrected non-nil
- ReciprocityModelTests · testMakeDetailsDisplayStateProducesNonNilForQuantifiedFormulaScenario | [presentation] details non-nil, title "Reciprocity Details"
- ReciprocityModelTests · testReciprocityStateDisplayStateForFormulaDerivedScenario | [presentation] formula-derived binding tone=.measured, showsInfoAffordance
- ReciprocityModelTests · testEvaluateMatchesDirectEvaluatorForKnownScenario | facade evaluate()==ReciprocityCalculationPolicyEvaluator (basis+corrected) @5s
- ReciprocityModelTests · testFormatReciprocityDurationCoversSubsecondToMultiDayBands | [presentation] duration fmt 0→"0s",2.13→"2.1s",125→"02:05",3725→"01:02:05",90000→"1d 01:00:00",-5→"0s"
- ReciprocityModelTests · testFormatReciprocityDurationCoarseCoarsensLargeValuesIntoMonthsAndYears | [presentation] coarse fmt: <1d falls through; 1-29d→"Nd"; 30-364d→"≈Nmo[ Nd]"; 365d+→"≈Ny"
- ReciprocityModelTests · testFormatReciprocitySecondsComparisonReturnsNilBelowOneMinuteAndAboveOneDay | [presentation] seconds-comparison nil <60s and ≥1d; 59.6→"60s"
- ReciprocityModelTests · testFormatReciprocitySecondsComparisonReturnsWholeSecondsInClockBand | [presentation] clock band → whole seconds "60s"/"1480s"/"8983s"/"86399s"
- ReciprocityModelTests · testFormatReciprocitySecondsComparisonCarriesApproximationMarker | [presentation] approximate=true → "≈6423s"
- ReciprocityModelTests · testFormatReciprocityAxisDurationUsesShortSuffixesAboveTwoMinutes | [presentation] axis fmt 119→"119s",120→"2m",3600→"1h",86400→"1d"
- ReciprocityModelTests · testCorrectedExposureDisplayStateForNilBindingFallsToNoFilmSelected | [presentation] nil binding → kind .noFilmSelected, "No film selected", non-numeric
- ReciprocityModelTests · testCorrectedExposureDisplayStateForQuantifiedFormulaBecomesNumeric | [presentation] quantified formula → kind .quantified, numeric, non-empty primary
- ReciprocityModelTests · testCorrectedExposureDisplayStateOmitsSecondsComparisonBelowOneMinute | [presentation] corrected<60s → secondaryText==""
- ReciprocityModelTests · testCorrectedExposureDisplayStateAddsSecondsComparisonInClockBand | [presentation] corrected 60s–1d → secondary = whole-seconds, ≈-marker tracks primary
- ReciprocityModelTests · testCorrectedExposureActionStateForNilBindingDisablesTimer | nil binding → canStartTimer=false, targetSeconds nil, accessibility hint set
- ReciprocityModelTests · testCorrectedExposureActionStateForQuantifiedFormulaEnablesTimer | quantified @10s → canStartTimer=true, targetSeconds≈10^1.31
- ReciprocityModelSelectionTests · testDualProfileFilmExposesBothProfilesAsModelSelection | [presentation] Portra 400 → 2 options, names [official,unofficial], labels ["Official","Unofficial"], active=official
- ReciprocityModelSelectionTests · testSingleProfileFilmHasNoModelSelection | [presentation] HP5 Plus → filmDetailsModelSelection nil, details.modelSelection nil
- ReciprocityModelSelectionTests · testSelectProfileVariantFlipsActiveProfileAndMetadata | [presentation] select unofficial → binding.profile.id flips, Source row="Practical / community guidance"
- ReciprocityModelSelectionTests · testSelectProfileVariantBackToOfficialClearsOverride | [presentation] select primary id → override cleared back to official
- ReciprocityModelSelectionTests · testMultiModelTableDefaultShowsSourceReferenceWithoutComparison | [presentation] Fomapan default: Source reference present, no App-derived comparison; Source="Manufacturer table", Calc="Log-log table interpolation"
- ReciprocityModelSelectionTests · testMultiModelAppDerivedFormulaSeparatesComparisonFromSourceReference | [presentation] Fomapan app-derived: both sections present; source ref no app deltas, comparison has "App "
- ReciprocityModelSelectionTests · testMultiModelTableRendersGraphWithAnchorsAndCurrentPoint | [presentation] Fomapan table graph: ≥2 sourcePoints, non-empty markers, currentPoint non-nil
- ReciprocityModelSelectionTests · testMultiModelTableBeyondSourceShowsBeyondSourceRangeWithValueAndNoFormulaWording | [presentation] Fomapan @1000s → corrected non-nil (extrapolated), badge="Beyond source range", no formula/no-prediction/outside-range wording
- ReciprocityModelSelectionTests · testMainScreenActiveModelSummaryIsTwoLineSourceAndCalculation | [presentation] Fomapan summary name="Official FOMA table", calculation="Log-log interpolation"
- ReciprocityModelSelectionTests · testMultiModelSelectorLabelsAreShortButNamesStayFull | [presentation] Fomapan labels ["Official table","Ohzart","App formula"], names full 3-model list
- ReciprocityModelSelectionTests · testMultiModelOfficialTableBadgeIsTableDerivedNotFormulaDerived | [presentation] Fomapan official table @10s badge="Table-derived"; app-derived badge="Formula-derived"
- ReciprocityModelSelectionTests · testMultiModelSubtitleNamesActiveModelNotPlainOfficialGuidance | [presentation] subtitle "…· Official FOMA table"; app-derived "…· App-derived formula", not "Official guidance"
- ReciprocityModelSelectionTests · testModelSelectorLabelPrefersExplicitElseDerives | [presentation] explicit selectorLabel "Ohzart" wins; nil → heuristic "Unofficial"
- ReciprocityModelMetadataPresenterTests · testSectionIsCompactSourceAndCalculationOnly | [presentation] HP5 section title="Reciprocity model", rows=["Source","Calculation"] only
- ReciprocityModelMetadataPresenterTests · testManufacturerFormulaProfileMapsToGuardedFormula | [presentation] HP5 → Source="Manufacturer formula", Calc="Guarded formula"
- ReciprocityModelMetadataPresenterTests · testMultiModelDefaultIsManufacturerTableLogLogInterpolation | [presentation] Fomapan default → Source="Manufacturer table", Calc="Log-log table interpolation"
- ReciprocityModelMetadataPresenterTests · testMultiModelAppDerivedAlternateReadsAppDerivedGuardedFormula | [presentation] Fomapan app-derived → Source="Manufacturer table", Calc="App-derived guarded formula"
- ReciprocityModelMetadataPresenterTests · testManufacturerLimitedGuidanceProfile | [presentation] Ektar 100 → Source="Manufacturer limited guidance", Calc="Limited guidance — no quantified prediction"
- ReciprocityModelMetadataPresenterTests · testTriXModelsDistinguishGraphTableFromPublishedTable | [presentation] Tri-X: default graph/table+log-log; official-table=table+log-log; app-formula=graph/table+app-derived guarded formula
- ReciprocityModelMetadataPresenterTests · testRangeGuidanceProfileReadsManufacturerRangeGuidance | [presentation] Acros II → Source="Manufacturer range guidance", Calc="Guarded formula"
- ReciprocityModelMetadataPresenterTests · testTableSourceProfilesWithFittedFormulaReadAppDerived | [presentation] Velvia50/100,Provia100F,RETRO80S,SUPERPAN200,CMS20II → Source="Manufacturer table", Calc="App-derived guarded formula"
- ReciprocityModelMetadataPresenterTests · testAllLimitedGuidanceProfilesReadLimitedGuidance | [presentation] Portra160/400,Gold200,UltraMax400,Ektachrome E100 → Source="Manufacturer limited guidance", Calc="Limited guidance — no quantified prediction"
- ReciprocityModelMetadataPresenterTests · testUnofficialPracticalProfileMapsToPracticalGuidance | [presentation] Portra 400 unofficial → Source="Practical / community guidance", Calc="Guarded formula"
- ReciprocityModelMetadataPresenterTests · testPromotedUnofficialPracticalPrimaryDoesNotReadAsManufacturerTable | [presentation] RETRO 400S primary → Source="Practical / community guidance" (not "Manufacturer table")
- ReciprocityDetailsVocabularyPresenterTests · testBadgeTextReflectsPresentationState | [presentation] badge: Provia@240→"Formula-derived", HP5@0.5→"No correction", Provia@1800→"Beyond source range", Portra@30→"No quantified prediction"
- ReciprocityDetailsVocabularyPresenterTests · testStatusTextEchoesBadgeForFormulaProfileEvenWhenGraphIsBeyondVisibleRange | [presentation] Provia@240 keeps statusText="Formula-derived" despite beyond-visible graph
- ReciprocityDetailsVocabularyPresenterTests · testSummaryTextReflectsPresentationState | [presentation] summary: Provia@240→"Formula-based correction on the active curve", Provia@1800→"Beyond source range", Portra@30→"Beyond published no-correction range"
- ReciprocityDetailsVocabularyPresenterTests · testUnofficialProfileSummaryDetailLeadsWithProfileNoteCaveat | [presentation] Portra unofficial → summaryDetail == first profile note (authority caveat leads)
- ReciprocityDetailsVocabularyPresenterTests · testFormulaSupportedSummaryDetailIsNil | [presentation] HP5@30s in-range → summaryDetail nil
- ReciprocityDetailsVocabularyPresenterTests · testOfficialTableBeyondSourceSummaryDetailKeepsPublishedOfficialCopy | [presentation] Fomapan@120s → summaryDetail = published-official extrapolation copy
- ReciprocityDetailsVocabularyPresenterTests · testUnofficialTableBeyondSourceSummaryDetailDoesNotSayOfficial | [presentation] community table@120s → detail "community table anchor", no "official"/"published"
- ReciprocityDetailsVocabularyPresenterTests · testReciprocityStateDisplayStateAgreesWithBadgeAndTone | [presentation] Portra@5 displayState.badgeText/tone == presenter badge/tone, showsInfoAffordance
- ReciprocityDetailsVocabularyPresenterTests · testUserDefinedFormulaBadgeReadsCustomFormula | [presentation] user-defined formula@30 → badge="Custom formula"
- ReciprocityDetailsVocabularyPresenterTests · testUserDefinedFormulaInRange_useMeasuredTone_notCaution | [presentation] PTIMER-84 user-defined in-range → category formulaDerived, tone=.measured (not caution)
- ReciprocityDetailsVocabularyPresenterTests · testToneReflectsCalculationStateNotSourceAuthority | [presentation] PTIMER-164: across FOMA/Ohzart/app/Portra-unofficial, tone reflects calc state (trusted/measured/unsupported/nil), never caution
- CalculationBasisPresenterTests · test_basic_collapsesToSimpleExponentShape | [presentation] basic coef 1/ref 1s/offset 0 → "Tc = Tm^1.3"
- CalculationBasisPresenterTests · test_scaled_rendersAnchoredShape | [presentation] TMAX scaled → "Tc = 0.1s × (Tm / 0.1s)^1.0966"
- CalculationBasisPresenterTests · test_scaled_taskExampleRenders | [presentation] scaled coef3/ref2s/exp1.29 → "Tc = 3s × (Tm / 2s)^1.29"
- CalculationBasisPresenterTests · test_advanced_taskExampleRenders | [presentation] advanced coef10/ref3s/exp1.30/offset0.3 → "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"
- CalculationBasisPresenterTests · test_unparseableForm_returnsNil | [presentation] empty form (no exponent) → nil (block suppressed)
- CalculationBasisPresenterTests · test_profileOverload_matchesFormOverload_forSameInputs | [presentation] form vs profile overload parity → both "Tc = 3s × (Tm / 2s)^1.29"
- CalculationBasisPresenterTests · test_profileWithoutFormulaRule_returnsNil | [presentation] threshold-only profile (no formula rule) → nil

## C — Catalog + custom-film domain (~190 tests)

**[verdict]** ✅ **already-covered / blocker→done** for the protected
catalog and custom **domain**: 37-film load / canonical order / launch-policy
shape rules / per-manufacturer membership / per-film formula+threshold
constants / provenance (`CatalogCoreTest` + new `CatalogPerFilmParityTest`),
and custom-film validation + sanitation (no-shortening guard, single-rule
shape, table/formula drop-cases) in `CustomFilmTest` incl. the new
`libraryRejectsMalformedCustomShapes`. Files prefixed `[editor-ui]` are the
iOS SwiftUI custom-film **editor** (token editor, anchored-formula form,
input modes, live-check, reset/revert, preview graph, inline validation,
save-disabled reasons) → **follow-up / android-replacement** (Android ships a
simpler editor). `PersistentCustomFilmLibraryTests` (concrete UserDefaults)
→ Android `CustomFilmLibraryCodec` fail-safe is covered.

Recorded intent (iOS file · test — intent):



#### LaunchPresetFilmCatalogTests.swift
- LaunchPresetFilmCatalogTests | testBundledLaunchPresetFilmCatalogLoadsSuccessfully | bundled JSON loads; count == scopeCount(37) & canonical order matches
- LaunchPresetFilmCatalogTests | testBundledLaunchPresetFilmCatalogPreservesExpectedSelectorOrdering | static `LaunchPresetFilmCatalog.films` count(37) + canonical order matches
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogRespectsPTIMER86LaunchPolicyConstraints | every film: kind=preset, status=current, exactly 1 profile; official/high source except rollei-retro-400s (unofficial/medium/Lafitte); no userMetadata
- LaunchPresetFilmCatalogTests | testLaunchCatalogContainsExpectedProfilesPerManufacturer | per-manufacturer membership counts+names: ILFORD 12, Kodak 9, Fujifilm 4, FOMA 3, Rollei 7, ADOX 2
- LaunchPresetFilmCatalogTests | testBarePowerLawCatalogEntriesPreserveOneSecondNoCorrectionBoundary | ILFORD family ships formula profiles w/ noCorrectionThroughSeconds==1
- LaunchPresetFilmCatalogTests | testLaunchCatalogPreservesBarePowerLawFormulaExponents | pins 12 ILFORD exponents (Pan F 1.33 … Kentmere400 1.30)
- LaunchPresetFilmCatalogTests | testLaunchCatalogExcludesNonLaunchReadyFilms | excludes Kodak motion-picture, weak-source mfrs, archival Kodak, non-ready Rollei/FOMA/ADOX stocks
- LaunchPresetFilmCatalogTests | testLaunchCatalogDoesNotDuplicateFilmOrProfileIdentifiers | film IDs + profile IDs unique
- LaunchPresetFilmCatalogTests | testLaunchCatalogDoesNotShipUnofficialPracticalProfileAsPrimary | Portra 400 primary = official/manufacturerPublished, id !contains "unofficial", exponent != 1.34
- LaunchPresetFilmCatalogTests | testRetro400SShipsPromotedUnofficialPracticalPrimary | RETRO 400S primary is promoted unofficial-practical (Lafitte, exp 1.62, noCorr 1, sourceRange 15, practicalCommunityGuidance/guardedFormula)
- LaunchPresetFilmCatalogTests | testRetro400SFormulaMatchesPublishedPracticalAnchorsApproximately | RETRO 400S: 1s→no-correction; 5/10/15s ≈ 13.5/41/80s (evaluator)
- LaunchPresetFilmCatalogTests | testLoaderRejectsArbitraryUnofficialPrimaryProfile | loader rejects arbitrary unofficial primary → .invalidPrimaryProfileSource
- LaunchPresetFilmCatalogTests | testLaunchCatalogPreservesPublisherAndCitationsForBatchExemplars | publisher/citation fragments preserved for 13 exemplars
- LaunchPresetFilmCatalogTests | testBarePowerLawProfileEvaluatesPastThreshold | HP5 @4s → quantified, basis=formulaDerived, 4^1.31
- LaunchPresetFilmCatalogTests | testBarePowerLawProfileReturnsNoCorrectionAtThreshold | HP5 @0.5s → basis=officialThresholdNoCorrection, corrected=0.5
- LaunchPresetFilmCatalogTests | testTableProfileQuantifiesInsidePublishedRange | T-MAX 100 (table) @4s → tableLogLogDerived ≈5.60s
- LaunchPresetFilmCatalogTests | testTableProfilesPreserveNoCorrectionThresholdBand | Tri-X/T-MAX100/T-MAX400 @0.05s → officialThresholdNoCorrection, corrected=metered
- LaunchPresetFilmCatalogTests | testTableProfileContinuesBeyondPublishedSourceRangeAsUnsupportedNumeric | Tri-X @1500s → unsupportedOutOfPolicyRange, corrected non-nil
- LaunchPresetFilmCatalogTests | testTableProfileReproducesPublished1SecondRow | Tri-X @1s → tableLogLogDerived, corrected=2 (anchor exact)
- LaunchPresetFilmCatalogTests | testLimitedGuidanceProfileReturnsNoQuantifiedPredictionBeyondThreshold | Portra 400 @30s → limitedGuidanceNoQuantifiedPrediction
- LaunchPresetFilmCatalogTests | testLimitedGuidanceProfileNoCorrectionInOfficialRange | Portra 400 @0.5s → officialThresholdNoCorrection, corrected=0.5
- LaunchPresetFilmCatalogTests | testConvertedFormulaProfileAboveSourceRangeIsBeyondSourceWithFormulaPrediction | Velvia 50 @80s (>32 source range) → unsupportedOutOfPolicyRange, corrected non-nil
- LaunchPresetFilmCatalogTests | testTableProfileReproducesPublishedMultiplierRowExactly | Fomapan 100 @1s → tableLogLogDerived, corrected=2 (anchor exact)
- LaunchPresetFilmCatalogTests | testGuardedFormulaRangeRowsArePreservedAsSourceEvidenceNotesRatherThanInvented | RETRO 80S: range-valued 1s row kept in sourceEvidence as "1 to 2 sec" note, NOT flattened to quantified exposure
- LaunchPresetFilmCatalogTests | testLimitedGuidanceProfilePreservesFiltrationGuidance | Ektachrome E100 limited-guidance rule preserves CC10R colorFilter adjustment
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogRejectsDuplicateFilmIdentifiers | loader → .duplicateFilmIdentifier + errorDescription text
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogRejectsInvalidCanonicalStockNames | blank canonical name → .invalidCanonicalStockName
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogRejectsDuplicateCanonicalStockNames | dup canonical name → .duplicateCanonicalStockName
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogMissingResourceFailsSafely | missing resource → .missingBundledResource
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogMalformedResourceFailsSafely | "{" → .malformedResource
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogDecodeFailureReportsMissingKeyAndCodingPath | missing iso/profiles → malformedResource reason contains "Missing key" + "[0]"
- LaunchPresetFilmCatalogTests | testLaunchPresetFilmCatalogValidationFailureDescriptionsNameOffendingEntry | 0 profiles → .invalidPrimaryProfileCount + errorDescription text


#### LaunchPresetFilmCatalogShapeTests.swift
- LaunchPresetFilmCatalogShapeTests | testLaunchPresetProfilesUseOnlySupportedRuleKinds | all rules ∈ {threshold,formula,limitedGuidance,tableInterpolation}; Fomapan 100 ships tableInterpolation
- LaunchPresetFilmCatalogShapeTests | testEveryLaunchPresetProfileMatchesAnAllowedShape | every profile classifies to an allowed launch shape (non-nil)
- LaunchPresetFilmCatalogShapeTests | testFormulaProfileReferenceDataLivesInSourceEvidenceOnly | formula profiles: threshold rule carries no quantified adjustments (ref data only in sourceEvidence)
- LaunchPresetFilmCatalogShapeTests | testLimitedGuidanceProfilesDoNotCarryAFormulaRule | limited-guidance profiles never carry a formula rule
- LaunchPresetFilmCatalogShapeTests | testLimitedGuidanceProfilesHaveEmptySourceEvidence | limited-guidance profiles keep sourceEvidence empty
- LaunchPresetFilmCatalogShapeTests | testLaunchPresetPresentationDoesNotUseLegacyTableWording | shortLabel never contains Exact/Estimated/Interpolated/Extrapolated/Advisory across metered samples
- LaunchPresetFilmCatalogShapeTests | testClassifyAcceptsOfficialFormulaOnlyAndRejectsEveryOtherShape | classifier: official formula-only→officialQuantifiedFormula; mixed/unofficial/user/unknown/formula+threshold→nil
- LaunchPresetFilmCatalogShapeTests | testLoaderRejectsFormulaProfileCarryingThresholdCompanion | loader → invalidRuleShape "formula profiles must not carry a companion threshold rule"
- LaunchPresetFilmCatalogShapeTests | testLoaderRejectsProfileMixingFormulaAndLimitedGuidance | loader → invalidRuleShape "formula and limited-guidance rules cannot coexist"
- LaunchPresetFilmCatalogShapeTests | testLoaderRejectsThresholdOnlyProfile | loader → invalidRuleShape "must declare formula or threshold+limited-guidance pair"
- LaunchPresetFilmCatalogShapeTests | testLoaderRejectsLimitedGuidanceProfileCarryingSourceEvidence | loader → invalidRuleShape "limited-guidance profiles cannot carry sourceEvidence rows"


#### CustomFilmCreateFormulaTests.swift (PTIMER-180; KEY parity flags)
- CustomFilmCreateFormulaTests | testCreatingFormulaSeedsFromTableFitAndLinks | creatingFormula(fromTable:) seeds .formula kind, pre-links referenceTableFilmID, auto-label "Acme 100 Formula", iso "100"; seeded params == shared fitted-preview (CustomTableFittedFormulaPresenter)
- CustomFilmCreateFormulaTests | testCreatingFormulaUnavailableForIneligibleTable | ineligible (short/non-curved) table → nil seed
- CustomFilmCreateFormulaTests | testCreatingFormulaNilForFormulaOrPresetFilm | formula film & preset film → nil seed (only tables seed)
- CustomFilmCreateFormulaTests | testSavedFormulaIsIndependentFormulaProfileWithPersistedLink | **SEPARATE formula film**: id != table.id, profile has formula rule + NO table rule (calc independent of table); referenceTableFilmID persists at film level
- CustomFilmCreateFormulaTests | testEditRoundTripPreservesLink | reopen saved linked formula preserves referenceTableFilmID + .formula kind
- CustomFilmCreateFormulaTests | testReferencePointRowsMergeTableAnchorsWithErrorAndDedup | reference rows = samples ∪ anchors deduped; anchor row Tc from **table anchor** (display-only) + stopError; standard-only row no reference/error
- CustomFilmCreateFormulaTests | testReferencePointRowsWithoutLinkHaveNoReferenceOrError | no link → no reference values / no error (inspection-only when linked)
- CustomFilmCreateFormulaTests | testFormulaPreviewGraphShowsLinkedReferenceMarkersOnlyWhenLinked | linked graph shows table anchors as source-reference markers (overlay only, curve stays formula, currentPoint present); unlinked → no markers
- CustomFilmCreateFormulaTests | testResolverHydratesSavedFormulaLinkFromPersistedMetadata | resolver re-hydrates linked table anchors from referenceTableFilmID; not missing
- CustomFilmCreateFormulaTests | testResolverReflectsEditedTableAnchorsWithoutTouchingFormula | resolver returns edited table's new anchors (10→50) — reference reflects table, formula untouched
- CustomFilmCreateFormulaTests | testResolverMarksMissingWhenLinkedTableDeleted | deleted linked table → isLinkedButMissing=true, anchors empty
- CustomFilmCreateFormulaTests | testResolverEmptyForUnlinkedFormula | unlinked formula → not missing, anchors empty


#### CustomFilmAnchoredFormulaTests.swift
- CustomFilmAnchoredFormulaTests | test_defaults_areOneOneZero | default baseTm="1", baseTc="1", offset=""
- CustomFilmAnchoredFormulaTests | test_validate_defaultAnchors_storesUnitCoefficient | baseTm=baseTc=1 → coeff=1, refTm=1, exp=1.33, offset=0, noCorr=1, sourceRange nil
- CustomFilmAnchoredFormulaTests | test_anchorPair_persistsOnSharedFormula | T-MAX example: baseTm/Tc=0.1, exp=1.0966 land on shared formula (coeff/refMeteredTime), no side-channel
- CustomFilmAnchoredFormulaTests | test_fromFilm_readsAnchorsFromSharedFormula | from(film:) reads anchors back: baseTm/Tc="0.1", exp "1.0966", manufacturer "Kodak"
- CustomFilmAnchoredFormulaTests | test_previewPresenter_usesBaseTmAndBaseTc | preview @8s = 0.1·(8/0.1)^1.0966, status=formulaApplied
- CustomFilmAnchoredFormulaTests | test_previewPresenter_unlimitedValidThrough_doesNotEmitBeyondRangeRows | Unlimited → no beyondSourceRange rows
- CustomFilmAnchoredFormulaTests | test_previewPresenter_finiteValidThrough_emitsBeyondRangeRows | validThrough=30 → 60/300s rows beyondSourceRange
- CustomFilmAnchoredFormulaTests | test_selectedCustomFilm_calculatesUsingAnchorPair | VM calc @8s = anchored formula value
- CustomFilmAnchoredFormulaTests | test_anchorRoundsTripThroughLibraryUpsert | library add → stored formula keeps coeff/refMeteredTime 0.1


#### CalculatorViewModelCustomFilmCalculationTests.swift (class CustomFilmCalculationFlowTests)
- CustomFilmCalculationFlowTests | test_selectedCustomFilm_producesQuantifiedCorrectedExposure | custom exp1.30 @5s → quantified, 5^1.30
- CustomFilmCalculationFlowTests | test_customProfile_correctedExposureExceedsAdjustedForPositiveExponent | exp1.45 → corrected > adjusted
- CustomFilmCalculationFlowTests | test_customProfile_correctedExposureScalesWithCoefficientAndOffset | coeff1.10/offset0.5 → 1.10·5^1.30+0.5
- CustomFilmCalculationFlowTests | test_customSelection_presentationUsesCustomShortLabel | binding authority=userDefined, shortLabel contains "custom"
- CustomFilmCalculationFlowTests | test_customSelection_filmSelectionDisplayState_subtitleIsCustom | display primary=stockName, secondary="Custom"
- CustomFilmCalculationFlowTests | test_presetFilmCalculation_isUnaffectedByCustomLibraryUsage | preset Provia adjusted/corrected identical before/after custom-library use
- CustomFilmCalculationFlowTests | test_presetFilmCalculation_neverShowsCustomAuthorityLabel | preset authority=official, shortLabel !contains "custom"


#### CalculatorViewModelCustomFilmTimerTests.swift
- CalculatorViewModelCustomFilmTimerTests | test_startTimer_fromCustomCorrectedExposure_createsRunningTimer | start → 1 running timer, source=filmCorrectedExposure, filmDisplayName "Custom Stock", qualifier "Custom"
- CalculatorViewModelCustomFilmTimerTests | test_identitySnapshot_preservesCustomProfileSummary | snapshot summary contains profile name, "ISO 100", "User-defined", "Tc", "1.3"
- CalculatorViewModelCustomFilmTimerTests | test_identitySnapshot_includesSourceTypeLabel | summary contains "Personal test" for personalTest source
- CalculatorViewModelCustomFilmTimerTests | test_identitySnapshot_remainsStable_afterCustomProfileDeleted | **snapshot byte-identical after library.remove**; displayName/qualifier/summary retained
- CalculatorViewModelCustomFilmTimerTests | test_presetTimer_identitySnapshot_omitsCustomSummary | preset timer: qualifier nil, customProfileSummary nil
- CalculatorViewModelCustomFilmTimerTests | test_persistedMetadata_roundTripsCustomProfileSummary | PersistentTimerMetadataSnapshot encodes/decodes customProfileSummary
- CalculatorViewModelCustomFilmTimerTests | test_persistedMetadata_decodesLegacyPayloadWithoutCustomSummary | legacy payload (no key) → customProfileSummary nil, other fields decode
- CalculatorViewModelCustomFilmTimerTests | test_customProfileFormulaText_handlesCoefficientAndOffset | shared FormulaEquationFormatter: "Tc = Tm^1.3", "+ 1.1 ×", "+ 0.5s", "- 0.25s" collapse rules


#### CustomFilmTableProfileFlowTests.swift (PTIMER-178; KEY parity flags)
- CustomFilmTableProfileFlowTests | test_library_acceptsValidTableProfile | valid table kept
- CustomFilmTableProfileFlowTests | test_library_acceptsValidFormulaProfile | valid formula kept
- CustomFilmTableProfileFlowTests | test_library_add_acceptsValidTableProfile | add() accepts table
- CustomFilmTableProfileFlowTests | test_library_dropsTableProfile_withSingleAnchor | single-anchor table dropped (sanitation)
- CustomFilmTableProfileFlowTests | test_library_acceptsTableProfile_withUnsortedAnchors | unsorted anchors OK at storage (domain sorts)
- CustomFilmTableProfileFlowTests | test_library_dropsTableProfile_withDuplicateMeteredAnchors | dup metered dropped
- CustomFilmTableProfileFlowTests | test_library_dropsTableProfile_withShorteningAnchor | shortening anchor (10→5) dropped
- CustomFilmTableProfileFlowTests | test_library_dropsTableProfile_withZeroNoCorrection | noCorrection=0 dropped (stricter than domain)
- CustomFilmTableProfileFlowTests | test_library_dropsTableProfile_withNonFiniteAnchor | infinity anchor dropped
- CustomFilmTableProfileFlowTests | test_library_keepsFormulaProfile_alongsideTableProfile | formula+table coexist, order preserved
- CustomFilmTableProfileFlowTests | test_library_dropsProfile_withMixedFormulaAndTableRules | mixed formula+table rules dropped
- CustomFilmTableProfileFlowTests | test_library_dropsProfile_withTwoFormulaRules | two formula rules dropped
- CustomFilmTableProfileFlowTests | test_library_dropsProfile_withTwoTableRules | two table rules dropped
- CustomFilmTableProfileFlowTests | test_persistentSnapshot_roundTripsTableProfile | snapshot encode/decode equal; 3 anchors + 3 sourceEvidence rows
- CustomFilmTableProfileFlowTests | test_libraryWithStore_restoresTableProfile | store round-trip restores table film
- CustomFilmTableProfileFlowTests | test_selectedTableProfile_reproducesAnchorExactly | VM @10s → 80 exact (anchor)
- CustomFilmTableProfileFlowTests | test_selectedTableProfile_interpolatesBetweenAnchorsInLogLogSpace | @30s → log-log interp between (10,80)/(100,1600)
- CustomFilmTableProfileFlowTests | test_tableCalculation_readsRuleAnchors_notSourceEvidence | **calc reads rule anchors NOT sourceEvidence**: corrupted (×1000) evidence yields same 80 result
- CustomFilmTableProfileFlowTests | test_detailsBadge_inRange_readsCustomTable | badge "Custom table" in range
- CustomFilmTableProfileFlowTests | test_detailsBadge_beyondSourceRange_readsBeyondSourceRange | @500s badge "Beyond source range", corrected non-nil
- CustomFilmTableProfileFlowTests | test_detailsSummary_customTableBeyondSource_usesNeutralTableCopy | neutral copy "extrapolated past the last table anchor"; no "published"/"official"
- CustomFilmTableProfileFlowTests | test_detailsBadge_customFormula_unchanged | custom formula badge "Custom formula"
- CustomFilmTableProfileFlowTests | test_detailsSummary_customFormulaDetailText_unchanged | custom formula summaryDetailText nil
- CustomFilmTableProfileFlowTests | test_customRangeLines_tableProfile_reportBothBoundaries | range lines ["No correction through 0.10s","Source range through 100s (1m 40s)"]
- CustomFilmTableProfileFlowTests | test_timerIdentity_distinguishesTableProfile | timer qualifier "Custom"; summary "Custom table · 3 anchors" + "ISO 100"
- CustomFilmTableProfileFlowTests | test_customProfileCalculationText_formulaProfile_staysFormulaText | formula profile calc text not "Custom table"


#### CustomFilmDetailsCalculationBasisTests.swift (PTIMER-84)
- CustomFilmDetailsCalculationBasisTests | test_customFormulaProfile_addsCalculationBasisSection_aheadOfCustomProfileSection | "Calculation basis" section renders before "Custom profile"
- CustomFilmDetailsCalculationBasisTests | test_customFormulaProfile_calculationBasisSection_carriesFormulaExpressionRow | one formulaExpression row "Tc = 0.1s × (Tm / 0.1s)^1.0966"
- CustomFilmDetailsCalculationBasisTests | test_customFormulaProfile_graphHeader_doesNotCarryFormulaText | custom graph header formulaDisplayText nil (defers to basis section)
- CustomFilmDetailsCalculationBasisTests | test_presetFormulaProfile_keepsGraphHeaderFormula_andHasNoBasisSection | preset HP5 keeps graph-header formula, no Calculation basis section


#### CustomFilmLibraryReloadTests.swift
- CustomFilmLibraryReloadTests | test_savedProfiles_surviveReloadInOrderIntoNewInstance | reload preserves order alpha/beta/gamma + stock name
- CustomFilmLibraryReloadTests | test_savedProfile_roundTripsAllFieldsAndFormula | reload preserves id/name/iso/sourceType/notes + formula exp/coeff/offset
- CustomFilmLibraryReloadTests | test_removeProfile_persistsDeletion | remove persists across reload


#### CustomFilmLibraryTests.swift
- CustomFilmLibraryTests | test_initWithoutSeed_isEmpty | empty init
- CustomFilmLibraryTests | test_add_appendsCustomFilm | add appends
- CustomFilmLibraryTests | test_add_preservesInsertionOrder | insertion order preserved
- CustomFilmLibraryTests | test_add_rejectsNonCustomKind | preset kind rejected
- CustomFilmLibraryTests | test_add_withDuplicateID_replacesInPlace | dup id upserts in place (count 2, v2 first)
- CustomFilmLibraryTests | test_remove_dropsMatchingEntry | remove drops matching
- CustomFilmLibraryTests | test_remove_unknownID_isNoOp | unknown remove no-op
- CustomFilmLibraryTests | test_initial_dropsMalformedEntries | blank id/name + preset dropped, only "ok" kept
- CustomFilmLibraryTests | test_filmWithID_returnsMatch | film(withID:) returns match / nil


#### CustomFilmDeleteFlowTests.swift
- CustomFilmDeleteFlowTests | test_deleteCustomFilm_removesFromSelectorEntries | delete removes from customFilms + selector entries
- CustomFilmDeleteFlowTests | test_deleteCurrentlySelectedCustomFilm_clearsSelection | delete active clears selection/entryID/workflow
- CustomFilmDeleteFlowTests | test_deleteUnselectedCustomFilm_doesNotChangeActiveSelection | delete other keeps active selection
- CustomFilmDeleteFlowTests | test_deletionPersists_acrossLibraryReload | deletion survives reload
- CustomFilmDeleteFlowTests | test_deletingActiveCustomFilm_leavesAlreadyStartedTimerSnapshotIntact | **running timer snapshot byte-identical after delete**
- CustomFilmDeleteFlowTests | test_deleteCustomFilm_doesNotTouchPresetCatalog | preset count + Provia unchanged after custom delete


#### CustomFilmStabilizationGuardTests.swift (no-shortening guard)
- CustomFilmStabilizationGuardTests | test_validate_unlimitedValidThrough_withSubUnitExponent_rejected | exp0.5 Unlimited → .formulaShortensExposure
- CustomFilmStabilizationGuardTests | test_validate_finiteValidThrough_subUnitExponent_rejectedAtUpper | exp0.5 finite → shortens at upper bound
- CustomFilmStabilizationGuardTests | test_validate_exponentOne_unlimited_baseTcLessThanBaseTm_rejected | Tc=0.5·Tm → shortens
- CustomFilmStabilizationGuardTests | test_validate_exponentAboveOne_unitAnchors_passes | exp1.30 unit anchors passes
- CustomFilmStabilizationGuardTests | test_sanitation_dropsProfileWithSubUnitExponent_unlimited | sanitation drops shortening formula
- CustomFilmStabilizationGuardTests | test_sanitation_keepsValidAnchoredFormula | keeps valid anchored T-MAX
- CustomFilmStabilizationGuardTests | test_previewRow_marksShorteningSampleAsInvalid | shortening sample → .invalidFormulaResult but still reports computed Tc


#### CustomFilmStabilizationFixesTests.swift
- CustomFilmStabilizationFixesTests | test_canonicalCustomFilmID_returnsFilmIDForCustomEntry | canonicalCustomFilmID = film id for custom
- CustomFilmStabilizationFixesTests | test_canonicalCustomFilmID_isNilForPresetAndNoFilmEntries | nil for preset / no-film sentinel
- CustomFilmStabilizationFixesTests | test_analyticGuard_rejectsConvexInteriorMinimum | guard catches interior minimum (exp2 offset-0.1)
- CustomFilmStabilizationFixesTests | test_analyticGuard_rejectsSubUnitExponentWithUnlimited | exp0.5 unlimited rejected
- CustomFilmStabilizationFixesTests | test_analyticGuard_acceptsValidPowerLaw | exp1.30 accepted
- CustomFilmStabilizationFixesTests | test_analyticGuard_linearCaseUnlimitedRequiresUnitCoefficient | exp1 coeff1 ok, coeff0.5 rejected
- CustomFilmStabilizationFixesTests | test_analyticGuard_nonShorteningSlackMatchesRuntimeEvaluator | guard slack==runtime 1e-6; offsets -0.5e-6 pass / -2e-6,-5e-4 fail; evaluator agrees
- CustomFilmStabilizationFixesTests | test_baseAnchor_rejectsUnlimitedKeyword | baseTm="Unlimited" → .invalidBaseTm
- CustomFilmStabilizationFixesTests | test_offset_rejectsUnlimitedKeyword | offset="Unlimited" → .invalidFormulaOffset
- CustomFilmStabilizationFixesTests | test_baseAnchor_acceptsDurationSuffixes | "1s"/"2s" parse to 1.0/2.0
- CustomFilmStabilizationFixesTests | test_previewParser_rejectsInvalidBaseTm_eliminatesSilentFallback | baseTm="abc" → parse nil (no silent fallback)
- CustomFilmStabilizationFixesTests | test_previewParser_partialInvalidOffset_returnsNil | offset="-" → parse nil


#### CustomFilmStabilizationFormTests.swift
- CustomFilmStabilizationFormTests | test_validate_succeeds_withoutProfileName_whenManufacturerAndLabelPresent | no profileName ok; name="Kodak T-MAX 100 · ISO 100", canonical="Kodak T-MAX 100"
- CustomFilmStabilizationFormTests | test_validate_doesNotEmitMissingProfileNameAnymore | empty label → .missingFilmLabel not .missingProfileName
- CustomFilmStabilizationFormTests | test_composeDisplayName_appendsISOWhenISOProvided | "Mfr Label · ISO n"
- CustomFilmStabilizationFormTests | test_composeDisplayName_handlesMissingSegments | label-only / mfr+label no ISO
- CustomFilmStabilizationFormTests | test_durationParser_plainAndSuffixed | 100/100s/5m/1h/0.5m parse
- CustomFilmStabilizationFormTests | test_durationParser_unlimitedKeyword | "Unlimited"/"unlimited" → .unlimited
- CustomFilmStabilizationFormTests | test_durationParser_emptyAndInvalid | ""/"  "→.empty; abc/100x/xh→nil
- CustomFilmStabilizationFormTests | test_validate_acceptsDurationSuffixesForValidThrough | "5m"→sourceRange 300
- CustomFilmStabilizationFormTests | test_validate_rejectsMalformedDurationString | "100x"→.invalidValidThrough
- CustomFilmStabilizationFormTests | test_validate_rejectsUnlimitedForNoCorrectionThrough | noCorr "Unlimited"→.invalidNoCorrectionThrough
- CustomFilmStabilizationFormTests | test_preview_emptyAnchors_useDefault | empty anchors → baseTm/Tc 1, offset 0, validThrough nil
- CustomFilmStabilizationFormTests | test_preview_invalidBaseTm_yieldsNilParse | baseTm abc → nil + all rows invalid
- CustomFilmStabilizationFormTests | test_preview_invalidBaseTc_yieldsNilParse | baseTc abc → nil
- CustomFilmStabilizationFormTests | test_preview_invalidOffset_yieldsNilParse | offset abc → nil
- CustomFilmStabilizationFormTests | test_preview_invalidValidThrough_yieldsNilParse | validThrough bad → nil
- CustomFilmStabilizationFormTests | test_preview_emptyValidThrough_treatedAsUnlimited | empty → validThrough nil
- CustomFilmStabilizationFormTests | test_preview_durationSuffixedValidThrough_parses | "5m"→300


#### CustomFilmRangeGuardTests.swift
- CustomFilmRangeGuardTests | test_editorBuiltProfile_carriesThresholdAndFormulaRules | editor profile: boundaries on shared formula (noCorr 1, sourceRange 60), no separate threshold rule
- CustomFilmRangeGuardTests | test_meteredBelowNoCorrectionThreshold_yieldsNoCorrection | @0.5s → corrected=0.5 (no-correction band)
- CustomFilmRangeGuardTests | test_meteredBeyondValidThrough_stillCalculatesCorrectedTimer | @120s >sourceRange30 → corrected=120^1.30 + timer still startable (confidence flag not block)
- CustomFilmRangeGuardTests | test_sanitation_keepsThresholdPlusFormulaShape | valid threshold+formula shape kept


#### CustomFilmProvenanceDetailsTests.swift
- CustomFilmProvenanceDetailsTests | test_customProvenance_listsSourceTypeFormulaRangeAndNotes | provenance text lists "Personal test", Tc/1.3, "No correction through 1s", "Source range through 240s (4m)", notes
- CustomFilmProvenanceDetailsTests | test_customProvenance_doesNotPresentOfficialWording | no official/manufacturer/kodak/fuji wording
- CustomFilmProvenanceDetailsTests | test_customProfileSection_emitsOneRowPerFact | section "Custom profile" rows [Source,Range,Notes]; no formulaExpression row (no dup of graph formula)
- CustomFilmProvenanceDetailsTests | test_customProfileSection_unlimitedSourceRange_rendersUnlimitedLine | range rows ["No correction through 1s","Source range unlimited"]
- CustomFilmProvenanceDetailsTests | test_customProfileSection_returnsNilForPresetProfile | preset Provia → nil custom section
- CustomFilmProvenanceDetailsTests | test_summaryDetailText_returnsNilForUserDefinedProfile | userDefined → summaryDetailText nil (provenance lives in section)


#### CustomFilmAutoSelectAfterSaveTests.swift (PTIMER-84)
- CustomFilmAutoSelectAfterSaveTests | test_newCustomFilmFlow_addThenSelect_marksFilmAsSelected | new flow add+select → selectedEntryID/film id, kind custom
- CustomFilmAutoSelectAfterSaveTests | test_editSaveOfSelectedFilm_preservesSelection_withUpdatedIdentity | edit upsert keeps selection id, updates name/exponent(1.55)
- CustomFilmAutoSelectAfterSaveTests | test_editSaveOfDifferentFilm_doesNotChangeSelection | upsert other keeps active on "active"


#### CustomFilmLifecycleCorrectnessTests.swift
- CustomFilmLifecycleCorrectnessTests | test_customFilmSelection_restoresOnRelaunchViaSessionStore | relaunch resolves persisted custom film id via session store
- CustomFilmLifecycleCorrectnessTests | test_legacyCalculatorContextRestore_resolvesCustomFilmID | legacy single-context restore resolves custom id
- CustomFilmLifecycleCorrectnessTests | test_deleteCustomFilm_scrubsInactiveCameraSlotSnapshots | delete scrubs inactive Camera 2 snapshot reference
- CustomFilmLifecycleCorrectnessTests | test_deleteCustomFilm_inactiveSlotCleanup_survivesRelaunch | cleared inactive slot persists across relaunch
- CustomFilmLifecycleCorrectnessTests | test_sanitation_dropsMalformedCustomFilm | drops preset-kind/zeroISO/blankName/neg/nan exp/zero coeff/inf offset; keeps "ok"
- CustomFilmLifecycleCorrectnessTests | test_sanitation_appliesOnLibraryRestore | restore sanitizes (drops exp=-2.0)


#### CustomFilmEditAndSelectorUXTests.swift
- CustomFilmEditAndSelectorUXTests | test_editorFormState_fromExistingFilm_prefillsEveryField | from(film:) prefills all fields; legacy coeff1.10→baseTm1/baseTc1.1
- CustomFilmEditAndSelectorUXTests | test_editorFormState_fromExistingFilm_rejectsNonCustom | preset → nil
- CustomFilmEditAndSelectorUXTests | test_addCustomFilm_withSameID_upsertsInPlace | same id upserts (1 entry, Edited/iso200)
- CustomFilmEditAndSelectorUXTests | test_filmSelectorEntries_noQuickAccessSection | no "Quick access" section
- CustomFilmEditAndSelectorUXTests | test_filmSelectorEntries_doesNotDuplicateCustomFilm | custom appears once
- CustomFilmEditAndSelectorUXTests | test_filmSelectorEntries_includesCreateCustomFilmRow_belowNoFilm | No film @0, Create row @1 (createCustomFilmEntryID)
- CustomFilmEditAndSelectorUXTests | test_createCustomFilmRow_isNeverMarkedSelected | selection never on create-row id
- CustomFilmEditAndSelectorUXTests | test_customFilmList_orderStableAcrossSelectionChanges | order stable across selection change


#### PersistentCustomFilmLibraryTests.swift (app-hosted; concrete UserDefaults store)
- PersistentCustomFilmLibraryTests | test_malformedPayload_failsSafeToEmptyLibrary | malformed bytes → empty library, no crash; recovers after save
- PersistentCustomFilmLibraryTests | test_userDefaultsStore_persistsAcrossDistinctInstances | distinct store instances share backing storage
- PersistentCustomFilmLibraryTests | test_presetCatalogStoreKey_isDistinctFromCustomLibraryKey | custom key distinct from calculator-context key (no stomp)


#### CustomFilmEditorFormStateTests.swift
- CustomFilmEditorFormStateTests | test_validate_validInput_returnsCustomFilmIdentity | valid → custom film, single formula rule, modifiedSchwarzschild, boundaries on formula, idGenerator consulted
- CustomFilmEditorFormStateTests | test_validate_acceptsOptionalCoefficientAndOffset | coeff1.10/offset0.05 stored
- CustomFilmEditorFormStateTests | test_validate_emptyNotes_storesNoNotesEntry | blank notes → []
- CustomFilmEditorFormStateTests | test_validate_emptyValidThrough_isUnlimitedNotAnError | empty → sourceRange nil
- CustomFilmEditorFormStateTests | test_validate_unlimitedKeyword_isUnlimitedNotAnError | "Unlimited" → sourceRange nil
- CustomFilmEditorFormStateTests | test_validate_validThroughBelowNoCorrection_reportsError | validThrough<noCorr → .invalidValidThrough
- CustomFilmEditorFormStateTests | test_validate_negativeOffset_rejectsShortenedExposure | offset-2 → .formulaShortensExposure
- CustomFilmEditorFormStateTests | test_validate_baseTcBelowBoundary_rejectsShortenedExposure | baseTc0.5 → shortens
- CustomFilmEditorFormStateTests | test_validate_lowExponentBelowBoundary_rejectsShortenedExposure | exp0.5 → shortens
- CustomFilmEditorFormStateTests | test_validate_emptyProfileName_isNotAnErrorAnymore | blank profileName ok
- CustomFilmEditorFormStateTests | test_validate_missingFilmLabel_reportsMissingError | empty label → .missingFilmLabel
- CustomFilmEditorFormStateTests | test_validate_invalidFieldValue_reportsSpecificError | 11-case table: ISO/exp/baseTc/baseTm/offset invalid → specific errors
- CustomFilmEditorFormStateTests | test_validate_emptyExponent_reportsMissingFormulaExponent | blank exp → .missingFormulaExponent
- CustomFilmEditorFormStateTests | test_validate_collectsAllErrorsAtOnce | all errors collected; no .missingProfileName


#### [editor-ui] CustomFilmEditorPolishTests.swift (app-hosted)
- [editor-ui] CustomFilmEditorPolishTests | test_rowDurationDisplayValue_rendersExpectedTextPerInput | row duration formatter 7-case table (s/m/sub-second/empty/unparseable/unlimited)
- [editor-ui] CustomFilmEditorPolishTests | test_commonISOs_includes320_atStablePosition | common-ISO chip list pinned order incl "320"


#### [editor-ui] CustomFilmEditorTwoLineFormulaTests.swift
- [editor-ui] CustomFilmEditorTwoLineFormulaTests | test_structureText_isAlwaysTheFullAnchoredShape | structure line always "Tc = Tc₀ × (Tm / Tm₀)^p + b" across modes
- [editor-ui] CustomFilmEditorTwoLineFormulaTests | test_currentLine_rendersExpectedExpressionPerFormState | current-value line 6-case table; symbol placeholders; never word "exponent"


#### [editor-ui] CustomFilmEditorFormulaPresentationTests.swift
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_anchoredFormula_summaryAndBasis_agreeOnCoefficientUnits | summary vs CalculationBasis agree on non-neutral slots incl "3s" suffix
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_neutralReferenceFormula_basisDropsCoefficientSuffix | neutral-ref coeff renders without "s"
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_advancedFormula_signedOffset_rendersWithSignedSegment | +0.3s / -0.3s segments
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_formulaExpressionSplitter_scopesExponentTokenPerInput | exponent superscript splitter 3-case (offset baseline / empty remainder / nil)
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_formulaCanRenderPreview_validForm_isTrue | valid form preview-renderable
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_formulaCanRenderPreview_unparseableForm_isFalse | unparseable not renderable
- [editor-ui] CustomFilmEditorFormulaPresentationTests | test_formulaCanRenderPreview_shortensExposure_isFalse | shortening form not renderable; saveDisabledReason "Tc₀ must be ≥ Tm₀"/"Current: 0.01s < 1s"


#### [editor-ui] CustomFilmEditorInputModeTests.swift
- [editor-ui] CustomFilmEditorInputModeTests | test_inputMode_inferredAsBasic_forExponentOnlyProfile | exp-only → .basic
- [editor-ui] CustomFilmEditorInputModeTests | test_inputMode_inferredAsScaled_forAnchoredProfile | anchored → .scaled
- [editor-ui] CustomFilmEditorInputModeTests | test_inputMode_inferredAsAdvanced_whenOffsetNonZero | offset≠0 → .advanced
- [editor-ui] CustomFilmEditorInputModeTests | test_switchingToBasic_resetsHiddenAdvancedFields | →basic resets anchors/offset, keeps exponent
- [editor-ui] CustomFilmEditorInputModeTests | test_switchingToScaled_resetsOnlyOffset | →scaled keeps anchors, clears offset
- [editor-ui] CustomFilmEditorInputModeTests | test_switchingToAdvanced_preservesEverything | →advanced preserves all
- [editor-ui] CustomFilmEditorInputModeTests | test_scaledMode_canRepresentAnchoredFormula | scaled T-MAX validate → coeff/refTm/exp/offset


#### [editor-ui] CustomFilmEditorResetRevertTests.swift
- [editor-ui] CustomFilmEditorResetRevertTests | test_resetDefaultsSnapshot_carriesDocumentedNeutralValues | reset snapshot neutral values
- [editor-ui] CustomFilmEditorResetRevertTests | test_applyResetSnapshot_overwritesAllFormulaFields | reset overwrites formula fields, keeps identity
- [editor-ui] CustomFilmEditorResetRevertTests | test_resetThenRevert_inEditFlow_restoresOpeningSnapshot | reset then revert restores opening snapshot
- [editor-ui] CustomFilmEditorResetRevertTests | test_revertFromUntouchedNewFlow_isAnIdentityOnFormulaFields | snapshot self-apply = identity on formula fields


#### [editor-ui] CustomFilmEditorPreviewPresenterTests.swift
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_rows_belowThreshold_marksNoCorrection | 1s → noCorrection, corrected=1
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_rows_insideFormulaRange_appliesFormula | 4s → formulaApplied 4^1.30, stopDelta>0
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_rows_beyondSourceRange_keepsCalculatingWithReducedConfidence | 120/300s → beyondSourceRange but corrected non-nil
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_rows_invalidExponent_marksEveryRowInvalid | invalid exp → all invalidFormulaResult, corrected nil
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_rows_defaultsMultiplierOneAndOffsetZero | blank coeff/offset → 4^1.30
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_parse_anchorAccepts_durationStringWithSuffix | suffixed durations parse (0.1s,1s,5m→300)
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_parse_rejectsInvalidNumericFieldValues | 6-case table: Unlimited/garbage/dash on anchors/offset → nil
- [editor-ui] CustomFilmEditorPreviewPresenterTests | test_parse_validThroughEmptyMeansUnlimited | empty validThrough → nil


#### [editor-ui] CustomFilmEditorSaveDisabledReasonTests.swift
- [editor-ui] CustomFilmEditorSaveDisabledReasonTests | test_validForm_returnsNilReason | valid → nil
- [editor-ui] CustomFilmEditorSaveDisabledReasonTests | test_untouchedNewForm_returnsNil_evenThoughExponentIsMissing | untouched new → nil (quiet)
- [editor-ui] CustomFilmEditorSaveDisabledReasonTests | test_perFieldErrors_returnNil_soInlineHintsLead | per-field errors → nil summary (inline leads)
- [editor-ui] CustomFilmEditorSaveDisabledReasonTests | test_formulaShortensExposure_surfacesFormulaConstraintReason | shortening → 2-line "Tc₀ must be ≥ Tm₀"/"Current: 1s < 2s"
- [editor-ui] CustomFilmEditorSaveDisabledReasonTests | test_formulaShortensExposure_doesNotEmitOldSentenceWording | no legacy "Corrected exposure"/"shorter than"
- [editor-ui] CustomFilmEditorSaveDisabledReasonTests | test_identityOnlyErrors_returnNil_soInlineHintsLead | identity-only → nil summary


#### [editor-ui] CustomFilmEditorFormulaTokenTests.swift
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_tokenOrder_matchesFormulaLeftToRight | slot order [tcAnchor,tmAnchor,exponent,offset]
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_tokenSymbols_useFormulaVocabulary | symbols Tc₀/Tm₀/p/b
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_tokenTap_opensMatchingFieldSheet | token→editField mapping
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_rangeFieldsAreNotFormulaTokens | range/label/iso/mfr fields not token slots
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_displays_neutralDefaults_renderNeutralLabelsAsPlaceholders | neutral → 1s/1s/p/0s placeholders
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_displays_filledValues_renderUnitsAndDropPlaceholderFlag | filled → 3s/2s/1.29/0.5s non-placeholder
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_displays_subSecondAnchor_trimsTrailingZeros | 0.1s not 0.10s
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_displays_negativeOffset_rendersWithMinusGlyph | −0.5s minus glyph, no "+"
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_displays_unparseableExponent_echoesUserTextNotSymbol | "abc" echoed + isInvalid
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_invalidFlag_setsForBothAnchors_whenShortensExposureGuardFails | shortening → both anchor tokens invalid, p/b valid
- [editor-ui] CustomFilmEditorFormulaTokenTests | test_invalidFlag_setsForSingleField_onPerFieldErrors | exp invalid → only exponent token invalid


#### [editor-ui] CustomFilmEditorLiveCheckTests.swift
- [editor-ui] CustomFilmEditorLiveCheckTests | test_liveCheckSamples_areExactlyOneSecondTenSecondsOneMinute | samples [1,10,60]
- [editor-ui] CustomFilmEditorLiveCheckTests | test_basicFormula_producesExpectedThreeRowSnapshot | basic: 1s noCorrection, 10/60s formula
- [editor-ui] CustomFilmEditorLiveCheckTests | test_scaledFormula_appliesAnchorPairToEverySample | scaled anchor pair applied (10s value)
- [editor-ui] CustomFilmEditorLiveCheckTests | test_advancedFormula_appliesOffsetAfterCurve | offset added after curve
- [editor-ui] CustomFilmEditorLiveCheckTests | test_liveCheck_respectsNoCorrectionThroughThreshold | noCorr=30 → 1/10s noCorrection, 60s formula
- [editor-ui] CustomFilmEditorLiveCheckTests | test_liveCheck_marksSampleBeyondSourceRange | sourceRange30 → 60s beyondSourceRange, corrected non-nil
- [editor-ui] CustomFilmEditorLiveCheckTests | test_liveCheck_hidesEveryRow_whenFormulaIsInvalid | invalid → all invalidFormulaResult, corrected nil


#### [editor-ui] CustomFilmEditorUIPassTests.swift
- [editor-ui] CustomFilmEditorUIPassTests | test_validate_composesCanonicalStockNameFromManufacturerAndLabel | canonical "Kodak NB1"; top mfr nil; userMetadata.customManufacturer "Kodak"
- [editor-ui] CustomFilmEditorUIPassTests | test_validate_withoutManufacturer_usesLabelAsCanonicalName | no mfr → canonical=label, customManufacturer nil
- [editor-ui] CustomFilmEditorUIPassTests | test_validate_storesReferenceURL | referenceURL stored film+profile level
- [editor-ui] CustomFilmEditorUIPassTests | test_unlimitedValidThrough_savesFormulaWithoutMaximumSeconds | sourceRange nil
- [editor-ui] CustomFilmEditorUIPassTests | test_fromFilm_splitsCanonicalStockNameOnManufacturerPrefix | splits "Kodak NB1"→mfr/label, referenceURL round-trip, validThrough ""


#### [editor-ui] CustomFilmEditorPreviewGraphPresenterTests.swift (class CustomFilmEditorPreviewGraphTests)
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_axisLabelsAndTitle_matchDetailsGraphPresenter | axes "Adjusted shutter"/"Corrected exposure", title "Reciprocity Graph"
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_graphHeader_suppressesFormulaText_forCustomAndAnchoredForms | custom/anchored graph state formulaDisplayText nil
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_viewportRange_extendsBelowOneSecond | x/y lower bound 0.01
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_axisTicks_includeSubSecondLabels | ticks incl "1/10s","1s"
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_noCorrectionThrough_drivesGreenBandUpperBound | noCorrection drives band upper bound (2)
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_finiteValidThrough_setsSupportedUpperBound | finite → supportedRangeUpperBound 240
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_unlimitedValidThrough_noBoundaryOrUpperBound | unlimited → no supported/notRecommended bounds
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_curveSampling_includesIdentitySegmentBelowThreshold | identity (Tc=Tm) samples below threshold
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_calculationBasis_carriesSameWordingAsTheLegacyGraphHeader | basis text "Tc = 0.1s × (Tm / 0.1s)^1.0966"
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_sameFormula_producesSameViewport | same formula → same viewport/scaleTier
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_unparseableForm_returnsNil | unparseable → nil graph state
- [editor-ui] CustomFilmEditorPreviewGraphTests | test_editorPreview_matchesRuntimeDetailsForSameParameters | editor preview == runtime Details graph for same params (axes/ranges/bounds/formula/points)


#### [editor-ui] CustomFilmEditorInlineValidationTests.swift
- [editor-ui] CustomFilmEditorInlineValidationTests | test_untouchedNewForm_returnsNil_forEveryField | untouched new → nil all fields
- [editor-ui] CustomFilmEditorInlineValidationTests | test_editingFlow_doesNotSuppressEvenIfFieldsLookUntouched | edit flow → "Required"/"p is required"
- [editor-ui] CustomFilmEditorInlineValidationTests | test_invalidField_returnsExpectedCompactInlineHint | 9-case table compact hints (Required/Enter 1–100000/p must be > 0/Tm₀.../etc)
- [editor-ui] CustomFilmEditorInlineValidationTests | test_validForm_returnsNilForEveryField | valid → nil all fields


#### [editor-ui] CustomFilmEditorFormulaRecoveryTests.swift
- [editor-ui] CustomFilmEditorFormulaRecoveryTests | test_resetDefaultsSnapshot_matchesSpec | reset snapshot spec values
- [editor-ui] CustomFilmEditorFormulaRecoveryTests | test_resetFormula_restoresSafeDefaults_andPreservesIdentity | reset formula fields, identity/notes/url preserved
- [editor-ui] CustomFilmEditorFormulaRecoveryTests | test_revertFormula_restoresOpeningSnapshot_andPreservesIdentity | revert formula to opening, identity edits survive
- [editor-ui] CustomFilmEditorFormulaRecoveryTests | test_revertFormula_recoversFormulaInputModeAfterModeSwitch | revert restores mode+anchors after switch


#### [editor-ui] CustomFilmEditorPreviewDiagnoseTests.swift
- [editor-ui] CustomFilmEditorPreviewDiagnoseTests | test_diagnose_returnsExpectedReasonPerFormState | diagnose 7-case table → InvalidReason (nil/emptyExponent/invalid*)
- [editor-ui] CustomFilmEditorPreviewDiagnoseTests | test_displayMessage_usesSymbolAnchoredVocabulary | "Tm₀ must be > 0."/"Tc₀ must be > 0."


#### [editor-ui] CustomFilmEditorFormulaSummaryTests.swift
- [editor-ui] CustomFilmEditorFormulaSummaryTests | test_formulaSummary_rendersExpectedStringPerFormState | 6-case anchored-shape rendering table
- [editor-ui] CustomFilmEditorFormulaSummaryTests | test_negativeOffset_rendersWithMinusSign | "− 0.5s", no "+ -"
- [editor-ui] CustomFilmEditorFormulaSummaryTests | test_blankExponent_fallsBackToSymbolP | "^p", no "exponent"
- [editor-ui] CustomFilmEditorFormulaSummaryTests | test_summary_updatesWhenExponentChanges | summary re-renders on exp change
- [editor-ui] CustomFilmEditorFormulaSummaryTests | test_summary_modeAgnostic_alwaysShowsAnchoredShape | scaled==advanced summary


#### CustomFilmEditorTableFormStateTests.swift (PTIMER-178; two classes)
- CustomFilmEditorTableFormStateTests | test_validate_validTable_buildsSingleTableRuleProfile | valid table → single .tableInterpolation rule, anchors exact, hasValidParameters
- CustomFilmEditorTableFormStateTests | test_validate_emptyNoCorrection_defaultsToHalfSecond_forTypicalAnchor | default noCorr = min(0.5, firstAnchor/2)=0.5
- CustomFilmEditorTableFormStateTests | test_validate_emptyNoCorrection_subHalfSecondAnchor_defaultsToHalfAnchor | anchor 0.4 → noCorr 0.2
- CustomFilmEditorTableFormStateTests | test_validate_sourceRange_derivedFromLastAnchor | sourceRange = last anchor (100)
- CustomFilmEditorTableFormStateTests | test_validate_explicitNoCorrection_isPreserved | explicit noCorr=2 preserved
- CustomFilmEditorTableFormStateTests | test_validate_blankRowsAreIgnored | blank row ignored
- CustomFilmEditorTableFormStateTests | test_validate_sourceEvidence_carriesDisplayCopiesOfAnchors | **sourceEvidence = display copies** of anchors (correctedTime mappings)
- CustomFilmEditorTableFormStateTests | test_validate_editIDQueue_reusesProfileThenFilmID | id queue → profile-id then film-id
- CustomFilmEditorTableFormStateTests | test_validate_singleAnchor_failsInsufficient | 1 anchor → .insufficientTableAnchors
- CustomFilmEditorTableFormStateTests | test_validate_unparseableValue_failsInvalidAnchors | "abc" → .invalidTableAnchors
- CustomFilmEditorTableFormStateTests | test_validate_nonPositiveValue_failsInvalidAnchors | 0 → .invalidTableAnchors
- CustomFilmEditorTableFormStateTests | test_validate_descendingMetered_autoSortedToValid | descending rows auto-sorted valid
- CustomFilmEditorTableFormStateTests | test_validate_duplicateMetered_failsInvalidAnchors | dup metered → .invalidTableAnchors
- CustomFilmEditorTableFormStateTests | test_validate_correctedShorterThanMetered_failsInvalidAnchors | Tc<Tm → .invalidTableAnchors (no-shortening)
- CustomFilmEditorTableFormStateTests | test_validate_partiallyFilledRow_failsInvalidAnchors | partial row → .invalidTableAnchors
- CustomFilmEditorTableFormStateTests | test_validate_zeroNoCorrection_failsStricterThanDomain | noCorr=0 → .invalidNoCorrectionThrough (stricter)
- CustomFilmEditorTableFormStateTests | test_validate_noCorrectionAtFirstAnchor_fails | noCorr at first anchor → invalid
- CustomFilmEditorTableFormStateTests | test_validate_unlimitedNoCorrection_fails | "Unlimited" noCorr → invalid
- CustomFilmEditorTableFormStateTests | test_validate_missingIdentity_stillReportsIdentityErrors | missing label/iso → identity errors
- CustomFilmEditorTableFormStateTests | test_parsedTableAnchors_autoSortsDescendingInput | parsed anchors sorted ascending
- CustomFilmEditorTableFormStateTests | test_parsedTableAnchors_incompleteRowDoesNotPreventSort | incomplete row skipped, rest sorted
- CustomFilmEditorTableFormStateTests | test_sortCompleteTableRows_reordersOutOfOrderRows | sort reorders complete rows
- CustomFilmEditorTableFormStateTests | test_sortCompleteTableRows_leavesIncompleteRowInPlace | incomplete row stays in place
- CustomFilmEditorTableFormStateTests | test_sortCompleteTableRows_noOpWhenFewerThanTwoCompleteRows | <2 complete → no-op
- CustomFilmEditorTableFormStateTests | test_sortCompleteTableRows_preservesDuplicateMeteredInvalid | dup metered still invalid post-sort, no drop
- CustomFilmEditorTableFormStateTests | test_removeTableRow_removesByIdLeavingOthersIntact | id-based remove (crash repro fix)
- CustomFilmEditorTableFormStateTests | test_removeTableRow_unknownIdIsNoOp | unknown id → no-op
- CustomFilmEditorTableFormStateTests | test_savePath_storesAnchorsSortedByMeteredTime | save stores sorted [2,10,100]
- CustomFilmEditorTableFormStateTests | test_tableRowValidationReason_flagsShorteningRow | shortening row → "Tc must be ≥ Tm"
- CustomFilmEditorTableFormStateTests | test_tableRowValidationReason_outOfOrderCompleteRow_returnsNil | out-of-order → nil (auto-sorted)
- CustomFilmEditorTableFormStateTests | test_tableRowValidationReason_duplicateMetered_returnsError | dup → "Rows must be sorted by Tm."
- CustomFilmEditorTableFormStateTests | test_tableRowValidationReason_blankRowIsSilent | blank row silent
- CustomFilmEditorTableFormStateTests | test_switchingToTable_seedsMinimumRows_andClearsFormulaDefault | →table seeds rows, clears noCorr default
- CustomFilmEditorTableFormStateTests | test_switchingBackToFormula_restoresFormulaDefault | →formula restores noCorr "1"
- CustomFilmEditorTableFormStateTests | test_switchingToTable_keepsTypedNoCorrection | →table keeps typed noCorr "0.5"
- CustomFilmEditorTableFormStateTests | test_fromFilm_tableProfile_prefillsTableKindAndRows | from(film:) table → kind table, rows/noCorr/notes; rebuilds identical rule
- CustomFilmEditorTableFormStateTests | test_fromFilm_formulaProfile_staysFormulaKind | from(film:) formula → kind formula, empty tableRows
- CustomFilmEditorTableFormStateTests | test_formatDurationExpression_100sDoesNotRenderAsDecimalMinutes | 100s → "1m 40s" not "1.7m"
- CustomFilmEditorTableFormStateTests | test_formatDurationExpression_wholeMinutesRenderCompact | 60/120/3600 → 1m/2m/60m
- CustomFilmEditorTableFormStateTests | test_formatDurationExpression_subMinuteValuesUnchanged | 1/30/0.5/1.5 sub-minute
- CustomFilmEditorTableFormStateTests | test_formatDurationExpression_fractionalMinutesUseMsSeparation | 400/1262/90 → m+s
- CustomFilmEditorTableFormStateTests | test_parsedTableRule_matchesSavedRule | preview rule == saved rule, tableCanRenderPreview
- CustomFilmEditorTableFormStateTests | test_previewTableRows_reproduceAnchorsExactly_andMarkBeyondSource | preview rows reproduce anchors exactly, last → beyondSourceRange w/ corrected
- CustomFilmEditorTableFormStateTests | test_previewTableRows_emptyWhileTableInvalid | invalid → empty rows + diagnosis message
- CustomFilmEditorTableFormStateTests | test_incompleteTable_yieldsNoRuleSoFittedWarningIsSuppressed | **incomplete table → no rule → no false fitted "shortening" warning**
- CustomFilmEditorAnchorSecondsFormatTests | test_formatAnchorSeconds_subSixty_returnsPlain | <60 → "10s"/"59s"
- CustomFilmEditorAnchorSecondsFormatTests | test_formatAnchorSeconds_exactSixty_includesRawSeconds | 60 → "60s" prefix
- CustomFilmEditorAnchorSecondsFormatTests | test_formatAnchorSeconds_100s_displaysSecondsFirst | 100 → "100s"+"1m"
- CustomFilmEditorAnchorSecondsFormatTests | test_formatAnchorSeconds_1000s_displaysSecondsFirst | 1000 → "1000s"+"16m"
- CustomFilmEditorAnchorSecondsFormatTests | test_formatAnchorSeconds_neverDecimalMinutes | never decimal minutes


## D — Timer + persistence + notification (~110 tests)

**[verdict]** ✅ **already-covered** for the protected timer core and restore
contract — verified directly against Android `core`: completion fires
exactly once and is then quiet (`tickCompletesExpiredOnceThenIsQuiet`),
reconcile completes-without-alert (`reconcileCompletesWithoutReportingAlerts`),
restore-running-past-end auto-completes (`restoreRunningPastEndCompletesAtExpectedTime`),
resume past the pause window stays running with frozen remaining
(`resumeAfterPauseWindowExpiredKeepsRemaining`), corrupt paused → completed
without fabricating freeze, corrupt snapshot → empty
(`TimerSnapshotCodecTest`), schema-version mismatch → empty, ordering
active-LIFO + completed-behind, and Start-Again clone. Identity immutability
is now pinned by `timerIdentityIsImmutableAcrossLifecycleAndLaterStarts`.
Restored-id collision and per-item snapshot sanitation were hardened in the
restore/persistence passes; malformed-typed-field isolation and duplicate-id
ordering were further hardened in Pass 2 (see *Restore / Persistence
Hardening — Pass 1* and *Pass 2* above).
**Notifications** (`TimerManagerNotificationSchedulingTests`,
`…CompletionAlertTests`) → **follow-up** (background delivery / foreground
service deferred, round2-accepted §8). `[ios-only]` rows
(`B4TimerLifecycleBaselineTests` RecordReplay traces,
`LockScreenTimerCoordinatorTests`, foreground-feedback gating) → **ios-only**;
Android covers representative selection via `RepresentativeTimerSelectorTest`.
iOS legacy-schema rows (`"stopped"` token, legacy `expectedCompletionAt`)
→ **N/A** (Android schema v1 is greenfield, no legacy payloads).

Recorded intent:



**TimerStatePauseResumeTests** (PTimerCore)
- `testTimerStateResumeReturnsCompletedWhenNoRemainingTime` | resume of paused w/ pausedRemainingTime=0 → .completed; pausedAt/pausedRemaining nil'd; endDate==pausedAt (corrupt/back-compat-only corner)
- `testTimerStateResumeReturnsRunningWhenPauseWindowHasExpired` | resume even after pausedRemaining elapsed in wall time → .running, remaining preserved (6), endDate=now+remaining (paused freezes wall clock)
- `testTimerStateResumeReturnsRunningWithNewEndDateWhenStillResumable` | resume → .running, endDate recomputed = now+frozenRemaining
- `testPausingWhenRemainingIsZeroImmediatelyCompletes` | pausing at endDate short-circuits to .completed (no zero-remaining paused via normal path)

**TimerManagerTests** (app-hosted; mostly TimerState logic)
- `testStartAddsMultipleRunningTimers` | start returns id, appends in insertion order, both running; endDate=start+dur
- `testTickUpdatesEachTimerIndependently` | tick advances each timer's remaining independently
- `testRemainingTimeCalculationTracksEndDateAndClampsAtZero` | remaining tracks endDate, clamps at 0 past end
- `testTickCompletesExpiredTimerWithoutAffectingOthers` | tick completes only expired timer; others stay running
- `testNotificationIdentifierIsDeterministicFromTimerUUID` | notif id == `timer-completion-<lowercased-uuid>`
- `testTimerWithVeryLargeDurationDoesNotOverflow` | 1yr duration finite; completes after end
- `testCompletedTimerHasDeterministicCompletionTimestamp` | completed endDate == start+dur regardless of tick time
- `testNonPositiveDurationIsIgnored` | start(0)/start(-3) → nil, no timer (xN: zero, negative)
- `testNonFiniteDurationIsIgnored` | start(±inf, nan, signalingNaN) → nil (isFinite guard) (x4)
- `testRemoveCompletedTimersRemovesOnlyCompletedEntries` | removeCompleted drops only .completed
- `testDelayedTickUsesAbsoluteTimeWithoutDrift` | late tick (5.8s) uses absolute time → completed, no drift
- `testCompletedTimerKeepsZeroRemainingTime` | completed remaining stays 0 even far past end
- `testCompletedStateHasNoPausedMetadata` | completed() clears pausedAt/pausedRemaining
- `testStatusTransitionsAtEpsilonBoundary` | status flips running→completed within ±epsilon/2 of endDate (stabilityEpsilon)
- `testRemainingTimeEpsilonClampBoundary` | remaining clamps to 0 below epsilon, exact above
- `testStatusAtDoesNotChangeOriginalState` | status(at:) is pure (no mutation)
- `testTimerManagerStopsLoopWhenNoRunningTimers` | no running timers remain after completion
- `testRunningTimerAutoCompletesViaUpdatingStatus` | updatingStatus past end → .completed, endDate unchanged
- `testBoundaryCompletionWithEpsilon` | updatingStatus epsilon boundary (mirror of status epsilon)
- `testPauseLoopUsesResolvedState` | resolved/updatingStatus state used for loop-stop decision

**TimerManagerPauseResumeTests** (app-hosted)
- `testPauseFreezesRemainingTimeInResumablePausedState` | pause freezes remaining(3); stable across later wall time; other timer keeps running
- `testTickDoesNotAdvanceFrozenPausedTimerRemainingTime` | tick does NOT advance paused remaining (frozen at 7)
- `testResumeContinuesFromFrozenPausedRemainingTime` | resume continues from frozen remaining, then counts down normally
- `testResumeRecalculatesEndDateFromFrozenPausedRemainingTime` | resume endDate = now+frozenRemaining(7)
- `testPausedTimerPreservesFrozenStatePauseMetadata` | paused keeps startDate, pausedAt=now, pausedRemaining=6
- `testCompletedTimerPreservesOriginalDurationMetadata` | completed keeps duration/startDate/endDate=start+dur
- `testRemoveCompletedTimersKeepsPausedTimersResumable` | removeCompleted leaves paused resumable
- `testResumeMultipleTimesMaintainsCorrectRemainingTime` | repeated pause/resume keeps correct frozen remaining; final endDate=now+12
- `testResumeAfterLongPauseUsesCorrectRemainingTime` | resume after 10000s pause → remaining still 6, endDate=now+6
- `testPausedTimerEndDateIsDerivedFromFreezeMetadata` | paused endDate computed = pausedAt+pausedRemaining (not stored)
- `testResumeAfterLogicalCompletionKeepsTimerRunningFromRemainingTime` | resume after end-time passed while paused → stays running w/ frozen remaining(1), NOT auto-completed; endDate=now+1
- `testCompletionDateMatchesRegardlessOfCompletionPath` | tick-complete endDate=start+dur; resume-then-complete endDate=resume-relative — completion timestamp path-dependent for resumed timers
- `testLongPausedResumeStaysRunningWithoutAlertAndAlertsOnlyAfterRunningCompletion` | resume past original end → running, NO alert; alert fires once only after running completion via tick

**TimerManagerPersistenceRestoreTests** (app-hosted)
- `testPersistedPausedSnapshotOmitsExpectedCompletionAt` | paused snapshot writes nil expectedCompletionAt; stores pausedRemainingDuration=6, pausedAt
- `testRestoreLegacyPausedSnapshotIgnoresExpectedCompletionAt` | legacy JSON expectedCompletionAt=199 IGNORED on restore; endDate reconstructed = pausedAt+pausedRemaining(6)
- `testRestoreRunningTimerAfterTerminationKeepsItRunningWithWallClockRemainingTime` | restore running → wall-clock remaining(6), endDate=orig start+dur
- `testRestoreRunningTimerAfterTerminationCompletesIfExpectedCompletionAlreadyPassed` | restore running past end → auto-.completed, remaining 0
- `testRestorePausedTimerAfterTerminationPreservesFrozenRemainingTime` | restore paused after 40s away → frozen remaining(6), pausedAt preserved
- `testRestoreWithCorruptedPersistedSnapshotSafelyFallsBackToEmptyState` | corrupt ("not-json") snapshot → empty timers, no crash
- `testRestoreDecodesLegacyStoppedSnapshotValueAsPaused` | legacy `"stopped"` status token decodes as .paused; remaining(6), pausedAt preserved
- `testRestoreCompletedTimerAfterTerminationKeepsCompletedState` | restore completed → stays completed, endDate=start+dur
- `testRestoreMultipleTimersAfterTerminationPreservesIDsAndStatuses` | restore preserves id order [running,paused,completed] + statuses + remaining
- `testResumeThenRelaunchRestoresRunningTimerWithReconciledRemainingTime` | resume then relaunch → running, reconciled remaining(4), endDate=start+12
- `testRestoreEntryPointLoadsSnapshotOnlyDuringInitialization` | snapshot load only at init (loadCallCount stays 2 across reconcile/tick)
- `testRemovingLastTimerClearsPersistedSnapshot` | remove last timer clears persisted snapshot (nil)
- `testRepeatedRelaunchRestoreDoesNotDuplicatePersistedTimers` | repeated relaunch → no duplicates, single id, remaining(6)

**TimerManagerReconcileTests** (app-hosted)
- `testReconcileAfterAppBecomesActiveKeepsStillRunningTimerRunningWithRefreshedRemainingTime` | reconcile keeps running, refreshes remaining(6)
- `testReconcileAfterAppBecomesActiveCompletesExpiredRunningTimerWithoutReplayingCompletionAlert` | reconcile completes expired running WITHOUT firing alert (reconcile-without-alert)
- `testReconcileAfterAppBecomesActiveKeepsPausedTimerUnchanged` | reconcile leaves paused unchanged, remaining(6)
- `testReconcileAfterAppBecomesActiveKeepsMultipleTimersConsistentAcrossStatuses` | reconcile across running/completing/paused: correct statuses+remaining, no alert

**TimerManagerNotificationSchedulingTests** (app-hosted)
- `testStartSchedulesCompletionNotificationForRunningTimer` | start → requests auth + schedules notif {id,endDate=start+3,.running} (schedule-on-start)
- `testPauseCancelsPendingCompletionNotification` | pause → cancels notif for id (cancel-on-pause)
- `testResumeReschedulesCompletionNotificationUsingNewEndDate` | resume → 2nd auth + reschedule at new endDate(now+6) + cancel during pause (reschedule-on-resume)
- `testRemoveCancelsRelatedCompletionNotification` | remove → cancels notif
- `testForegroundCompletionCleansUpStalePendingNotification` | foreground tick-complete → cancels stale pending notif
- `testRemoveCompletedTimersCancelsStalePendingNotificationsForCompletedTimers` | removeCompleted cancels only completed timer's notif (not paused)
- `testPausedAndCompletedTimersDoNotLeaveScheduledNotifications` | no active (uncancelled) schedule remains after pause+complete
- `testMultipleTimersScheduleAndCancelUsingDeterministicPerTimerLifecycle` | schedule order [first,second]; cancel order [second(pause),first(complete)] — per-timer deterministic

**TimerManagerCompletionAlertTests** (app-hosted)
- `testCompletionAlertFiresExactlyOnceWhenRunningTimerCompletes` | running completion → exactly one alert {id,completionDate} (completion exactly-once)
- `testCompletedTimerDoesNotTriggerDuplicateAlertOnRepeatedTickOrReevaluation` | repeated ticks/status/updatingStatus → alert count stays 1 (idempotent)
- `testPausedTimerDoesNotTriggerCompletionAlertAfterTimePasses` | paused past end + tick → no alert, stays paused
- `testPausedTimerDoesNotTriggerCompletionAlert` | pause then tick past end → no alert
- `testMultipleTimersTriggerSeparateCompletionAlertsAtTheirOwnCompletionTimes` | each timer alerts once at its own completion (ordered first@2,second@5)
- `testForegroundAlertServiceOnlyPlaysFeedbackWhileAppIsActive` | [ios-only] feedback plays only when app .active (background suppressed); playCount=1

**B4TimerLifecycleBaselineTests** (app-hosted) — [ios-only] RecordReplay trace baselines
- `testPauseThenRemoveBaseline` | [ios-only] trace: start→tick→pause(frozen)→remove
- `testPauseResumeCompleteBaseline` | [ios-only] trace: pause freezes 50, resume endDate=t90, complete
- `testMultiTimerStaggeredCompletionBaseline` | [ios-only] trace: staggered 2-timer completion
- `testCompletedClearThenRestartBaseline` | [ios-only] trace: complete→removeCompleted→start new (Start New, fresh uuid)
- `testPauseWhileNotRunningNoOpBaseline` | [ios-only] trace: pause on completed = no-op transition still emits cancelNotif+save
- `testReactivationReconciliationBaseline` | [ios-only] trace: reconcile(now) completes-without-alert branch

**CompletedRelativeTimeFormatterTests** (PTimerKit)
- `testFormatterSupportsRequiredMinuteAndHourStrings` | relative strings: "just now"(<60s), "N min ago", "N hr ago", "N day(s) ago"; compact: "Nm/Nh/Nd ago"
- `testNextRefreshDateAdvancesAtNextDisplayBoundary` | nextRefreshDate = next minute/hour boundary

**LockScreenTimerCoordinatorTests** (PTimerKit) — [ios-only] lock-screen exposer coordinator
- `testSyncWithEmptyTimersClearsExposerOnlyOnce` | [ios-only] sync([]) with no prior target → no expose, no clear
- `testSyncWithOneRunningTimerExposesTargetOnce` | [ios-only] idempotent sync exposes once; carries representative id+name
- `testSyncTransitionsFromExposeToClearWhenAllTimersStop` | [ios-only] expose→clear when all stop
- `testSyncRespectsEarliestEndDateAcrossRunningTimers` | [ios-only] representative = earliest endDate; scheduledTargets sorted by endDate
- `testSyncIgnoresPausedAndCompletedTimers` | [ios-only] only running timers exposed/scheduled
- `testSelectRepresentativeReturnsNilForEmptyList` | [ios-only] empty → nil
- `testSelectRepresentativeReturnsNilWhenAllTimersAreNonRunning` | [ios-only] all paused/completed → nil
- `testSelectRepresentativeUsesIDOrderWhenEndDateAndPresentationTie` | [ios-only] tie-break → lexicographically smaller UUID
- `testSelectRepresentativeSchedulesAllRunningTargetsInOrder` | [ios-only] representative=earliest; scheduledTargets ordered by endDate
- `testExposedNamesCarrySelectedModelLabelOnlyForNonDefaultModels` | [ios-only] non-default model appends "· App formula"; default name byte-identical (identity capture: model)

**BottomSheetIdentityPaletteTests** (PTimerKit) — identity cue/badge presentation
- `testMultipleTimersGetDistinguishableIdentityCues` | distinct markerText (3) + ≥2 tintSlots
- `testCompactIdentityCueRemainsSeparateFromPrimaryAndSecondaryTimeText` | marker "T2" not embedded in time text; primary "55s"/secondary "03:00"
- `testLargeIdentityCueRemainsSeparateFromTitleTimeAndStatusValues` | marker not duplicated into title/status/remaining/timing/context
- `testOverflowCardKeepsViewAllRoleWithoutTimerIdentityMarker` | overflow "+1", hidden=1, visible markers [T2,T1,T3] (active-LIFO order), no T4
- `testTwoCameraSlotsGetDistinctTints` | camera1 vs camera2 → markers C1/C2, distinct tints
- `testFallbackToOrderMarkerWhenSnapshotAbsent` | no identity snapshot → fallback "T<order>"=T5, nil camera/film
- `testIdentitySurfacesCameraFilmSourceAcrossCompactLargeAndVoiceOver` | C2/"Camera 2"/film/source surfaced consistently in compact cue, large title+subtitle, VoiceOver label
- `testDigitalTimerShowsNoFilmIdentityInCompactAndLarge` | digital (no film) → "No film" descriptor in compact + large title
- `testIdentityCueIsStableAcrossPresentationsAndCompletion` | identity cue identical compact vs large, and stable when timer→completed (identity immutability)

**BottomSheetWorkspaceOrderingTests** (PTimerKit)
- `testActiveTimersPreserveStableRelativeOrderAcrossStatusChanges` | active relative order stable when one running→paused
- `testCompletedTimersAreDeferredBehindActiveTimersInWorkspaceOrdering` | active (paused+running) before completed; completed desc by completion (completed-desc / active-LIFO)
- `testNewTimerIsAlwaysInsertedAtTheTop` | newest timer at top (LIFO)
- `testNewTimerInsertedAtTopEvenWhenCompletedTimersExist` | new active at top, completed pushed below
- `testLargeSectionsGroupTimersByPresentationStatus` | sections ["Active","Recently Completed"], 2+2
- (helpers only, no extra tests)

**BottomSheetWorkspaceSnapshotFactoryTests** (PTimerKit)
- `testSnapshotStoreReflectsTimerCreationInCompactAndLargeFromSameRuntimeTruth` | start surfaces in compact+large from one runtime truth; detent .compact; same id/identityCue
- `testSnapshotStoreReflectsTickVisibilityForCompactAndLarge` | tick updates remaining 10→6 in both; identityCue stable; progress increases
- `testWorkspaceSnapshotReflectsAppReactivationStateReconciliationForCompactAndLarge` | reconcile splits running(6)/completed across Active vs Recently Completed; completedCount=1
- `testCompletedLargeItemShowsAbsoluteAndRelativeCompletionTime` | completed timing "Completed <abs> · just now"
- `testCompletedLargeItemsUseEachCompletionDateForRelativeTimingText` | each completed uses own completionDate for "N min ago"
- `testSnapshotStorePropagatesPauseResumeRemoveAndClearCompletedActionsConsistently` | pause/resume/tick-complete/clear/start/remove all propagate; identityCue stable across pause→resume→complete; remaining frozen at 7
- `testSnapshotStoreKeepsExistingTimerMetadataIndependentFromLaterCalculatorEdits` | later baseShutter/ndStop edits do NOT mutate existing timer's id/identity/title/context (identity immutability)
- `testSnapshotStoreKeepsCompactAndLargeViewsConsistentThroughCompletionOrdering` | compact/large id sets match through completion; sections collapse to Recently Completed; count=2
- `testCompactSummaryOrdersVisibleTimersCountsAndReportsOverflow` | compact visible-limit, order [paused,running,completed]→markers [T2,T1,T3], overflow "+1", completedCount=2
- `testCompactPresentationSimplifiesLongDurationContent` | long dur → "4d 6h" compact
- `testCompactDurationTextUsesSimplifiedMiniDockFormatting` | duration text rules: 64→"01:04", 25→"25s", 9.64→"9.6s", 0.25→"0.3s", 3661→"1h 1m", 90061→"1d 1h", 34218061→"1y 1m"
- `testClearCompletedRemovesCompletedSectionMetadataAndIdentityMarkers` | clearCompleted removes Recently Completed section; surviving timer keeps C1 badge + context

**BottomSheetWorkspaceSnapshotStartAgainTests** (PTimerKit) — Start Again clone
- `testCompletedRowSurfacesStartAgainActionAndOtherStatusesDoNot` | only completed rows expose actions==[.startAgain,.remove] (order: startAgain before remove); active/paused do not
- `testStartingNewTimerFromCompletedAddsCloneAndLeavesSourceUnchanged` | startNew(fromCompleted) → clone running w/ new id+startDate=now, same duration; source unchanged (status/duration/completedAt)
- `testStartingNewTimerFromNonCompletedRowIsRejected` | startNew from running source → rejected (count stays 1)
- `testSnapshotStoreReflectsPreviewStateTimerStartWithoutChangingWorkspaceFlow` | live-preview baseShutter feeds start: name "6 stops - 4s", basis "Base 1/15s · 6 stops", dur 4; detent stays compact

**TimerSelectedModelIdentityTests** (PTimerKit) — PTIMER-171 selected-model identity capture
- `testOfficialAlternateModelsCaptureDistinguishingLabels` | default→nil label; official table→"Official table" (selectorLabel); app formula→"App formula" (profile-name fallback), no qualifier
- `testOhzartCommunityTableKeepsSourceNamedLabel` | community table → label "Ohzart" + qualifier "Unofficial" both travel
- `testUnofficialOverrideWithoutSelectorLabelKeepsQualifierOnly` | unofficial w/o selectorLabel → label nil, qualifier "Unofficial"
- `testCustomProfileIdentityIsUnchanged` | custom film → label nil, qualifier "Custom", customProfileSummary set
- `testFilmDescriptorPrefersModelLabelOverQualifier` | descriptor prefers model label: "Fomapan… · Ohzart", "Tri-X 400 · App formula"
- `testFilmDescriptorWithoutModelLabelRendersAsBefore` | no label → "Portra 400 · Unofficial" / "Tri-X 400"
- `testPersistedSnapshotRoundTripsModelLabel` | metadata snapshot round-trips selectedModelLabel="App formula"
- `testLegacySnapshotWithoutModelLabelDecodesNil` | legacy snapshot (no field) → selectedModelLabel nil, qualifier preserved
- `testStartPersistsAndPublishesModelLabel` | start persists+publishes label; identitySnapshot exposes it; saved snapshot carries it
- `testRestoredMetadataCarriesModelLabel` | relaunch (state restored first, metadata bound on sync) → item carries label "Ohzart"+qualifier+name (identity immutability after relaunch)
- `testCloneInheritsModelLabel` | Start Again clone inherits selectedModelLabel (no silent model switch)

**TimerWorkspaceModelTests** (PTimerKit)
- `testStartTimerAddsRunningEntryToTimers` | start → running item w/ duration/name/basis
- `testStartTimerWithNonPositiveDurationDoesNotPersistMetadata` | dur 0 → nil id, no timer, no saved snapshot (metadata roll-back)
- `testPauseResumeLifecycleTransitions` | pause→.paused, resume→.running
- `testRemoveTimerDropsTimerAndClearsPersistedMetadata` | remove last → empty + clearCount≥1
- `testClearCompletedTimersOnlyRemovesCompletedEntries` | clearCompleted keeps running only
- `testCloningCompletedTimerStartsNewRunningTimerWithSameDuration` | clone: fresh id, running, same duration/name/basis; source unchanged (status/dur/completedAt/order)
- `testCloningCompletedTimerCopiesShootingContextIdentity` | clone copies cameraSlot/film/qualifier/exposureSource (identity capture: slot/film/source)
- `testCloningCompletedTimerPreservesFunctionalityWithoutShootingContext` | clone w/o context → nil slot/film/qualifier/source, still works
- `testCloneAssignsFreshOrderIndependentOfSource` | clone gets nextTimerOrder (not source order); nextOrder increments
- `testCloningRejectsNonCompletedTimer` | clone of running → nil, no new timer
- `testCloneIsIndependentLifecycleFromSource` | pausing clone does not mutate source completed state
- `testRestorePersistedMetadataPopulatesNamesAndOrdering` | restored nextTimerOrder=7 drives new timer order=7, next=8
- `testMultipleStartsAssignIncrementingOrder` | incrementing orders; workspace order [3,2,1] (LIFO)

**CalculatorTimerMetadataTests** (PTimerKit)
- `testStartTimerPublishesCapturedMetadataOnFirstRuntimeEmission` | start publishes exactly one non-empty emission; name "6 stops - 2s", basis "Base 1/30s · 6 stops"
- `testStartTimerCreatesRunningDisplayItemWithMetadataAndContext` | running item: name/remaining(2)/duration/basis + TimeDisplay + targetContext "2s · 2s" + timeContext "Ends <dt>"
- `testStartTimerFromDomainAPIUsesProvidedResult` | startTimer(from:30) → name "Timer - 30s"
- `testClearCompletedTimersRemovesCompletedDisplayItems` | clearCompleted clears completed from both VM and manager
- `testClearCompletedTimersPreservesActiveMetadataAndRemovesCompletedMetadataBeforeNewTimer` | clearCompleted keeps active metadata, drops completed; new timer prepended; names/basis order verified (identity immutability + LIFO)
- `testExistingTimerMetadataDoesNotChangeAfterInputUpdates` | later baseShutter/ndStop edits do not change existing timer name/basis (identity immutability)

**CalculatorTimerDisplaySemanticsTests** (PTimerKit)
- `testPausedTimerRemainingTimeStaysStableInViewModel` | paused remaining frozen(5) across tick
- `testPausedTimerDisplaySemanticsPreservePauseMetadataAndRemainResumable` | paused: remaining(5)/duration(8)/pausedAt; timeContext "Paused <dt>"; resumable
- `testResumeTimerUpdatesViewModelState` | resume → running, remaining(5) preserved; basis "Manual timer"
- `testCompletedTimerDisplaySemanticsPreserveOriginalDurationAndCompletionMetadata` | completed: remaining 0, duration(2), completedAt=start+2; targetContext nil; timeContext "Completed <dt> · just now"
- `testRunningTimerPrimaryIsRemainingSecondaryIsExactSeconds` | running display primary "01:22" (mm:ss), secondary "82s" (exact)
- `testCompletedTimerDisplaysOriginalDurationNotZero` | completed displays original duration "01:30", not "0s"
- `testTimerDisplayDoesNotDuplicateInformation` | target/time context do not duplicate "Ends"/basis/"Base"/"ND"/primary/secondary
- `testBasisSummaryRemainsStableAcrossStateChanges` | basisSummary stable across pause/resume (identity immutability)
- `testTimerStateTransitionDoesNotCorruptDisplayModel` | running"8s"→paused"5s"→resume"5s"→complete duration"8s" display integrity

**CalculatorTimerIntegrationTests** (PTimerKit; file = ExposureCalculatorViewModelTimerIntegrationTests)
- `testFilmModeCorrectedExposureTimerUsesQuantifiedCorrectedResult` | Tri-X corrected timer dur 2s; name "Tri-X 400 - 2s"; basis "Base 1s · 0 stops · Adjusted 1s · Tri-X 400 · Corrected 2s"
- `testFilmModeAdjustedShutterTimerStartsFromAdjustedValueWhenCorrectedIsQuantified` | adjusted-shutter timer dur 1s; basis "…Adjusted 1s · Tri-X 400"
- `testFilmModeLimitedGuidanceDoesNotProvideCorrectedExposureTimerSource` | limited-guidance (Portra) → corrected timer disabled, start no-ops; result kind .limitedGuidance
- `testFilmModeAdjustedShutterTimerStartsForLimitedGuidanceResult` | adjusted-shutter still allowed for limited guidance; dur 15s
- `testFilmModeBeyondConvertedFormulaSourceRangeStartsCorrectedExposureTimerFromFormulaPrediction` | Velvia beyond-source-numeric → corrected timer uses formula prediction pow(64,1.1821); kind .quantified
- `testFilmModeAdjustedShutterTimerStartsForUnsupportedResult` | Velvia adjusted-shutter dur 64s; basis "…Adjusted 64s · Velvia 50"
- `testDigitalModeStartTimerBehaviorRemainsUnchanged` | digital start dur 2s; name "6 stops - 2s"; basis "Base 1/30s · 6 stops"
- `testStartTimerUsesLivePreviewCalculationWhenPresent` | live ND preview(10) used at start → "10 stops - 30s", dur 30
- `testStartTimerUsesLiveBaseShutterPreviewCalculationWhenPresent` | live baseShutter preview(1/15) used → "6 stops - 4s", dur 4
- `testTargetDurationNeverChangesAcrossStateTransitions` | duration immutable across pause/resume/complete (identity immutability: base/nd/adjusted)

**Notes for parity audit**
- Core invariant set (Android must mirror): paused freezes wall clock; resume recomputes endDate=now+frozenRemaining and stays running even past original end; completion fires exactly once; reconcile completes-without-alert; restore reconstructs paused endDate from `pausedAt+pausedRemaining` and IGNORES legacy `expectedCompletionAt`; legacy `"stopped"` token → paused; corrupt snapshot → empty; notification schedule-on-start / cancel-on-pause / reschedule-on-resume / cancel-on-remove&complete; ordering active-LIFO + completed deferred; Start Again clone (fresh id/order/startDate, source untouched, inherits slot/film/source/model label); identity captured at start is immutable across later calculator edits, rename, and relaunch.
- `[ios-only]` (skip for Android parity unless platform equivalent exists): all `B4TimerLifecycleBaselineTests` (RecordReplay traces), all `LockScreenTimerCoordinatorTests` (Live-Activity/lock-screen exposer), and `testForegroundAlertServiceOnlyPlaysFeedbackWhileAppIsActive` (UIApplication state gating). The identity/ordering/snapshot factory tests are presentation-layer but platform-agnostic in intent.
- Path note: the 4th ExposureCalculator file's on-disk class name is `CalculatorTimerIntegrationTests` (filename `ExposureCalculatorViewModelTimerIntegrationTests.swift`).

## E — Camera slots + Target Shutter + film selection (~140 tests)

**[verdict]** ✅ **already-covered / blocker→done** for the protected
behavior: 4-slot session isolation, per-slot calculator/film/target state,
slot rename (trim/clear/isolation/immutable-after-start), per-slot Target
Shutter set/clear/restore + stop-difference presentation (no signed zero,
fraction snapping), the per-source start-action model (adjusted always
startable incl. limited guidance; corrected disabled with reason and no
fabricated value; target separate), film selection + authority/support
labels, and restore robustness. Restore sanitation (corrupt base/ND/target,
unknown film → digital, stale profile id → primary, schema/corrupt → defaults)
is closed (`CalculatorControllerTest`, `SlotSessionCodec`); the hardening passes
added stale-profile-id normalization, slot-name restore sanitation, and
custom-film id-reuse prevention (see *Restore / Persistence Hardening — Pass 1*
above).
Rows tagged `[ui-feel]` are the iOS wheel live-telemetry / momentum / quick↔fine
input-state behaviors → **android-replacement** (Android uses steppers + a
simpler target sheet). The 1/3-stop scale rows under `CalculatorModel` →
**android-replacement** (whole-stop only).

Recorded intent (iOS file · test — intent):

- CameraSlotSessionModel · testDefaultStateExposesAllFourSlotsAndStartsOnCameraOne | default: availableSlots = allOrdered (4), active = camera1, name "Camera 1"
- CameraSlotSessionModel · testInactiveSnapshotReturnsInitialDefaultUntilSlotIsVisited | unvisited inactive slot → `CameraSlotCalculatorSnapshot.initial`
- CameraSlotSessionModel · testActiveSlotHasNoStoredSnapshotInTheInactiveMap | active slot returns nil from inactive map (live models own it)
- CameraSlotSessionModel · testSwitchActiveSlotStoresOutgoingSnapshotAndReturnsIncomingDefault | switch captures outgoing snapshot, returns incoming `.initial`, new active absent from map
- CameraSlotSessionModel · testSwitchingBackRestoresStoredInactiveSnapshot | round-trip switch restores each slot's parked snapshot (per-slot isolation)
- CameraSlotSessionModel · testSwitchToActiveSlotIsNoOp | switch to already-active slot → nil, no state change
- CameraSlotSessionModel · testSwitchRejectsSlotsOutsideAvailableSet | switch to slot not in availableSlots → nil, active unchanged
- CameraSlotSessionModel · testInitialCustomDisplayNamesResolveDisplayName | seeded custom names route through identity(for:) and activeSlot
- CameraSlotSessionModel · testTwoSlotConfigurationIsAccepted | 2-slot config accepted (lower bound invariant)
- CameraSlotSessionModel · testFourUniqueSlotConfigurationIsAccepted | 4 unique slots accepted (upper bound; shipping config)
- CameraSlotSessionModel · testRestoreActiveSlotMovesActiveAndDropsStaleInactiveEntry | launch restore sets active slot AND drops its stale inactive snapshot
- CameraSlotSessionModel · testSetCustomDisplayNameUpdatesIdentity | setCustomDisplayName updates identity + activeSlot + map
- CameraSlotSessionModel · testRenamingOneSlotDoesNotAffectAnotherSlotLabel | rename isolation: other slots keep "Camera N" labels
- CameraSlotSessionModel · testRenameTrimsLeadingAndTrailingWhitespace | rename trims whitespace ("  Leica M6  " → "Leica M6")
- CameraSlotSessionModel · testRenameWithEmptyStringClearsCustomName | "" clears custom name → default label
- CameraSlotSessionModel · testRenameWithWhitespaceOnlyStringClearsCustomName | "   " clears custom name → default label
- CameraSlotSessionModel · testRenameWithNilClearsCustomName | nil clears custom name → default label
- CameraSlotSessionModel · testResetCustomDisplayNameRestoresDefault | reset drops custom name → "Camera 1"
- CameraSlotSessionModel · testRenameDoesNotMutateInactiveCalculatorSnapshot | rename of inactive slot leaves its parked calc snapshot intact (name/calc separate axes)
- CameraSlotSessionModel · testRenameForSlotOutsideAvailableSetIsIgnored | rename for slot outside availableSet silently ignored (no map poisoning)
- CameraSlotSessionModel · testRestoreCustomDisplayNamesReplacesPriorMap | bulk restore fully replaces runtime name map (no stale carryover)
- CameraSlotSessionModel · testRestoreCustomDisplayNamesTrimsAndDropsBlankEntries | bulk restore trims and drops blank entries
- CameraSlotSessionModel · testRestoreInactiveSnapshotsLoadsBulkAndDropsActiveEntry | bulk restore loads inactive snapshots, drops active slot's entry
- CameraSlotSessionPersistence · testAllFourCameraSlotsSaveAndRestore | 4-slot save+restore: each slot's film/baseShutter/ND round-trips independently
- CameraSlotSessionPersistence · testInactiveSlotsSurviveTwoRelaunches | regression: inactive-slot state survives TWO relaunches (restore must not overwrite session with active-only)
- CameraSlotSessionPersistence · testTargetShutterRoundTripsAcrossRelaunchPerSlot | per-slot Target Shutter round-trips; slot with no target restores nil (no leak)
- CameraSlotSessionPersistence · testCorruptedPersistedTargetIsSanitisedAtDecodeTime | negative/non-finite persisted target decodes as nil/inactive
- CameraSlotSessionPersistence · testLegacySingleContextMigratesToSessionOnFirstLaunch | legacy single-context migrates to active slot on first launch; next launch is session-self-sufficient (no legacy read)
- CameraSlotSessionPersistence · testInvalidFilmReferenceInPersistedSlotRestoresAsNoFilm | invalid persisted film id → "No film" fallback, no crash; other slot intact
- CameraSlotSessionPersistence · testStaleMigratedProfileIDFallsBackToDefaultTableProfile | stale pre-PTIMER-168 profile id dropped as override; film kept, falls back to default table profile ("Table-derived")
- CameraSlotSessionPersistence · testSchemaVersionMismatchIsIgnoredOnLoad | future schemaVersion (+100) rejected on load → fresh defaults (active=camera1)
- CameraSlotSessionPersistence · testCustomDisplayNameRoundTripsAcrossRelaunch | custom slot names round-trip; untouched slots keep "Camera N"
- CameraSlotSessionPersistence · testResetClearsPersistedCustomDisplayName | reset persists nil customDisplayName → relaunch shows default label
- CameraSlotSessionPersistence · testSnapshotWithoutRenameOmitsCustomDisplayNameField | no-rename snapshot persists nil customDisplayName (byte-compat pre-PTIMER-123)
- CameraSlotSessionPersistence · testLegacySnapshotWithoutCustomDisplayNameDecodesAsDefault | legacy snapshot without customDisplayName field decodes to default label
- CameraSlotSessionPersistence · testFourSlotSaveAndRestoreKeepsRenamesWithCalculatorState | renames + calc state both round-trip in 4-slot save/restore
- CameraSlotSessionPersistence · testOfficialProfileSurvivesRelaunchAfterPreviouslyChoosingUnofficial | re-selecting catalog-default (Official) clears stale Unofficial override on relaunch; selection alone persists (no calc change)
- CameraSlotSessionPersistence · testAppFormulaAlternateModelSurvivesRelaunch | selected alternate profile id (Tri-X App formula) round-trips via selectProfileVariant→session-save
- CameraSlotSessionPersistence · testPresetFilmSelectionSurvivesRelaunch | single-profile film (Kentmere) survives when selection is only mutation; no override
- CalculatorViewModelCameraSlots · testTwoSlotsKeepDifferentFilmAndNonFilmWorkflowState | per-slot film vs non-film workflow isolation across switch+return
- CalculatorViewModelCameraSlots · testTwoFilmSlotsHoldDifferentFilmsAcrossSwitchAndReturn | two slots hold different films (Tri-X / Portra); unvisited slot starts no-film
- CalculatorViewModelCameraSlots · testExposureInputsStaySlotSpecificAcrossMutations | per-slot baseShutter/ND isolation; mutating active doesn't bleed to inactive
- CalculatorViewModelCameraSlots · testAdjustedShutterResultStaysSlotSpecific | per-slot adjusted (digital) shutter result isolation
- CalculatorViewModelCameraSlots · testCorrectedExposureStaysSlotSpecific | same film, different inputs → per-slot corrected (film) exposure isolation
- CalculatorViewModelCameraSlots · testActiveCameraSlotIDPublishesOnSwitch | activeCameraSlotID publishes on switch
- CalculatorViewModelCameraSlots · testStartedDigitalTimerCarriesActiveSlotIdentityAndDigitalSource | started digital timer carries active slot identity + `.digitalResult`, no film
- CalculatorViewModelCameraSlots · testFilmAdjustedAndCorrectedTimersBothCarrySlotIdentity | both film timers carry active slot identity (camera3)
- CalculatorViewModelCameraSlots · testActivePageStateMatchesLiveCalculatorState | active page state mirrors live calc state (isActive, name, inputs, film)
- CalculatorViewModelCameraSlots · testInactivePageStateReadsStoredSnapshot | inactive page state read from stored snapshot (not live)
- CalculatorViewModelCameraSlots · testInactivePageDigitalSlotShowsNoFilmDisplay | unvisited inactive page → no film, "No film", defaults
- CalculatorViewModelCameraSlots · testCalculationResultForInactivePageUsesItsOwnInputs | inactive page calc result uses its own slot inputs, not live
- CalculatorViewModelCameraSlots · testSelectNextCameraSlotAdvancesAndStopsAtLast | next-slot pager advances, bounded no-op at last
- CalculatorViewModelCameraSlots · testSelectPreviousCameraSlotReversesAndStopsAtFirst | prev-slot pager reverses, bounded no-op at first
- CalculatorViewModelCameraSlots · testActiveCameraSlotPageTextFollowsCurrentSlot | page text "Camera N, n of 4" follows current slot
- CalculatorViewModelCameraSlots · testStartedTimerCarriesFilmDisplayNameAndExposureSource | started film timer carries filmDisplayName + `.filmAdjustedShutter` + slot id
- CalculatorViewModelCameraSlots · testTimerIdentityIsImmutableAfterSlotAndFilmChanges | started timer identity frozen at start; later slot/film changes don't rewrite it
- CalculatorViewModelCameraSlots · testManualTimerDoesNotCaptureCameraSlotOrFilmIdentity | manual timer (startTimer(from:)) captures no slot/film/source/identitySnapshot
- CalculatorViewModelCameraSlots · testInactivePageDisablesBothAdjustedAndCorrectedActions | inactive page disables BOTH adjusted+corrected start actions in state (not just view)
- CalculatorViewModelCameraSlots · testCalculatorContextPersistsActiveSlotIDForNonDefaultSlots | non-default active slot persisted (activeCameraSlotIDRaw="camera3")
- CalculatorViewModelCameraSlots · testCalculatorContextOmitsActiveSlotIDForDefaultSlot | default camera1 emits nil slot id (legacy byte-compat)
- CalculatorViewModelCameraSlots · testRelaunchRestoresPersistedActiveSlot | relaunch restores persisted non-default active slot (camera3) with its values
- CalculatorViewModelCameraSlots · testSingleSlotBehaviorMatchesSingleSlotBaseline | never-switched: inputs land on camera1, timer carries camera1 identity (not nil)
- CalculatorViewModelCameraSlotRename · testRenameUpdatesActiveTitleAndPreservesCalculatorState | rename updates active title + page state, preserves calc state (label-only)
- CalculatorViewModelCameraSlotRename · testRenamingOneSlotDoesNotAffectAnotherSlotsLabelOrState | rename isolation: other slot keeps default label + parked inputs
- CalculatorViewModelCameraSlotRename · testRenameSurvivesSlotSwitch | rename survives slot switch away+back
- CalculatorViewModelCameraSlotRename · testResetRestoresDefaultSlotLabel | reset restores "Camera 1", custom name nil
- CalculatorViewModelCameraSlotRename · testRenameWithWhitespaceOnlyClearsCustomName | whitespace-only rename clears custom name
- CalculatorViewModelCameraSlotRename · testRenamingDoesNotChangeCameraSlotIDRawValues | rename never shifts stable slot rawValues (persisted ids)
- CalculatorViewModelCameraSlotRename · testStartedTimerSlotLabelIsImmutableAfterRename | started timer slot label immutable after later rename
- CalculatorViewModelCameraSlotRename · testNewTimerAfterRenameUsesUpdatedLabel | timer started after rename stamps renamed label (capture at start)
- CalculatorViewModelCameraSlotRename · testRenamePublishesCustomDisplayNamesOnFacade | rename publishes cameraSlotCustomDisplayNames for SwiftUI binding (no slot switch)
- CameraSlotIdentity · testDefaultIdentityFallsBackToCanonicalLabel | no custom name → canonical "Camera 2", customDisplayName nil
- CameraSlotIdentity · testCustomDisplayNameWinsOverDefault | custom name wins over default
- CameraSlotIdentity · testWhitespaceCustomNameFallsBackToDefault | whitespace-only custom name → default label
- CameraSlotIdentity · testNilCustomNameFallsBackToDefault | nil custom name → default label
- CameraSlotIdentity · testCustomDisplayNameIsTrimmedWhenRendered | custom name trimmed when rendered
- CameraSlotIdentity · testConvenienceInitMapsDefaultLabelToNoCustomName | convenience init: name == default → no custom name recorded
- CameraSlotIdentity · testConvenienceInitMapsDifferingNameIntoCustomSlot | convenience init: differing name → stored as custom
- FilmSelectionModel · testDefaultStateIsNoSelectionWithCatalogAvailable | default: no film/override, catalog non-empty
- FilmSelectionModel · testSelectPresetFilmSetsActiveFilmAndPersistsSnapshot | select film sets active + persists snapshot bundling calc inputs + film id
- FilmSelectionModel · testClearSelectedPresetFilmResetsSelectionAndPersistsCleared | clear film resets selection, persists normalized snapshot with nil film id (not clearSnapshot)
- FilmSelectionModel · testSelectEntryAppliesProfileOverride | selectEntry applies film + unofficial profile override
- FilmSelectionModel · testRestoreContextResolvesValidFilmAndReturnsCalcInputs | restore resolves valid film id, returns calc inputs, hadInvalidFilmReference=false
- FilmSelectionModel · testRestoreContextWithUnknownFilmIDClearsSnapshot | restore with unknown film id → hadInvalidFilmReference=true, no film, snapshot cleared
- FilmSelectionModel · testRestoreContextReturnsNilWhenStoreIsEmpty | restore returns nil for empty store
- FilmSelectionModel · testFilmRowAuthorityLabelMapsAuthorityValuesToTextOrNil | authority label: official profile → "Official guidance"; nil → nil
- FilmSelectionModel · testFilmRowISOTextRendersStructuredISOFromFilmIdentity | ISO text from structured identity ISO (125 → "ISO 125")
- FilmSelectorSupportPresenter · testNoFilmMapsToNone | nil film → `.none` (no indicator)
- FilmSelectorSupportPresenter · testUserDefinedAuthorityMapsToCustomFormulaPrediction | userDefined authority → `.userDefinedFormulaPrediction` (Custom badge)
- FilmSelectorSupportPresenter · testOfficialFilmsMapToExpectedSupportState | film→support-state case table: Provia/Tri-X/Fomapan100/HP5 → officialQuantifiedPrediction; Portra/Ektar/Ektachrome → officialLimitedGuidance
- FilmSelectorSupportPresenter · testProfileWithOnlyThresholdMapsToNoQuantifiedPrediction | official threshold-only profile → `.noQuantifiedPrediction`
- FilmSelectorSupportPresenter · testProfileWithNoRulesMapsToNoQuantifiedPrediction | official empty-rules profile → `.noQuantifiedPrediction`
- FilmSelectorSupportPresenter · testUnofficialPracticalProfileMapsToUnofficial | Portra + unofficial override → `.unofficialPractical`
- FilmSelectorSupportPresenter · testPromotedUnofficialPracticalPrimaryMapsToUnofficial | RETRO 400S (promoted unofficial primary) → `.unofficialPractical`
- FilmSelectorSupportPresenter · testUnofficialOverrideIsNotConflatedWithOfficialPrediction | unofficial override distinct from official; never officialQuantifiedPrediction
- FilmSelectorSupportPresenter · testOfficialAndLimitedAndUnsupportedAndUnofficialMapToDistinctStates | 4 support states are distinct values
- FilmSelectorSupportPresenter · testEachOfficialStateHasItsOwnIcon | 3 official states have distinct SF Symbols (color-independent)
- FilmSelectorSupportPresenter · testUnofficialUsesVisibleTextBadgeNotIconOnly | unofficial uses text badge "Unofficial", no icon
- FilmSelectorSupportPresenter · testUnofficialBadgeIsNeitherStarMarkerNorColorOnly | unofficial badge spells "Unofficial", not "*"
- FilmSelectorSupportPresenter · testEachStateExposesDistinctAccessibilityLabel | 4 distinct a11y labels (exact strings asserted)
- FilmSelectorSupportPresenter · testNoneStateHasNoIndicatorOrLabel | `.none` has no icon/badge/a11y label
- FilmSelectorSupportPresenter · testFilmRowAuthorityLabelReflectsProvenance | authority label by provenance: official→"Official guidance", app-derived→"App-derived formula", Ohzart→"Unofficial practical"; app-derived never reads official
- ExposureCalculatorViewModelFilmMode · testFilmRowDefaultsToNoFilmSelectorState | default: no film, not film-workflow, "No film", no details
- ExposureCalculatorViewModelFilmMode · testSelectingPresetFilmUpdatesActiveCalculatorContextAndDisplayState | select film → context/workflow active, primary "Tri-X 400" (no ISO), secondary "Official guidance"
- ExposureCalculatorViewModelFilmMode · testReplacingPresetFilmUpdatesActiveCalculatorContext | replacing film updates context + display (Portra 400)
- ExposureCalculatorViewModelFilmMode · testFilmSelectorEntriesKeepISOAsSecondaryMetadata | Portra single top-level row (no dup unofficial), no override; ISO secondary per stock
- ExposureCalculatorViewModelFilmMode · testChangingFromPresetFilmToNoFilmReturnsToDigitalWorkflow | clear film → digital workflow, no binding/result
- ExposureCalculatorViewModelFilmMode · testSelectingPresetFilmActivatesFilmWorkflowAndReciprocityBinding | select film activates reciprocity binding (official, manufacturerPublished, calculated time)
- ExposureCalculatorViewModelFilmMode · testNoFilmBehavesAsDigitalWorkflow | no film → digital calc result only (1/30 ND6 → 2s)
- ExposureCalculatorViewModelFilmMode · testFilmSelectorSectionsGroupByManufacturerWithNoFilmAsHeaderlessLeadingSection | sections: leading headerless "No film"+"New custom film"; rest manufacturer cards alpha-sorted; flat==flattened; Portra single Kodak row
- ExposureCalculatorViewModelFilmMode · testFilmSelectorEntriesKeepNoFilmFirstAndShowISOWhenAvailable | "No film" first; entries' secondary is "ISO …" or "Unofficial"
- FilmModeAuthorityLabel · testFilmModeDetailsUnofficialProfileShowsUnofficialAuthorityAndFormula | unofficial details: formula "Tc=Tm^1.34", "Formula-derived" badge, no Profile/Formula/Sources sections, subtitle "Unofficial practical"
- FilmModeAuthorityLabel · testFilmModeDetailsOfficialProfileShowsOfficialAuthorityInSubtitle | official details subtitle "Official guidance", no Profile section
- FilmModeAuthorityLabel · testFilmSelectionDisplayStateOfficialProfileShowsOfficialGuidanceLabel | official Portra main row secondary "Official guidance"
- FilmModeAuthorityLabel · testFilmSelectionDisplayStateUnofficialProfileShowsUnofficialPracticalLabel | unofficial Portra main row secondary "Unofficial practical"
- FilmModeAuthorityLabel · testFilmSelectionDisplayStateOfficialAndUnofficialProfileAreDistinguishable | same primary name, distinct secondaries (official vs unofficial)
- FilmModeAuthorityLabel · testFilmModeDetailsUnofficialProfileShowsFormulaNearGraphWithoutProfileSection | unofficial: graph+formula present, no Profile/Formula/Sources sections, subtitle unofficial
- FilmModeAuthorityLabel · testFilmRowOfficialGuidanceLabelAppliesToAllOfficialPresetFilms | every official-authority film shows "Official guidance" (consistency)
- FilmModeAuthorityLabel · testFilmRowLabelClearedWhenNoFilmSelected | no-film → no secondary qualifier
- FilmModeAuthorityLabel · testFilmModeDetailsDisplayStateIsNonNilForOfficialAndUnofficialProfile | details display state non-nil for both official+unofficial (sheet opens)
- FilmModeAuthorityLabel · testFilmModeDetailsUnofficialProfileSubtitleMatchesMainRowAuthorityLabel | unofficial details subtitle reuses main-row "Unofficial practical"; no "Official"
- FilmModeAuthorityLabel · testFilmModeDetailsUnofficialProfileSurfacesAuthorityCaveatNote | unofficial details surfaces caveat "Not a Kodak-published profile"
- FilmModeAuthorityLabel · testFilmModeDetailsUnofficialProfileDoesNotUseOfficialSourceWording | authority-leak guard: unofficial never uses source-range wording / "Source reference" / "Guidance boundary" sections
- FilmModeAuthorityLabel · testFilmModeDetailsOfficialProfileKeepsOfficialLimitedGuidanceBeyondThreshold | official Portra beyond 10s threshold: "Official guidance", "No quantified prediction", nil corrected
- FilmModeAuthorityLabel · testFilmModeDetailsSourceBackedProfilesStillShowSourceRangeWordingBeyondSupportedBound | source-backed films (Provia/Tri-X/T-MAX100/400/Velvia50/100/Acros II) past bound → "Beyond source range" badge
- FilmModeAuthorityLabel · testFilmModeDetailsSectionOrderIsConsistentAcrossOfficialAndUnofficialProfile | no Profile/Formula sections either profile; Sources (if present) is last
- FilmModeFormulaExtrapolation · testTableProfileBelowOneSecondStaysTableDerivedNotUnsupported | Tri-X 0.5s → "Table-derived", quantified, corrected≈0.812s (not Unsupported)
- FilmModeFormulaExtrapolation · testTableProfileAtOneSecondReturnsCorrectedExposureFromTablePrediction | Tri-X 1s anchor → "Table-derived", corrected 2s exactly, primary "2s"
- FilmModeFormulaExtrapolation · testCorrectedExposureNumericDisplayUsesRestoredTimeFormatting | CHS 100 II 8s in-range: no "≈" prefix; primary == formatReciprocityDuration
- FilmModeFormulaExtrapolation · [ui-feel] testReciprocityDisplayFormattingUsesReadableUserFacingPrecision | duration/axis formatter precision rules (seconds/clock/days bands)
- FilmModeFormulaExtrapolation · testTopLevelCorrectedExposureCoarsensVeryLongDurationsIntoYears | HP5 huge ND → quantified, primary "≈37y" (year coarsening), numeric exact retained
- FilmModeFormulaExtrapolation · testReciprocityDisplayStateUsesReadableAdjustedAndCorrectedValues | Tri-X 5s: corrected "15s", comparison layout, adjusted "4s", sub-minute no detailText
- FilmModeFormulaExtrapolation · [ui-feel] testResultDurationDisplayPairsClockPrimaryWithSecondsComparison | result-row duration: clock primary + whole-seconds secondary in min/hour bands; seconds-only below 1m
- FilmModeFormulaExtrapolation · testNoCorrectionDetailsUseSharedComparisonLayoutAndPlotIdentityCurrentPoint | Tri-X sub-0.1s → "No correction", comparison layout, identity current point with `.noCorrection` marker
- FilmModeFormulaExtrapolation · testTableProfileSmallerSupportedExposureDoesNotRegressToUnsupported | Tri-X smaller-of-two supported exposures both quantified (no regress to unsupported)
- FilmModeFormulaExtrapolation · testTableProfileBeyondSourceRangeKeepsTablePredictionAsQuantifiedResult | Tri-X past table → "Beyond source range" (.unsupported tone), still quantified; basis unsupportedOutOfPolicyRange; usesTableInterpolation
- FilmModeFormulaExtrapolation · testTableProfileVeryLongExposureStaysBeyondSourceRangeWithFormulaContinuation | Tri-X very long → "Beyond source range", quantified, coarsened primary, empty seconds secondary
- FilmModeFormulaExtrapolation · testBarePowerLawProfileLongAdjustedExposureRemainsFormulaDerivedInsteadOfUnsupported | HP5 long → "Formula-derived" (.measured), quantified, corrected timer enabled
- FilmModeFormulaExtrapolation · testFilmModeLimitedGuidanceResultKeepsCorrectedExposureRowStateWithoutNumericValue | Portra 15s limited-guidance: "No quantified prediction", nil corrected, corrected timer disabled w/ a11y hint, adjusted timer enabled
- FilmModeFormulaExtrapolation · testFilmModeBeyondConvertedFormulaSourceRangeKeepsCorrectedExposureRowQuantifiedFromFormula | Velvia50 128s beyond converted-formula range: "Beyond source range", quantified formula prediction, "≈" marked, corrected timer enabled, isOutsideManufacturerGuidance
- CalculatorContextPersistence · testSelectingPresetFilmPersistsWorkingContextValues | selecting film persists film id + base 1/15 + ND4 snapshot
- CalculatorContextPersistence · testRelaunchRestoresValidFilmModeWorkingContextAndReciprocityBinding | relaunch restores film+inputs+scale token; binding valid, "Table-derived"
- CalculatorContextPersistence · testRelaunchWithoutStoredPresetFallsBackToNoFilmState | empty store → no film, "No film", nil binding/result
- CalculatorContextPersistence · testRelaunchWithInvalidStoredPresetIdentifierFallsBackSafely | invalid stored film id → no-film fallback, snapshot cleared
- CalculatorContextPersistence · testInvalidStoredPresetFallbackLeavesDigitalWorkflowUnaffected | invalid film fallback leaves digital calc working (1/30 ND6 → 2s)
- CalculatorContextPersistence · testDigitalWorkingContextPersistsWithoutSelectedFilm | digital context persists with nil film id
- CalculatorContextPersistence · testRelaunchRestoresDigitalWorkingContextWithoutSelectedFilm | relaunch restores digital inputs, no film (base1 ND3 → 8s)
- CalculatorContextPersistence · testRelaunchWithInvalidStoredNumericValuesFallsBackToDefaultCalculatorInputs | invalid stored numeric (base0.3 ND99) → defaults (1/30, ND0), keeps film
- CalculatorContextPersistence · testResetFilmModeWorkingContextClearsSelectionInputsAndPersistedSnapshot | reset clears film/inputs/result + persisted snapshot; canReset toggles
- CalculatorContextPersistence · testRelaunchRestoresTimerCardIdentityMetadataForMultipleTimers | relaunch restores per-timer name/basisSummary/order/status for multiple timers
- CalculatorContextPersistence · testRelaunchWithoutMetadataSnapshotFallsBackToDefaultCardIdentity | no metadata snapshot → default card identity ("Timer - 10s","Manual timer")
- CalculatorContextPersistence · testOrphanedMetadataIsDroppedWhenNoTimersRestore | orphaned metadata dropped when no timers restore
- CalculatorContextPersistence · testOrphanedMetadataIsFilteredOutWhenSomeTimersRestore | orphaned metadata filtered to only matched timer ids
- CalculatorContextPersistence · testRemovingLastTimerClearsPersistedTimerAndMetadataSnapshots | removing last timer clears both persisted snapshots
- CalculatorModel · testDefaultInputsProduceFullStopSnappedResult | default 1/30 ND0 fullStop → result 1/30 (snap)
- CalculatorModel · testNDStopChangeUpdatesCalculationResult | ND3 on 1/30 → snaps to 1/4
- CalculatorModel · testBaseShutterChangePropagatesToCalculationResult | base 1s ND0 → result 1s
- CalculatorModel · testNonPositiveBaseShutterSurfacesAsFailure | base 0 → `.nonPositiveBaseShutter` failure
- CalculatorModel · testCalculateOverloadDoesNotMutateStoredInputs | preview overload doesn't mutate stored inputs
- CalculatorModel · [ui-feel] testEffectiveBaseShutterFallsBackToCommittedValueWhenPreviewIsNil | live preview nil → effective falls back to committed
- CalculatorModel · [ui-feel] testUpdateLivePreviewSetsOverlayWhenDifferentFromCommitted | live preview overlay set when differs from committed
- CalculatorModel · [ui-feel] testUpdateLivePreviewClearsOverlayWhenEqualToCommitted | live preview equal to committed clears overlay
- CalculatorModel · [ui-feel] testClearLivePreviewExplicitlyDropsOverlay | explicit clear drops live preview overlay
- TargetShutterModel · testInitialStateIsInactive | default: targetSeconds nil, inactive
- TargetShutterModel · testSetTargetActivatesModelWithFinitePositiveValue | setTarget(60) activates, value 60
- TargetShutterModel · testSetTargetRejectsEveryNonFinitePositiveInput | zero/neg/NaN/inf/nil rejected → nil+inactive (fresh & prior-valid arrange)
- TargetShutterModel · testClearReturnsModelToInactiveState | clear → nil + inactive
- TargetShutterModel · testInitializerSanitizesInvalidInputs | init(-10) → nil + inactive
- TargetShutterModel · testInitializerAcceptsValidInputs | init(1200) → active, value 1200
- TargetShutterModel · testLastUsedSeconsStartsNil | lastUsed starts nil
- TargetShutterModel · testInitializerSeedsLastUsedFromValidValue | init(600) seeds lastUsed 600
- TargetShutterModel · testInitializerLeavesLastUsedNilForInvalidSeed | init(-1) leaves lastUsed nil
- TargetShutterModel · testSetTargetUpdatesLastUsed | setTarget updates lastUsed (120→900)
- TargetShutterModel · testClearPreservesLastUsedMemory | clear preserves lastUsed (300)
- TargetShutterModel · testInvalidSetTargetDoesNotEraseLastUsedMemory | invalid setTarget (zero/neg/NaN/inf/nil) preserves lastUsed 420
- TargetShutterPresenter · testInactiveTargetProducesUnavailableDisplayState | nil target → `.unavailable(.inactive)`
- TargetShutterPresenter · testZeroTargetProducesUnavailableDisplayState | zero target → `.unavailable(.inactive)`
- TargetShutterPresenter · testNonFiniteTargetProducesUnavailableDisplayState | infinity target → `.unavailable(.inactive)`
- TargetShutterPresenter · testActiveTargetWithUnavailableComparisonPreservesTarget | active target + `.unavailable` comparison → target kept, comparison/stopDiff nil
- TargetShutterPresenter · testDigitalWorkflowComparesAgainstAdjustedShutter | 120 vs adjusted 60 → "Adjusted Shutter", +1 stops longer
- TargetShutterPresenter · testFilmComparisonHasReadableLabel | film comparison label "Corrected Exposure"
- TargetShutterPresenter · testFilmWorkflowComparesAgainstCorrectedExposure | 18m vs corrected 22m → "Corrected Exposure", shorter, log2(18/22) stops
- TargetShutterPresenter · testComparisonValueZeroFallsBackToUnavailableComparison | comparison source 0 → target kept, comparison/stopDiff nil
- TargetShutterPresenter · testComparisonValueNonFiniteFallsBackToUnavailableComparison | comparison source NaN → comparison/stopDiff nil
- TargetShutterPresenter · testStopDifferenceMatchWhenWithinEpsilon | 0.001 → match, "0 stops"
- TargetShutterPresenter · testStopDifferenceExactZeroIsMatch | 0 → match, "0 stops"
- TargetShutterPresenter · testStopDifferencePositiveOneThirdSnapsToFraction | +1/3 → "+⅓ stop" (singular, vulgar glyph)
- TargetShutterPresenter · testStopDifferenceNegativeTwoThirdsSnapsToFraction | -2/3 → "−⅔ stop" (Unicode minus, singular)
- TargetShutterPresenter · testStopDifferenceWholeStopRendersAsInteger | 2 → "+2 stops"
- TargetShutterPresenter · testStopDifferenceMixedFractionRenders | 1⅓ → "+1⅓ stops"
- TargetShutterPresenter · testStopDifferenceNearOneThirdSnapsToOneThird | 0.36 → snaps "+⅓ stop"
- TargetShutterPresenter · testStopDifferenceRoundingToZeroThirdsIsTreatedAsMatch | 0.14/-0.14 → match "0 stops" (no signed zero)
- TargetShutterPresenter · testStopDifferenceNonFiniteFallsBackToMatchString | NaN → match "0 stops"
- TargetShutterPresenter · testStopDifferenceNeverEmitsSignedZeroAcrossSnapZone | invariant: no "+0"/"−0"/"-0" across snap-zone sweep
- CalculatorViewModelTargetShutter · testTargetShutterDefaultsToInactive | default inactive, nil, `.unavailable(.inactive)`, can't start timer
- CalculatorViewModelTargetShutter · testSetTargetShutterAcceptsValidDurationsAndEnablesTimer | 1/120/3600 each activate, verbatim value, enable timer
- CalculatorViewModelTargetShutter · testClearTargetShutterReturnsToInactive | clear → inactive + nil
- CalculatorViewModelTargetShutter · testTargetShutterRemainsFixedWhileBaseShutterChanges | target fixed while base/ND change
- CalculatorViewModelTargetShutter · testInvalidTargetShutterValueIsRejected | -10 rejected → inactive, can't start
- CalculatorViewModelTargetShutter · testDigitalWorkflowComparesAgainstAdjustedShutter | digital: 128 vs adjusted 64 → "Adjusted Shutter", +1 stop
- CalculatorViewModelTargetShutter · testFilmWorkflowComparesAgainstQuantifiedCorrectedExposure | Tri-X film: target 4 vs corrected≈2 → "Corrected Exposure", +1 stop
- CalculatorViewModelTargetShutter · testFilmWorkflowLimitedGuidanceDoesNotFabricateStopDifference | Portra limited-guidance: target kept, NO comparison/stopDiff (no fabrication vs adjusted)
- CalculatorViewModelTargetShutter · testFilmWorkflowBeyondConvertedFormulaSourceRangeComparesAgainstFormulaPrediction | Velvia50 beyond-source quantified: compares vs formula corrected pow(64,1.1821)
- CalculatorViewModelTargetShutter · testTargetMatchProducesMatchKind | target==adjusted 1s → match "0 stops"
- CalculatorViewModelTargetShutter · testStartTargetShutterTimerUsesTargetDurationForAnyLength | timer duration == target verbatim, `.targetShutter` source (short & 8h)
- CalculatorViewModelTargetShutter · testStartTargetShutterTimerStampsTargetMetadata | digital target timer: name "Target - 120s", basis "Target 120s", active slot id
- CalculatorViewModelTargetShutter · testStartTargetShutterTimerWithoutTargetIsNoop | start with no target → no timer
- CalculatorViewModelTargetShutter · testStartTargetShutterTimerNamePrefixesFilmAndTargetWhenFilmActive | film+target timer name "Tri-X 400 · Target - 120s"
- CalculatorViewModelTargetShutter · testTargetTimerCanCoexistWithAdjustedTimer | target + digital timers coexist (2 timers, distinct sources)
- CalculatorViewModelTargetShutter · testTargetShutterIsPerSlotAndDoesNotLeakWhenSwitching | per-slot target: camera2 starts nil, camera1's value can't leak
- CalculatorViewModelTargetShutter · testInactiveSlotDoesNotLeakLastUsedAsSheetSeed | slot-isolation: global lastUsed must NOT seed other slot's sheet; inactive slots report `.unavailable(.inactive)`
- CalculatorViewModelTargetShutter · testTargetShutterRestoredOnSlotReturn | per-slot target restored on round-trip (cam1 5m / cam2 1h)
- CalculatorViewModelTargetShutter · testInactiveSlotPageExposesStoredTargetWhileActiveSlotStaysInactive | inactive page surfaces stored target (cam1 2h available) while active slot inactive
- CalculatorViewModelTargetShutter · testResetFilmModeWorkingContextClearsActiveSlotTarget | workspace reset drops active slot's target
- CalculatorViewModelTargetShutter · testActiveTargetCountsAsResettableContext | setting target exposes Reset action (default-scale fixture)
- CalculatorViewModelTargetShutter · testTargetShutterAcceptsEightHourDuration | 8h target vs adjusted 64 → log2(28800/64)≈8.81 stops longer
- CalculatorViewModelTargetShutter · testLastUsedTargetMemoryStartsNilThenTracksLatestSet | lastUsed starts nil, tracks latest set (120→900)
- CalculatorViewModelTargetShutter · testLastUsedTargetSurvivesClear | lastUsed (600) survives clear
- CalculatorViewModelTargetShutter · testLastUsedTargetSurvivesSlotSwitch | lastUsed (900) survives slot switch (cam2 still nil target)
- CalculatorViewModelTargetShutter · testInvalidSetTargetDoesNotAffectLastUsedMemory | invalid setTarget(-1) preserves lastUsed 300
- CalculatorViewModelTargetShutter · testCamera2TargetWritesAndClearsDoNotAffectCamera1StoredTarget | per-slot isolation: cam2 set/clear doesn't touch cam1's stored 5m
- TargetShutterInputState · testQuickSelectionUpdatesDraftAndDerivedFineImmediately | Quick change → draft + derived Fine update immediately (480→8m)
- TargetShutterInputState · testQuickSelectionDerivedFineForCompoundValue | Quick 7200 → Fine 2h0m0s
- TargetShutterInputState · testFineSelectionUpdatesDraftImmediately | Fine change → draft 65, Quick highlight cleared, anchor nearest 60
- TargetShutterInputState · testStaleQuickEmitDoesNotOverwriteFine | stale Quick emit while Fine active dropped (draft 65 kept)
- TargetShutterInputState · testStaleFineEmitDoesNotOverwriteQuick | stale Fine emit while Quick active dropped (draft 120 kept)
- TargetShutterInputState · testQuickToFineCarriesDraftIntoFineWheels | Quick→Fine carries draft (240→4m), clears Quick highlight
- TargetShutterInputState · testFineToQuickParksAnchorOnNearestPresetWithoutAutoSelect | Fine→Quick parks anchor nearest (390→480), no auto-select
- TargetShutterInputState · testModeTransitionsPreserveCustomDraft | custom seed 65 opens Fine; draft preserved across mode swaps
- TargetShutterInputState · testInitialModeIsQuickWhenSeedMatchesPreset | seed matching preset (7200) → Quick mode
- TargetShutterInputState · testInitialModeIsFineForCustomSeed | custom seed (2h9m) → Fine mode
- TargetShutterInputState · testNilSeedFallsBackToDefaultForSlotIsolation | nil seed → default (slot-isolation: no leak of other slot's value)
- TargetShutterInputState · testInitialSanitizesInvalidSeed | NaN/neg/0 seed → default 60
- TargetShutterInputState · testInitialClampsHugeSeedToMaximum | huge seed (999999) → maxTotalSeconds (23:59:59)
- TargetShutterInputState · testInitialEnabledFalseOpensOffWithSeedPreserved | initialEnabled=false → cleared/Off, seed preserved as dimmed context
- TargetShutterInputState · testClearPreservesDraftAndFlagsOff | clearDraft preserves draft 120, flags Off, clears highlight
- TargetShutterInputState · testWheelEmitsIgnoredWhileOff | while Off wheel emits ignored (no auto-rearm, draft unchanged)
- TargetShutterInputState · testReArmRestoresPreservedDraft | reArm restores preserved draft 240 (no re-seed)
- TargetShutterInputState · testReArmSeedsFromSeedWhenDraftIsZero | reArm with draft 0 seeds from seed (480)
- TargetShutterInputState · testClearedFlagSurvivesModeTransitions | cleared/Off flag survives Quick↔Fine swaps
- TargetShutterInputState · testDraftSecondsIsTheCommittedValueAfterEdits | Confirm commits exactly draftSeconds (195) after edits
- TargetShutterInputState · testQuickIsExactMatchTracksDraft | quickIsExactMatch true on preset seed, false after Fine edit
- TargetShutterInputState · [ui-feel] testActiveQuickLiveTelemetryUpdatesDisplayNotDraft | active Quick live telemetry → display only; draft + anchor still (momentum)
- TargetShutterInputState · [ui-feel] testActiveFineLiveTelemetryUpdatesDisplayNotDraft | active Fine live telemetry → display only; draft still
- TargetShutterInputState · [ui-feel] testSettleClearsLiveValue | settled selection clears live value, commits draft 900
- TargetShutterInputState · [ui-feel] testInactiveQuickLiveTelemetryIgnoredAfterSwitchToFine | stale Quick live emit after switch to Fine ignored
- TargetShutterInputState · [ui-feel] testInactiveFineLiveTelemetryIgnoredAfterSwitchToQuick | stale Fine live emit after switch to Quick ignored
- TargetShutterInputState · [ui-feel] testClearedStateIgnoresLiveTelemetry | Off ignores live telemetry; readout shows preserved draft
- TargetShutterInputState · [ui-feel] testModeSwitchMidSpinFlushesLiveValueIntoDraft | mid-spin mode switch flushes live value into draft (900→Fine 15m)
- TargetShutterInputState · [ui-feel] testCommitLiveIntoDraftUsesLiveValue | Confirm-time flush commits in-progress live value (195)
- TargetShutterInputState · [ui-feel] testConcurrentFineWheelsComposeFromLiveValues | concurrent Fine wheels compose from live other-column values (no revert to settled)

## F — Presentation / snapshot / shell (~120 tests)

**[verdict]** Two behavior-relevant areas are ✅ **already-covered** in
Android `core`: region/basis policy (`GuardedFormulaRegionBasisContractTests`
→ `ReciprocityCalculationPolicyEvaluator`) and representative-timer / lock-screen
**selection** (`CalculatorTimerLockScreenTests` kit copy →
`RepresentativeTimerSelector`). The remaining behavior-relevant
presentation contracts (Details Source-reference/Guidance-boundary section
split, secondary-guidance formatter, stop-signal/not-recommended vocabulary,
source-reference row sorting, display-state snapshot harness) are
🟡 **partial / follow-up** — Android `DetailsPresenter` is a reduced flat-row
model with no graph. All `*Graph*`, dock/shell/theme/layout-metric, ActivityKit,
and RecordReplay suites are **ios-only / deferred-presentation**.

Classification (iOS file | #tests | class | why | Android equivalent):




#### Snapshots / App / Components / Theme (PTimerKitTests):

DisplayStateSnapshotTests | 7 | behavior-relevant | Locks serialized form of policy results, confidence presentation, and the full preset-film catalog shape — guards numeric/structural drift, not visuals. | partial (Android has policy evaluator + confidence mapper + catalog loader with their own tests, but no snapshot harness)

BottomSheetWorkspaceCompactPresentationTests | 12 | deferred-presentation(layout/vocab) | Compact-dock card geometry constants plus relative-time/"Done"/"Paused" copy and large-card title-suppression — iOS dock surface. | no (Android has no compact-dock presenter; only TimerWorkspaceController ordering)

BottomSheetWorkspaceCompactProgressTests | 5 | deferred-presentation(graph) | Multi-layer compact progress-ring fraction/layer-selection policy — a numeric computation but purely for the iOS layered ring widget. | no

ResultValueRowTests | 2 | ios-only-UI | SwiftUI ResultRowLayout/Value config + Equatable for a reusable row component. | no

TimerActionMetricsTests | 2 | ios-only-UI | SwiftUI button metrics/style value type. | no

PTimerComponentThemeTests | 4 | ios-only-UI | SwiftUI color-token theme + graph palette; reproduces shipping SwiftUI colors. | partial (Android has ui/theme/Color.kt etc., untested)


#### Reciprocity presentation (PTimerKitTests):

FilmModeDetailsGraphPresenterTests | ~13 | deferred-presentation(graph) | Pins graph presenter IO: kind, current-point style, markers, beyond-source/no-recommended boundaries, formula display text — all for the deferred iOS graph. | no (graph deferred on Android)

FormulaGraphVisibilityTests | ~14 | deferred-presentation(graph) | Graph viewport/no-correction-band/identity-segment/current-marker visibility; one test also asserts corrected-exposure card + play-button basis (behavior) but the file is graph-dominant. | no

FormulaGraphScalePolicyTests | ~11 | deferred-presentation(graph) | Graph axis tier selection, viewport bounds, axis tick labels — pure iOS graph scaling policy. | no

FilmDetailsGraphKindInvariantTests | ~4 | deferred-presentation(graph) | Catalog-wide invariant that each film yields a formula graph or none, plus identity-segment sampling — graph-shape contract. | no

ConvertedFormulaDetailsPresentationTests | ~18 | behavior-relevant | Asserts Details section split (Source reference / Guidance boundary / Sources), status text ("No correction"/"Formula-derived"/"Beyond source range"), badge alignment, ≈ de-duplication — vocabulary + section-structure contract; some graph sub-checks. | partial (Android Details has flat rows + corrected label, no section split / status-vocabulary)

GuardedFormulaPresentationContractTests | 5 | behavior-relevant | Table-driven Source-reference/Guidance-boundary split tokens, beyond-source wording gate ("source range" not "extrapolated"), play-button enablement for unsupported-numeric. | partial

GuardedFormulaRegionBasisContractTests | 4 | behavior-relevant | Pure policy: classifies basis (threshold/formulaDerived/unsupportedOutOfPolicyRange) and exact corrected continuation values per region. No UI. | yes (Android ReciprocityCalculationPolicyEvaluator + ReciprocityCoreTest cover region/basis)

NotRecommendedBoundaryPresentationTests | ~9 | behavior-relevant | Stop-signal classifier firing at boundary + vocabulary presenter leading info/detail text with verbatim manufacturer warning; single-message/scope gates. | no (Android has no stop-signal classifier/vocabulary presenter)

ReciprocitySecondaryGuidancePresentationTests | 7 | behavior-relevant | Secondary-guidance formatter: maps color/development/warning/note adjustments to kind/severity/verbatim value, preserves order, invents no numeric value. Pure value transform. | no

ReciprocitySecondaryGuidanceCatalogMappingTests | 1 | behavior-relevant | Wires real catalog adjustments through the same formatter; forbids inventing color rows, requires stop warning. Data-integrity + formatter contract. | no

SourceReferenceRowSortingTests | ~7 | behavior-relevant | Source-reference row sort-ordering logic (sortValue→kind→catalogOffset) plus through-presenter row order and boundary-exclusion. Ordering logic, not visuals. | no


#### ExposureCalculator viewmodel / boundary (PTimerKitTests):

ExposureCalculatorViewModelFilmDetailsTests | (read header) | behavior-relevant | Drives the iOS view model: corrected-exposure numbers, badge/tone, can-start-timer flags, details section/value text — number + state contract. | partial (Android ShootingViewModel/CalculatorController compute results but no Details display-state assertions)

ExposureCalculatorViewModelFilmGraphTests | (header) | deferred-presentation(graph) + some behavior | Graph source-point span/stability for view model, but also asserts sub-second no-correction basis and corrected==adjusted guard (behavior). Mixed; graph-framed. | partial (basis guard exists in core; graph spans do not)

FilmModeDetailsSecondaryGuidancePresenterTests | (header) | behavior-relevant | View-model-level Source-reference/Guidance-boundary layout with per-entry color-note pairing and stop-row exclusion — section structure + vocabulary. | partial

CalculatorTimerLockScreenTests (PTimerKitTests) | (multiple) | behavior-relevant | LockScreen target selection: representative timer + scheduled targets from earliest end date. Selection logic, not visual. | yes (Android core RepresentativeTimerSelector + RepresentativeTimerSelectorTest)

ExposureCalculatorViewModelScenePhaseTests | (multiple) | behavior-relevant | App-becomes-active timer reconciliation publishes updated running/completed state. Runtime/state behavior. | partial (Android TimerWorkspaceController/TimerRuntime reconcile, OS-boundary differs)


#### App-hosted (ios/PTimerTests):

App/CalculatorTimerLockScreenTests (PTimerTests) | 1 | ios-only-UI | Only the ActivityKit Live Activity ContentState hand-off (`displayTarget(at:)`); OS-boundary. Selection logic itself lives in the kit copy. | no (no ActivityKit; selection in core)

App/BottomSheetWorkspaceLayoutMetricsTests | (several) | ios-only-UI | Screen-level layout-height budget tiers (compact/regular/dense) for iPhone — pure layout sizing. | no

App/BottomSheetWorkspaceShellTests | (several) | ios-only-UI | App-delegate portrait orientation + BottomSheetWorkspaceStateStore expand/collapse/detent — SwiftUI shell + OS. | no (Android has its own Compose shell)

App/BottomSheetWorkspaceShellTestSupport | 0 | ios-only-UI | Test support helpers for the shell suite (no tests). | no

RecordReplay/RecordReplayBaselineSmokeTests | 1 | behavior-relevant | End-to-end timer start→complete event-trace baseline against spied deps; protects runtime call sequence. | no (no record-replay harness on Android)

RecordReplay/RecordReplayBaseline, RecordReplayHarness, RecordReplaySpies, RecordReplayTrace | 0 each | ios-only-UI (infra) | Record-replay harness/spies/trace/baseline infrastructure, no tests of their own. | no

App/BottomSheetWorkspaceShellTestSupport (PTimerKitTests, `Snapshots`-adjacent) | 0 | n/a-support | Shared snapshot/dock test fixtures (`makeBottomSheetSnapshot`, sample timers) — support only. | no

Snapshots/DisplayStateSnapshot | 0 | n/a-support | Snapshot assertion harness (golden-file infra), no tests. | no



**Flagged behavior-relevant** (protect non-visual logic):
DisplayStateSnapshotTests, ConvertedFormulaDetailsPresentationTests,
GuardedFormulaPresentationContractTests, GuardedFormulaRegionBasisContractTests,
NotRecommendedBoundaryPresentationTests, ReciprocitySecondaryGuidancePresentationTests,
ReciprocitySecondaryGuidanceCatalogMappingTests, SourceReferenceRowSortingTests,
ExposureCalculatorViewModelFilmDetailsTests, FilmModeDetailsSecondaryGuidancePresenterTests,
CalculatorTimerLockScreenTests (kit), ExposureCalculatorViewModelScenePhaseTests,
RecordReplayBaselineSmokeTests. Of these, region/basis policy and lock-screen
selection are covered in Android `core`; the rest are **follow-up** (reduced
Details model) or **ios-only**.
