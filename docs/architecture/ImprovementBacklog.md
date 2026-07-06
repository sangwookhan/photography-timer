<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PTimer — Code, API, and Architecture Improvement Backlog

**Type**: Assessment of current quality debt — app-target code,
PTimerKit/PTimerCore API surface, and cross-cutting structure — with
improvement directions. Not a behavior contract and not a task spec.
**Audience**: The maintainer triaging which investments to turn into
tickets, and any agent asked to evaluate or plan one of them.
**Direction of influence**: This document follows
`docs/architecture/Architecture.md` (current structure) and the
PTIMER-174/177 outcomes. Each item below is a candidate ticket; none
is authorized work by itself. When an item ships, remove it here and
update `Architecture.md` instead.

Snapshot date: 2026-06-11, evaluated against the PTIMER-174 PR #6
branch (app target 25 files; PTimerKit 71 + PTimerCore 17 source
files; tests 129 app-hosted / 1069 package).

**Status refresh: 2026-07-06.** Items re-checked against current
`main` (app target 30 files; PTimerKit 78 + PTimerCore 20 source
files; tests 120 app-hosted / 1,355 package). Item 4.3 has shipped
and is marked completed below; file-size evidence in items 2.1, 3.1,
3.3, and 3.4 is updated to current measurements (every cited file has
grown since the snapshot); the RecordReplay note in §5 is revised.
The cross-platform review
([`CrossPlatformArchitectureReview.md`](CrossPlatformArchitectureReview.md),
Appendix B) tracks a complementary set of items — defects and
platform-glue gaps — that this backlog deliberately does not cover;
consult both when ticketing.

---

## 1. What is working — preserve, do not regress

These properties were verified by measurement and are the foundation
the items below must not break.

- **Compiler-enforced layering.** PTimerCore imports Foundation only
  (17/17 files). PTimerKit imports Foundation / Combine / SwiftUI /
  Observation / PTimerCore only — zero UIKit. Because the package
  declares macOS, `swift test` doubles as a layer-boundary gate: UIKit
  creep into Kit fails the build immediately.
- **Thin app shell with clean adapters.** The app target is 25 files:
  SwiftUI views, four small UserDefaults stores (38–53 lines),
  `TimerManager` as a 199-line RunLoop/OS coordinator, notification +
  Live Activity adapters (19–93 lines), and a 43-line
  `ViewModelDependencyFactory` with `production()` / `test()` pairs in
  which every dependency crosses a protocol seam. Domain-symbol grep
  over the views found zero business-logic leakage.
- **Restrained public API with high doc density.** Core exposes 84
  public declarations, Kit 147 (~2 per file). Core carries 863 `///`
  lines and cross-references the specs (e.g. `TimerState` cites Timer
  Spec §3.1 and documents its trusted-callsite contract); Kit carries
  3,332 `///` lines.
- **Published-state discipline at the facade.** The view-model facade
  exposes exactly four mutable `@Published public var` properties —
  all user inputs that need two-way bindings (`baseShutter`, `ndStop`,
  `ndStep`, `scaleMode`); outputs are `private(set)`.
- **Naming conventions hold in practice.** Measured: `*Storing` 5,
  `NoOp*` 8, `*DisplayState` 7, `*Coordinator` 3, `*Presenter` 16,
  `Persistent*` 8, `*Factory` 1 — matching the documented conventions.
- **Off-simulator test majority.** 89% of tests run via `swift test`
  (warm loop ≈ 3.5 s end-to-end); the app-hosted remainder is a
  deliberate OS-boundary list, each residual file carrying a doc
  comment stating why it stays.

---

## 2. App-target code problems

### 2.1 View files are oversized

- **Evidence** (re-measured 2026-07-06): five files over 500 lines —
  `CustomFilmEditorView` 1,623 (was 1,022 at snapshot),
  `BottomSheetWorkspaceShell` 1,273 (was 1,011),
  `ExposureCalculatorScreen` 1,184 (was 959),
  `ExposureWorkspaceMainLayoutStyle` 808 (was 712),
  `FilmModeDetailsView` 586 (unchanged). Logic-clean (verified by
  domain-symbol grep), but UI iteration pays a growing diff/review
  cost, and these files dominate merge-conflict probability for any
  screen-level change.
- **Direction**: Continue the PTIMER-155-style decomposition: extract
  leaf subviews per the module-prefix convention
  (`BottomSheetWorkspace*` pattern). No behavior change; views remain
  render-only. One screen per ticket, opportunistically — not one big
  pass.
- **Effort/risk**: Medium / Low.

