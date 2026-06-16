# PTIMER-146 — Android MVP, Round 3 Readiness Review

> **Status:** Implementation-gate review only. Evaluates the accepted Round 2
> baseline (`docs/tasks/PTIMER-146-round2-accepted.md`) and decides whether
> implementation may begin. Not implementation. No production source changed
> (this document only), no commits, no Jira, no tickets. This document does not
> re-plan; it reviews.

---

## 0. Verification performed this round

Read-only checks against current source (worktree `PTIMER-146-android-mvp`):
- Git base: `HEAD == origin/main == 0078b80` ("Create an editable custom formula
  from a saved custom table (#14)"); `origin/main..HEAD` and `HEAD..origin/main`
  both empty; working tree clean except `docs/tasks/`.
- Custom-profile follow-up present: `CustomFilmReferenceTableResolver.swift`
  exists at HEAD; `referenceTableFilmID` is an additive optional on
  `UserEditableMetadata` (decode-if-present).
- No PTIMER-188 behavior committed; `startAgain` symbols trace to the
  pre-existing PTIMER-36 "start a new timer from a completed exposure" (commit
  `5edda86`), not PTIMER-188.
- Catalog shape distribution: 37 films = 20 formula + 11 tableInterpolation + 6
  threshold+limitedGuidance.
- Android side remains the placeholder Compose skeleton (no product behavior).

---

## 1. Owner decisions — closed

### Q1 — Base alignment → **ACCEPTED**
PTIMER-146 targets `origin/main` at `0078b80`. Verified: `HEAD == origin/main`;
the base **includes** PTIMER-165 (custom table input + inspection-only fitted
preview, #13) and PTIMER-180 (Create-Formula-from-table + `referenceTableFilmID`
+ resolver, #14), and **excludes** PTIMER-188 (no 188 commit; the `startAgain`
code is pre-existing PTIMER-36). The base is clean; no correction needed. (The
parent repository directory is checked out on a branch named
`feature/PTIMER-188-...`, but the PTIMER-146 worktree is on its own branch at
`origin/main` and carries no 188 changes.)

### Q2 — Catalog shape validation → **ACCEPTED**
Android validates against the catalog's **three actual profile shapes**:
`formula`, `tableInterpolation`, `threshold + limitedGuidance`. Android does
**not** enforce the fixture's two-shape `rule-11`, because the older fixture text
(`rule-11` two-shape restriction and `perFilmExpectations` without
`tableInterpolation` entries) **does not match the current catalog**, which
contains 11 table films. Android runs the self-consistent fixture rules (count,
manufacturer counts, ids/order, formula per-film params, threshold ranges,
rejection cases, vocabulary `rule-12`). Reconciling the iOS fixture/document is a
separate iOS-side concern, **out of PTIMER-146**.

### Q3 — Notification action buttons → **ACCEPTED (conditional on actions only)**
Completion notification and the ongoing running-timer notification are
**included**. Pause/Resume **action buttons** are included **only if low-risk**;
if they complicate the foreground-service/intent architecture, defer the action
buttons — **never** the notification feature itself. The notification feature is
not gated on the buttons.

### Q4 — Persistence consolidation → **ACCEPTED**
Android greenfield consolidation accepted: (a) timer runtime + display/identity
metadata in one timer-collection snapshot; (b) calculator context inside the
camera-slot session snapshot; (c) a separate custom-film library store. **No iOS
legacy migration is required** — current source does not impose any migration on
a fresh Android install (the iOS legacy single-context path is an
iOS-upgrade-only concern). All snapshots carry `schemaVersion = 1`; unknown/
future versions load as default; corrupt payloads fail safe to default.

---

## 2. Readiness check — Scope stability

The accepted Must scope is **stable** and each item maps to verified current iOS
behavior:

| Scope item | Stable? | Note |
|---|---|---|
| Exposure calculation; base ladder; ND `0..30`; formatting | ✅ | fixture-backed |
| Film catalog/profile loading | ✅ | 37 films, 3 shapes |
| Reciprocity formula / table / threshold / limited / unsupported | ✅ | table evaluator required (11 films) |
| Preset alternate-model selection | ✅ | `AlternateReciprocityModels` (preset-only) |
| Film select/clear; adjusted/corrected results; Start enablement | ✅ | limited/unsupported blocks corrected timer |
| Timer lifecycle; **Start Again** (completed clone); multiple + ordering | ✅ | PTIMER-36 clone present in source |
| Camera slots + rename; per-slot calc/film/target/selected-model; immutable identity | ✅ | identity incl. `selectedModelLabel` + custom descriptor |
| Target Shutter | ✅ | per-slot; nil when non-quantified |
| Custom formula profile; custom table profile; table anchors | ✅ | single rule formula XOR table |
| Fitted formula preview/generation **inspection-only** | ✅ | never the active calc — verified |
| Create-Formula-from-table; `referenceTableFilmID` | ✅ | separate linked formula film; resolver display-only |
| Custom-profile persistence/restore | ✅ | incl. `referenceTableFilmID` |
| Details source/model/calculation transparency | ✅ | model picker; custom rows; fitted comparison; linked reference/error |
| Android completion + running-timer notifications | ✅ | functional; OEM background guarantees deferred |
| Persistence/restore for all included state | ✅ | greenfield consolidation |
| Android parity tests | ✅ | see §4 |

No scope item is unstable. **No previously-deferred function reappeared as Must
without a basis in current source.**

---

## 3. Readiness check — Deferred scope sanity

All deferred items are genuine UI/UX polish or platform limits — **none is
product functionality**:

| Deferred item | Classification | Confirmed polish/limit? |
|---|---|---|
| Picker feel / wheel tuning | UI/UX polish | ✅ (function — picker entry — is included) |
| Details graph visual fidelity | UI/UX polish | ✅ (model/calc transparency included via rows/comparison) |
| Editor layout polish | UI/UX polish | ✅ (authoring + validation function included) |
| Bottom-sheet drag choreography, density tiers, slot-pager animation | UI/UX polish | ✅ (timer list + slots function included) |
| Home-screen widget visual design | Platform polish | ✅ (ongoing notification covers monitoring) |
| Guaranteed exact background delivery across Doze/OEM | Platform limit | ✅ (best-effort scheduling included; not fully controllable) |
| iOS ActivityKit/RecordReplay/layout metrics | iOS-only | ✅ (replaced functionally by Android notification plan) |
| Notification action buttons (if not low-risk) | Conditional polish | ✅ (notification feature itself included) |

**Flag:** none. The one item to watch is "ongoing running-timer notification" —
its *core function* (a live notification for the representative running timer) is
**included**; only exact background-delivery reliability under aggressive OEM
battery managers is deferred. That deferral is a real platform limit, not a
function cut.

---

## 4. Readiness check — Architecture readiness

| Architecture requirement | Ready? | Note |
|---|---|---|
| Pure-Kotlin `:core`, no Android dependency | ✅ | `kotlin.jvm` module; enforced by classpath |
| No version catalog for PTIMER-146 | ✅ | inline versions; revisit if modules grow |
| Minimal dependencies | ✅ | serialization (`:core`); coroutines, viewmodel-compose, datastore (`:app`) |
| `:app` owns ViewModel, Compose UI, DataStore, timer coordinator, notifications | ✅ | clear ownership |
| One-way UI event flow | ✅ | `onEvent(ShootingIntent)` → `StateFlow<ShootingUiState>` |
| Persistence behind interfaces | ✅ | `*Store` in `:core`; DataStore impls in `:app` |
| Timer tick owned by coordinator/runtime, not Composables | ✅ | `AndroidTimerCoordinator` drives `TimerRuntime.tick(now)` |
| Fitted formula + reference-table link remain display-only unless the user explicitly creates a separate formula profile | ✅ | matches verified iOS invariant; explicit "never active" test required |
| No iOS source changes required | ✅ | migration is additive under `android/` |

Architecture is **ready**. One explicit guardrail to carry into implementation:
the inspection-only invariant (fitted formula and `referenceTableFilmID` never
enter calculation) must be enforced and unit-tested, mirroring iOS.

---

## 5. Readiness check — Test readiness

For each group, behavior is clear enough to implement:

| Test group | Behavior clear? | Source of truth |
|---|---|---|
| Fixture-driven (exposure, catalog) | ✅ | `shared/test-fixtures/*` |
| Core parity (exposure, reciprocity, fitter, guard, resolver, table, timer) | ✅ | iOS behavior + fixtures |
| ViewModel (calc+film, Start enablement, alternate-model, lifecycle, identity, Start-Again) | ✅ | iOS ViewModel/timer tests as audit source |
| Persistence (timer/session/custom-film round-trip + restore + corrupt fail-safe) | ✅ | schemas defined; greenfield |
| Custom film (table form, fitted preview, create-formula, library CRUD, codable) | ✅ | iOS custom-film tests |
| Timer / notification (exactly-once, cancel-on-pause, representative selection) | ✅ | iOS notification/coordinator rules |
| Camera slot (independence, capture/restore, rename isolation) | ✅ | iOS slot tests |
| Target Shutter (comparison, match, nil, per-slot, lastUsed) | ✅ | iOS target tests |
| Details / presenter (rows, picker, fitted comparison, reference/error, vocab) | ✅ | iOS presenter tests |
| Compose UI smoke (render, start/pause/remove, slot switch, open picker/details) | ✅ | kept minimal |

**iOS tests are used as behavior-audit sources, not mechanically translated** —
restated and accepted.

**One test-readiness detail (non-blocking):** because the catalog fixture's
`perFilmExpectations` omits the 11 table films, per-film parity for those films
uses **anchor-derived goldens computed from the catalog JSON's own anchors**
(via the ported log-log math) rather than the shared fixture. This is explicit
in the plan and is implementable; it is logged so the implementer does not
expect those 11 films in `perFilmExpectations`.

---

## 6. Readiness check — Slice readiness

The accepted 10-slice order is **well-formed**: each slice has a clear goal,
testable result, test set, stop condition, and checkpoint, and no slice has a
hidden dependency on a later slice (dependencies flow forward only:
core → runtime → coordinator/VM → UI → custom/target/details/notifications).

**Two non-blocking sizing observations (recommended sub-splits, applied at
execution time — do not require another planning round):**

- **Slice 8 (custom film library + formula + table + fitted preview +
  Create-Formula-from-table + persistence + Details) is the largest.** Recommend
  executing it as three checkpoints that each end green:
  - 8a — custom film library + custom **formula** authoring + persistence/restore.
  - 8b — custom **table** authoring + log-log calc + inspection-only fitted preview.
  - 8c — Create-Formula-from-table + `referenceTableFilmID` + reference-table
    resolver/columns.
- **Slice 10 bundles two concerns (Details transparency + notifications).**
  Recommend two checkpoints:
  - 10a — Reciprocity Details functional transparency.
  - 10b — completion + ongoing running-timer notification (foreground service);
    action buttons only if low-risk.

These are review-granularity refinements, not reordering or scope changes. The
slice order is otherwise correct.

---

## 7. Implementation gate decision

**Ready for implementation**, with the two non-blocking slice sub-splits in §6
recommended as execution-time checkpoints (no further planning round required).

### First implementation slice
**Slice 1 — Gradle/module setup.**

- **Goal:** create the pure-Kotlin `:core` module and wire minimal dependencies;
  no product behavior yet.
- **Exact constraints for starting:**
  - Touch only `android/settings.gradle.kts`, `android/build.gradle.kts`,
    `android/app/build.gradle.kts`, and the new `android/core/build.gradle.kts`
    (+ a trivial `:core` smoke test).
  - **No** changes under `ios/`, `docs/specs/`, `shared/test-fixtures/`, or any
    production iOS source.
  - **No** version catalog; inline dependency versions.
  - `:core` is `org.jetbrains.kotlin.jvm` + serialization plugin only — **no
    Android dependency** on its classpath.
  - No commits unless explicitly instructed after this gate.
- **Stop condition:** `cd android && ./gradlew :core:test assembleDebug` green;
  app still launches the existing placeholder.
- **Checkpoint:** confirm `:core` classpath contains no `com.android.*` /
  `androidx.*` artifacts before proceeding to Slice 2.

---

## 8. Verification required before starting implementation

- Re-confirm at start that `HEAD == origin/main` and no unrelated PTIMER-188
  work has landed since this review.
- Confirm owner sign-off on Q1–Q4 as closed above (all ACCEPTED).
- Confirm the implementer treats the inspection-only invariant (fitted formula +
  `referenceTableFilmID` never enter calculation) as a hard guardrail.
- Confirm the catalog parity approach for the 11 table films (anchor-derived
  goldens) is understood (§5).

---

## 9. Summary table — gate

| Area | Result |
|---|---|
| Q1 Base alignment | ACCEPTED (clean: 165/180 in, 188 out) |
| Q2 Catalog shape validation | ACCEPTED (3 real shapes; no two-shape rule) |
| Q3 Notification actions | ACCEPTED (feature in; buttons only if low-risk) |
| Q4 Persistence consolidation | ACCEPTED (greenfield; no migration) |
| Scope stability | Stable |
| Deferred scope sanity | All polish/platform; nothing mis-deferred |
| Architecture readiness | Ready |
| Test readiness | Ready (one non-blocking note) |
| Slice readiness | Ready (recommend 8/10 sub-splits) |
| **Gate decision** | **Ready for implementation** |

---

*End of Round 3 readiness review. Implementation may begin at Slice 1 under the
constraints in §7 once owner sign-off on Q1–Q4 is recorded. No implementation,
commits, or production source changes have been made.*
