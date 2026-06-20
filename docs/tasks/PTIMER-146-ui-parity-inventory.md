# PTIMER-146 Android MVP — UI Parity Inventory

Date: 2026-06-21
Branch: `feature/PTIMER-146-android-mvp`
PR: Draft PR #16

## Scope and limits

This pass is inventory-only. No Android UI implementation was attempted.

Verified in this pass:

- PR #16 is open/draft at branch HEAD `f3c8dc7` before this doc pass.
- PR #16 has 54 commits and 97 changed files against `main`.
- The PR branch is 54 commits ahead and 2 commits behind current `main`.
- Android source inspected:
  - `android/app/src/main/kotlin/com/sangwook/ptimer/ui/ShootingScreen.kt`
  - `android/app/src/main/kotlin/com/sangwook/ptimer/ui/TestTags.kt`
  - `android/app/src/main/kotlin/com/sangwook/ptimer/details/DetailsPresenter.kt`
  - `android/app/src/main/kotlin/com/sangwook/ptimer/MainActivity.kt`
  - UI smoke test sources under `android/app/src/test/.../ui` and
    `android/app/src/androidTest/.../ui`
  - PTIMER-146 worklog and test-intent docs

Not verified in this pass:

- Direct current iOS UI source was not successfully located/fetched in this
  connector pass, so iOS target behavior below is based on PTIMER-146 handoff,
  existing project decisions, and Android-side parity notes, not fresh iOS-source
  inspection.
- No screenshots were available in this chat; visual fidelity is not verified.
- No Gradle command was run in this environment. Source was inspected through the
  GitHub connector; the execution container has no reachable GitHub/network clone.
- `connectedDebugAndroidTest` remains unverified green in this pass.

## Coverage counts

UI parity inventory areas: 18
Checked: 18/18 = 100.0%
Already acceptable: 7/18 = 38.9%
Needs implementation: 8/18 = 44.4%
Needs user decision/screenshots: 2/18 = 11.1%
Deferred: 1/18 = 5.6%

These are UI-inventory classifications, not functional MVP completion claims.

## Inventory