### 2.2 View-layer helpers hold testable logic in view files

- **Evidence**: `rowDurationDisplayValue(...)` (a pure formatting
  free function) lives in `CustomFilmEditorView.swift`, and the
  `customFilmEditorCommonISOs` constant lives in
  `CustomFilmEditorFieldSheets.swift`. Both are pure values with their
  own tests, and they are the only reason
  `CustomFilmEditorPolishTests` keeps a 2-test app-hosted residual.
- **Direction**: Relocate both into PTimerKit `CustomFilm/` (pure
  formatting helper + constant; call sites unchanged). Unlocks the
  residual tests moving off-simulator as a side effect.
- **Effort/risk**: Trivial / Low. File-move discipline applies
  (task-level approval per AGENTS.md).

---

## 3. Kit / Core API problems

### 3.1 `ExposureCalculatorViewModel` facade is the codebase's gravity well

- **Evidence** (re-measured 2026-07-06): 1,758 lines (was 1,671 at
  snapshot; still growing) plus `+CustomFilm` extension (99). As an
  API it exposes the union
  of four domains' published surfaces in one type; as code, every
  feature change routes through it, making it the single biggest
  source of review load and merge conflicts.
- **Direction**: Complete the in-progress four-model decomposition
  (`CalculatorModel`, `ReciprocityModel`, `FilmSelectionModel`,
  `TimerWorkspaceModel` already exist). Target shape: the facade keeps
  only published-surface composition and cross-model orchestration;
  per-domain behavior, derived state, and formatting delegation live
  in the models. Success criterion: facade well under half its current
  size with no public API change for views.
- **Safety net already in place**: `ViewModelDisplayStateBaselineTests`
  and the RecordReplay traces were built exactly to fence this
  refactor ("byte-identical user-visible state for the same input").
- **Effort/risk**: Large / Medium. Highest ROI item in this list.

### 3.2 Two observation paradigms coexist without a stated rule

- **Evidence**: the facade publishes via Combine (`@Published` /
  `ObservableObject`); the newer internal models use Observation
  (`@Observable`: `CalculatorModel`, `ReciprocityModel`,
  `TargetShutterModel`). Both work, but nothing tells a contributor
  which to use for new state.
- **Direction**: Decide and document one target (likely: Observation
  for models, Combine only at the facade edge while views still
  consume `@Published`; or full Observation migration as part of 3.1).
  One paragraph in `Architecture.md` is the minimum deliverable even
  if no code changes.
- **Effort/risk**: Small (decision + doc) to Medium (migration) / Low.

### 3.3 `CustomFilmEditorFormState` carries four responsibilities

- **Evidence** (re-measured 2026-07-06): 1,521 lines (was 1,334 at
  snapshot) in one Kit type: form field state, validation, display
  formatting, and formula-expression tokenizing.
- **Direction**: Split along existing seams — the tokenizer and the
  formula presentation formatting are already tested as separable
  units (`CustomFilmEditorFormulaPresentationTests`). Extract those
  into focused types; keep `FormState` as field state + validation.
- **Effort/risk**: Medium / Low (pure-value code, well covered).

### 3.4 Core domain monolith files

- **Evidence** (re-measured 2026-07-06): `ReciprocityDomain.swift`
  1,401 lines and `ReciprocityCalculationPolicy.swift` 1,185 lines.
  Cohesive and
  protected, but any vocabulary addition lands in one of two huge
  files.
- **Direction**: File-level split only (one type-cluster per file:
  profiles / rules / provenance / evaluation), zero semantic change.
  Protected Area applies to behavior, not file layout, but the split
  still deserves its own ticket with the policy regression suite as
  the gate.
- **Effort/risk**: Small / Low-Medium (touches protected code paths;
  mechanical but must be reviewed as such).

### 3.5 `TimerState` legacy compatibility initializer is transitional API

- **Evidence**: the sum-type `TimerState` keeps a 7-argument
  compatibility initializer mirroring the historical struct shape,
  with a documented trusted-callsite contract and debug-trap /
  release-fallback behavior for corrupt inputs. It exists for the
  persistence restore path and pre-migration test callers.
- **Direction**: Once remaining callers construct cases directly
  (`.running(RunningTimer(...))` etc.), narrow the compatibility
  initializer to the persistence boundary (or make it internal to the
  restore path). Pure API cleanup; semantics unchanged.
- **Effort/risk**: Small / Low. Low priority; do alongside other
  timer work, not alone.

### 3.6 Kit bundles two module responsibilities

