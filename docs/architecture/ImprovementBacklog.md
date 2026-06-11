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

- **Evidence**: five files over 500 lines —
  `CustomFilmEditorView` 1,022, `BottomSheetWorkspaceShell` 1,011,
  `ExposureCalculatorScreen` 959, `ExposureWorkspaceMainLayoutStyle`
  712, `FilmModeDetailsView` 586. Logic-clean (verified by
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

- **Evidence**: 1,671 lines — the largest file in the repository —
  plus `+CustomFilm` extension (120). As an API it exposes the union
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

- **Evidence**: 1,334 lines in one Kit type: form field state,
  validation, display formatting, and formula-expression tokenizing.
- **Direction**: Split along existing seams — the tokenizer and the
  formula presentation formatting are already tested as separable
  units (`CustomFilmEditorFormulaPresentationTests`). Extract those
  into focused types; keep `FormState` as field state + validation.
- **Effort/risk**: Medium / Low (pure-value code, well covered).

### 3.4 Core domain monolith files

- **Evidence**: `ReciprocityDomain.swift` 1,349 lines and
  `ReciprocityCalculationPolicy.swift` 1,182 lines. Cohesive and
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
- **Direction**: When PTIMER-177 resumes, either (a) re-home the
  runtime-semantics suites to Kit against `TimerRuntime` and keep a
  small app-hosted suite for the RunLoop ticking loop and UIKit alert
  service, or (b) move `TimerManager` itself into Kit after splitting
  its UIKit companions (`SystemTimerCompletionFeedbackPlayer`,
  `ForegroundTimerCompletionAlertService` stay app-side). Option (b)
  also finishes the Reusable Kit Architecture intent.
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

### 4.3 Conventions that exist only in PR history

- **Evidence**: two rules introduced during PTIMER-174 are enforced
  only by doc comments and reviewer memory:
  1. *Test placement*: a test lives in the module that owns its
     subject; app-hosted is reserved for OS-boundary behavior
     (RunLoop coordinator, ActivityKit, `UIApplication`, concrete
     UserDefaults stores, SwiftUI shell, RecordReplay).
  2. *Timer fake boundary*: `FakeTimerManaging` records starts but
     must never gain time-advance or state-transition behavior;
     anything needing transitions uses `RuntimeBackedTimerManaging`
     (real `TimerRuntime`).
- **Direction**: Add one short section to `Architecture.md` (or
  `docs/verification/Strategy.md`) stating both rules. Documentation
  only.
- **Effort/risk**: Trivial / None.

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
- **RecordReplay and the display-state baselines are the insurance for
  facade/timer refactors** (items 3.1 and 4.1 depend on them). They
  stay protected regardless of test-suite size pressure.

---

## 6. Suggested ticket grouping

| Candidate ticket | Items | Why grouped |
| ---------------- | ----- | ----------- |
| Convention write-down | 4.3 | Trivial docs-only, do first |
| Facade decomposition | 3.1 + 3.2 | The paradigm decision is cheapest made while the facade is being taken apart |
| Custom-film form split | 3.3 + 2.2 | Same feature area; 2.2 also clears a test residual |
| View decomposition (per screen) | 2.1 | One screen per ticket, opportunistic |
| Timer architecture completion | 4.1 + 3.5 | Protected Area; resumes PTIMER-177 |
| Deferred until triggered | 3.4, 3.6, 4.2 | Cheap to wait, cheap to do later |