| # | Area | iOS target behavior / visual intent | Android current behavior | Gap | Severity | Recommended action | Test coverage |
|---|---|---|---|---|---|---|---|
| 1 | Shooting main hierarchy | Camera identity first, then film/model, target, exposure controls, result, workspace. | `ShootingScreen` uses `LazyColumn` ordered as camera title, slot chips, Film, Target shutter, Base shutter + ND, Result, Custom films, Active, Recently completed. | Structure is now close enough for an MVP parity base; visual density still needs screenshots. | Medium | no action | host-side Compose smoke covers composition only |
| 2 | Camera slot header | Clear active camera identity and quick camera switching without confusing timer identity. | Active label headline + `FilterChip` slot row, Rename and Reset actions. | Behavior is present; chip spacing/density vs iOS needs screenshot/user review. | Medium | needs screenshot/user decision | untested visually; ViewModel/session tests cover slot behavior elsewhere |
| 3 | Film selector | iOS-style film selection with clear film identity, ISO, custom/official distinction, and low friction. | Current Android uses a dropdown opened by `Choose`; rows include name, ISO, and custom suffix. | Functional but not iOS-like. Likely should become a fuller selector/list/sheet before claiming UI parity. | Major | implement now | not covered by UI smoke |
| 4 | Model picker | Official / app-derived / community model choice should be visible and hard to confuse. | Android uses `SingleChoiceSegmentedButtonRow` for available models. | Structural parity is acceptable; label wrapping may need screenshot review later. | Medium | no action | not directly asserted beyond source inspection |
| 5 | Target shutter | iOS target shutter flow is a first-class card/control with compare/start affordance. | Android has Target shutter section with Set/Clear and optional play button; Set opens seconds text dialog. | Functional but visually/basic-control parity is weak. Needs a designed Android equivalent, even if iOS wheel remains out of scope. | Major | implement now | controller tests cover behavior; UI smoke does not cover target |
| 6 | Base shutter / ND controls | iOS uses dense shooting controls; wheel exception is allowed, but values must remain fast and legible. | Android uses simple minus/plus steppers for base shutter and ND stops. | May be acceptable as wheel exception, but user decision needed on density and friction. | Medium | needs screenshot/user decision | ND plus has smoke selector; no interaction green on device |
| 7 | Result card | Adjusted, reciprocity basis/details, corrected, and target start actions should be separate and obvious. | Android has a Result card with Adjusted row + play, Reciprocity row + badge + Details, Corrected row + play/disabled reason. | Current structure matches the fixed per-source start-action model. Visual polish remains. | Medium | no action | controller tests; host smoke asserts adjusted play exists |
| 8 | Active timer row | Active row should preserve timer identity, source subtitle, metadata, remaining time, and actions without clipping. | Android timer card shows title, status pill, subtitle, metadata, remaining, ends-at, Pause/Resume, Start new, Remove. | Structurally good. Needs visual screenshot check before final parity claim. | Medium | no action | host smoke asserts active row identity; instrumented test authored but not green |
| 9 | Completed timer row | Completed history should keep identity and allow Start again / Remove. | Completed timer cards share layout and expose Start again + Remove. | Structurally acceptable. | Medium | no action | behavior tests elsewhere; no visual/device UI green |
| 10 | Timer actions | Active supports pause/resume/remove and Start new; completed supports Start again/remove. | Android actions are present in `TimerCard`. | No immediate gap from source inspection. | Minor | no action | controller tests; instrumented smoke authored for pause/resume/remove but blocked |
| 11 | Details metadata presentation | Details should show source, calculation, basis, corrected value, source range, and comparison/reference information clearly. | Android Details dialog renders rows and comparison lines from `DetailsPresenter`. | Functional rows exist, but layout is basic dialog text and likely below iOS readability. | Major | implement now | `DetailsPresenterTest`; no visual UI test |
| 12 | Details graph / source reference | iOS details include graph/source/reference presentation and source markers/notes. | Android `DetailsPresenter` explicitly defers graph fidelity; `DetailsDialog` has no graph. | Largest visible parity gap in Details. | Major | implement now | untested visually; presenter rows only |
| 13 | Custom formula editor | iOS has a richer custom formula editor with clear fields, preview, save/edit semantics, and source/reference presentation. | Android has a minimal `NewFormulaDialog` with name, exponent, no-correction seconds. | Too minimal for UI parity. | Major | implement now | factory/library tests cover behavior; UI untested |
| 14 | Custom table editor | iOS custom table editor supports compact anchor rows, validation, sorting, fitted preview, and usable editing flow. | Android has a minimal `NewTableDialog` with repeated text fields and Add anchor. | Too minimal for UI parity and likely awkward on phone. | Major | implement now | core/app behavior tests; UI untested |
| 15 | Fitted preview / create formula from table | iOS policy: fitted formula is inspection/seed only; Create Custom Formula should be prominent near preview. | Android shows `fittedPreviewSummary` text and a text button `Create formula from this table` inside Film section when selected custom table. | Functional but CTA prominence/layout likely below iOS intent. | Medium | implement now | behavior tested; UI untested |
| 16 | Custom edit/delete/source management | iOS custom film management supports edit/delete flows and source/reference display. | Android exposes delete for selected custom film and new formula/table actions; no rich edit screen seen in inspected UI. | Custom management UI is not parity-level. | Major | implement now | behavior partially tested; UI untested |
| 17 | Exact alarm notice | Reliability prompt should not disrupt shooting flow. | Android shows compact dismissible notice only when exact-alarm prompt is visible; settings deep link is wired in `MainActivity`. | Current placement is acceptable for MVP; screenshot review later. | Medium | no action | ViewModel tests; UI notice selector exists; connected UI blocked |
| 18 | Notification / live countdown UI | iOS lock-screen/live surfaces are replaced by Android notification model. | Completion and ongoing notification code exists; foreground service/live countdown hardening remains outside this inventory. | Android replacement is intentionally different; live countdown reliability can be deferred. | Medium | defer | scheduling/notification rules tested; device evidence from prior worklog only |

## Summary

Current Android UI is no longer a bare functional screen. It already has an
attempted iOS-like shooting hierarchy, sectioned cards, segmented model picker,
filled play actions, and richer timer cards. The earlier handoff statement that
UI parity had not meaningfully started is stale for the current branch.

However, full UI parity is not done. The main remaining visible gaps are Details
(graph/source-reference), Custom Film editors/management, film selector quality,
and control density/screenshot validation.

## Recommended implementation order

1. Details parity pass: graph/source/reference presentation first.
2. Custom film editor pass: formula/table editor density, validation, fitted
   preview placement, create-formula CTA.
3. Shooting main polish pass: film selector and target/base/ND control density.
4. Timer workspace visual pass: verify row density and action hierarchy with
   screenshots; adjust only if needed.
5. Stable-emulator UI verification pass: run authored instrumented smoke on API
   34/35 or another stable supported target.

## Verification status

- Source inspection: done through GitHub connector for the Android files listed
  above.
- Automated execution: not run in this ChatGPT environment.
- Handoff/worklog says latest green JVM suite was 201 tests with 3/3 host-side
  Robolectric Compose smoke passing, but that was not re-run here.
- Instrumented smoke tests are authored as 3 tests, but still 0/3 verified green
  in this pass.

## Follow-up

Keep PR #16 draft. Do not claim Android MVP review-ready until UI parity gaps are
implemented or explicitly deferred, and until required verification is actually
run in an environment with a stable emulator/device.