- **Evidence**: PTimerKit is both the app-logic layer (models,
  presenters, persistence contracts) and a SwiftUI component kit
  (9 files import SwiftUI: theme, graph view, target-shutter sheet,
  reusable components).
- **Direction**: Acceptable at current size. If the component surface
  keeps growing, split a `PTimerUI` library target (PTimerCore ←
  PTimerKit ← PTimerUI ← app) so logic consumers never link SwiftUI.
  Trigger to act: the component kit needing its own conventions/theme
  evolution, or Kit compile time becoming noticeable in the
  `swift test` loop.
- **Effort/risk**: Medium / Low — mechanical target split when
  triggered.

---

## 4. Cross-cutting structure and test architecture

### 4.1 Timer runtime semantics are covered only through the app wrapper

- **Evidence**: `TimerRuntime` (Kit) owns the protected state-machine
  semantics, but its 64 covering tests live app-hosted with the thin
  `TimerManager` wrapper as the subject. Kit has zero direct
  `TimerRuntime` tests. Coverage is currently correct because the
  wrapper delegates 1:1 — but the protected area's tests depend on a
  target that is not its owner.
- **Direction**: As a follow-up to PTIMER-177 (shipped), either
  (a) re-home the runtime-semantics suites to Kit against
  `TimerRuntime` and keep a small app-hosted suite for the RunLoop
  ticking loop and UIKit alert service, or (b) move `TimerManager`
  itself into Kit after splitting its UIKit companions
  (`SystemTimerCompletionFeedbackPlayer`,
  `ForegroundTimerCompletionAlertService` stay app-side). Option (b)
  also finishes the Reusable Kit Architecture intent. The 2026-07-06
  cross-platform review quantified the same overlap from the test
  side: ~52 app-hosted methods re-prove `TimerState` math
  (`CrossPlatformArchitectureReview.md` §16.1).
- **Constraint**: Protected Area — requires its own explicit ticket;
  do not fold into unrelated work.
- **Effort/risk**: Medium / Medium.

### 4.2 Test-support duplication across targets

- **Evidence**: the `private` in-file fake-store pattern
  (`InMemory*Store`) is duplicated per file by design, and after the
  PTIMER-174 splits some helpers exist in both the app residual file
  and the Kit file. `FilmModeTestSupport` exists in both test targets.
  A protocol signature change now fans out to N hand-written fakes.
- **Direction**: Tolerate at current scale. If fan-out cost shows up
  in practice, promote the recurring fakes into a shared test-support
  module (SPM test utilities target consumed by both PTimerKitTests
  and, via the project, PTimerTests). Do not promote prematurely —
  file-scoped `private` fakes are also what keeps tests independent.
- **Effort/risk**: Small / Low.

### 4.3 Conventions that exist only in PR history — COMPLETED

Completed as of the 2026-07-06 status refresh: both rules (test
placement per owning module; the `FakeTimerManaging` /
`RuntimeBackedTimerManaging` boundary) are now stated in `AGENTS.md`
(Build and Test Commands → test placement rule) and reflected in
`Architecture.md` §5. Retained here as a record; no ticket needed.

---

## 5. Accepted decisions (recorded to prevent re-litigation)

- **`PresentationSemantics` lives in PTimerCore.** Unusual placement
  for presentation mapping, but deliberate: it is pure value mapping,
  a protected contract (`ReciprocityConfidencePresentation`), and has
  no UI dependency. Leave it.
- **`TimerManaging` stays minimal.** The protocol deliberately omits
  `tick(now:)`; deterministic tick driving is a test-support concern
  (`RuntimeBackedTimerManaging`), not an app-facing API. Do not widen
  the protocol for tests.
- **macOS in `Package.swift` is a test/fitness platform, not a product
  target.** It exists so package tests run off-simulator and so the
  compiler polices the Kit layer. Do not remove it; do not start
  treating macOS as a supported product platform because of it.
- **RecordReplay status revised (2026-07-06).** The original decision
  recorded here — "RecordReplay and the display-state baselines are
  the insurance for facade/timer refactors, protected regardless of
  suite-size pressure" — no longer holds for RecordReplay as-is: its
  7 baselines have not been re-recorded since 2026-05-17 while the
  harness kept changing, and its replays duplicate the assertion-based
  lifecycle suites through injected spies
  (`CrossPlatformArchitectureReview.md` §16.2). Before item 3.1 or 4.1
  starts, make an explicit decision: **re-record and own it** (restore
  its insurance role) **or retire it** and rely on the display-state
  baselines plus the assertion suites. The display-state baselines
  remain protected insurance either way.

---

## 6. Suggested ticket grouping

| Candidate ticket | Items | Why grouped |
| ---------------- | ----- | ----------- |
| Facade decomposition | 3.1 + 3.2 | The paradigm decision is cheapest made while the facade is being taken apart; requires the §5 RecordReplay decision first |
| Custom-film form split | 3.3 + 2.2 | Same feature area; 2.2 also clears a test residual |
| View decomposition (per screen) | 2.1 | One screen per ticket, opportunistic; `CustomFilmEditorView` first (fastest-growing) |
| Timer architecture completion | 4.1 + 3.5 | Protected Area; follow-up to PTIMER-177 (shipped) |
| Deferred until triggered | 3.4, 3.6, 4.2 | Cheap to wait, cheap to do later |

(4.3 completed 2026-07-06; removed from the grouping.)

---

## 7. Staged follow-up plan from the 2026-07-06 cross-platform review

This section records the agreed ticketing plan for the findings in
[`CrossPlatformArchitectureReview.md`](CrossPlatformArchitectureReview.md)
(Appendix B holds the finding-level REQ/POS classification). The
tickets below are **planned but not yet created**; this section is the
source a future agent uses to create them.

Conventions for these tickets:

- **Granularity**: one ticket = one problem resolved to one verifiable
  outcome. Investigation, implementation, and verification for the
  same problem stay in one ticket (multi-step reviewable commits, not
  multiple tickets). A ticket is split only if execution proves the
  outcome genuinely divisible.
- **Description format**: the ticket description states the Problem
  and the Outcome (acceptance) precisely; implementation methods are
  recorded only as non-binding candidate approaches. Direction changes
  during execution update the approach, not the ticket set.
- **Issue types**: tickets that change code or tests are Stories
  (defect fixes stay Bugs); tickets whose outcome is documentation or
  a recorded decision are Tasks. A decision ticket stays a Task even
  when its execution regenerates test artifacts; reclassify only if
  the decided outcome produces an actual code diff.
- **Epics**: no new epics for Stage 1 — Android tickets attach to
  PTIMER-144, the rest stand alone. Revisit epic structure when
  Stage 3 begins.
- References cite review sections; do not copy stale numbers into
  tickets — re-verify counts at pickup.

### Stage 1 — Problem resolution (start now; data/alarm items target the first store releases)

**S1-1. Restore the green fast loop and remove dead test artifacts**
(bug) — *Problem*: the package suite fails 4 display-state snapshot
tests on `main` (baselines embed catalog provenance URLs, so a
data-only link fix invalidated them); two orphaned duplicate
test-support files and a stub test remain. *Outcome*: `swift test`
green on `main`; a pure catalog-data edit no longer invalidates
display-state baselines; the dead files are gone. *Candidates*:
re-record with `SNAPSHOT_RECORD=1`; exclude provenance URLs from the
serialized display state; delete the files listed in review §16.1.
(Review §5, §16.1–16.2; REQ-1, REQ-10.)

**S1-2. Decide RecordReplay disposition** (task — the deliverable is
the decision; reclassify if the outcome produces a code diff) —
*Problem*: the 7
RecordReplay baselines have not been re-recorded since 2026-05-17
while the harness kept changing; replays duplicate assertion suites
through injected spies; §5 above makes this decision a prerequisite
for facade decomposition. *Outcome*: a recorded decision (re-record
and own, or retire) executed in the same ticket; §5 above updated.
(Review §16.2.)

**S1-3. Decide the launch-catalog primary-profile policy and
reconcile DomainSchema §13** (task) — *Problem*: DomainSchema §13
states every shipped primary profile is official, but the shipped
catalog carries one unofficial primary (`rollei-retro-400s`); the
film count (34 vs 40) and the §13.2 exclusion list also contradict
the shipped set. *Outcome*: the policy decision is recorded (accept
and document an unofficial-primary class, or reclassify the profile)
and §13/§13.1/§13.2 match the shipped catalog. (Review §6.3; REQ-4.)

**S1-4. Make persisted user data survive schema evolution** (story;
touches protected persistence/restore contracts — explicit
authorization required in the ticket) — *Problem*: one persisted
custom film containing an unknown enum value or rule kind makes both
platforms drop the entire custom library, and the next save destroys
the original payload; version gating is inconsistent (iOS custom-film
load ignores `schemaVersion`, iOS timer schemas carry none, Android
rejects unknown versions); decode failures are silent. *Outcome*: a
payload written by a newer schema degrades the affected record only,
never a whole collection; version gating is consistent across
platforms and schemas; decode failure is observable and the raw
payload is preserved; all existing payloads decode to identical
domain values (regression-gated). *Candidates*: unknown-fallback
enum decoders / `coerceInputValues`; the per-record `mapNotNull`
pattern already used by the Android workspace codec; a quarantine
side key with a restore signal. (Review §12.2–12.3; REQ-2.)

**S1-5. Verify the Android OS-glue contracts** (story, PTIMER-144) —
*Problem*: the layer between the tested alert plan/policy and the OS
is untested — `AndroidTimerAlertCoordinator.sync()` AlarmManager
reconciliation (schedule/cancel/reschedule, stale pre-alert drop,
exact→inexact fallback, foreground-service transitions), the concrete
`TimerAlarmPlayer`, the Timer-spec §6 display-ordering contract, and
the four `DataStore*Store` adapters (corrupt-blob fail-safe). The
coordinator has no test seam (direct `AlarmManager` +
`System.currentTimeMillis()`), and `ShootingViewModel` carries
`android.content.Context` in the alarm-player signature. *Outcome*:
these contracts are pinned by JVM tests; the coordinator has an
injectable seam; the VM band is `Context`-free. (Review §16.3, §8 B2;
REQ-9, POS-5, POS-18-part.)

**S1-6. Remove Android main-thread blocking at startup and timer
completion** (story, PTIMER-144) — *Problem*: first composition parses
the 84 KB catalog and performs three `runBlocking` DataStore reads on
the main thread; timer completion performs a `runBlocking` workspace
write on the main thread. *Outcome*: no `runBlocking` on the main
thread; startup I/O loads off-main behind the existing splash;
completion persists off-main. (Review §11.2 #3–4; REQ-7.)

**S1-7. Fix Android MVP usability defects** (story, PTIMER-144) —
*Problem*: primary timer actions are 34 dp and ND segments ~26–30 dp
(below the 48 dp guideline); the custom-film editor draft and dialog
state are lost on configuration change; several visible strings and
contentDescriptions are hard-coded English with a non-locale
timestamp format. *Outcome*: 48 dp interactive targets; the editor
draft survives configuration change and process death; all
user-visible strings localize. (Review §13.1–13.2, §13.7; REQ-5/6/8.)

### Stage 2 — Parity contract (gate: before resuming calculation-band work — the ND feature backlog or the next catalog wave)

**S2-1. Establish the shared calculation golden contract and fix the
divergences it exposes** (story) — *Problem*: shared fixtures pin
only exposure calculation and catalog shape; reciprocity policy
outputs, table interpolation, custom-film fitting, and target-shutter
differences have no cross-platform oracle — and one live numeric
divergence is already known (Android thirds rounding is half-even
where iOS is half-away-from-zero). *Outcome*: golden fixtures under
`shared/test-fixtures/` for those surfaces, consumed by both suites;
known divergences fixed (rounding) or recorded as accepted in the UI
spec (ASCII fraction rendering). If calculation-band work resumes
earlier than expected, this ticket moves ahead of it. (Review §10.1,
§10.3; REQ-3, POS-1.)

### Stage 3 — Target structure (gate: store releases shipped and the feature surface stabilized; create tickets at pickup, not in advance)

Candidates, in rough order, with their standing evidence:

1. Facade decomposition (§3.1 + §3.2 above; S1-2 is its
   prerequisite).
2. Custom-film form split (§3.3 + §2.2 above).
3. Per-screen view decomposition (§2.1 above; `CustomFilmEditorView`
   first).
4. iOS `UserDefaults*Store` move into PTimerKit, or a recorded
   rejection (review §8 B1).
5. Timer architecture completion: `TimerManager` into Kit and
   re-homing the ~52 app-hosted state-machine tests (§4.1 + §3.5
   above; protected area).
6. Android `:kit` extraction once its trigger fires (review §8 B3 —
   `:app` test slowdown or a second Android surface).
7. `PTimerUI` target split once its trigger fires (§3.6 above).
8. Versioned custom-profile interchange envelope (review §12.3 item
   5; feeds PTIMER-195), then the shared-core experiments
   (PTIMER-196/197) scoped to one rule set with the Stage 2 goldens
   as the safety net.
9. Android display-state snapshot layer and first Compose UI tests
   (review §8 C3, §16.3).
10. Android theme/haptics/predictive-back polish (review §13.3–13.6).
11. iOS package-suite trim — catalog static-data assertions to
    `verify.py`, snapshot-overlap merge (review §16.1; POS-15).
