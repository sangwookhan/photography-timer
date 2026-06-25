# PTIMER-146 — Android MVP (3rd attempt) — JIRA-centric Feature Backlog

> **Status:** Planning baseline for review. No code yet. This is the lightweight
> decomposition that drives the Claude-led 3rd attempt — it replaces attempt 1's
> heavy spec extraction and attempt 2's test-restructuring-first.
>
> **Parent:** PTIMER-146 "Deliver native Android MVP from current iOS behavior"
> (Story, 해야 할 일) under epic PTIMER-144 "Native Android Platform Expansion".
> Reporter/assignee: sangwook_han. Jira: `https://sangwook.atlassian.net/browse/PTIMER-146`.

## Governing principle (owner-confirmed 2026-06-18)

1. **Only 완료 (Done) iOS tickets are the Android reference.** 해야 할 일 / Won't
   Do tickets are NOT current iOS behavior → out of scope (matches PTIMER-146's
   "Out of Scope: adding new product behavior beyond the current iOS MVP
   reference").
2. **JIRA tickets are the oracle spine** (not GitHub/Bitbucket PR numbers).
   Implement against current iOS HEAD (`ec0e61b`) behavior; use the named tickets
   + iOS source dir + `shared/test-fixtures/` as the behavior oracle.
3. **Understand-and-reconstruct**, not commit-replay. Skip iOS-internal churn.
4. Keep cheap assets: pure-Kotlin `:core` + `:app` split; the shared golden
   fixtures as the parity oracle (avoid porting the whole iOS test suite).
5. **UI** = iOS screen captures under `docs/design/ios-screens/`, two fidelity
   tiers (T1 clone exactly minus OS chrome: timer-list full, reciprocity detail,
   custom-film edit; T2 resemble/adapt: main shooting, bottom-sheet list).
6. One reusable `SnapWheel` (base shutter / ND / target shutter). **Hard
   requirement (PTIMER-64 is the iOS oracle):** emit value on every centered-item
   change DURING fling so adjusted shutter + exposure recompute live.

## Commit message convention (this ticket)

Every Android commit carries the umbrella ticket in the canonical footer
position, preceded by an Android-port traceability block stating, per iOS
feature ticket, whether this commit **완료 / 일부 / 참조** (Completed / Partial /
Referenced) its behavior on Android. JIRA IDs never appear in the subject.

```
<imperative summary, no ticket id>

<body: what changed and why>

Android port:
  완료(Completed):  PTIMER-19, PTIMER-22, PTIMER-30
  일부(Partial):    PTIMER-8
  참조(Referenced): PTIMER-64, PTIMER-177

PTIMER-146 Deliver native Android MVP from current iOS behavior

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

- **완료** = the iOS ticket's behavior is fully reproduced on Android (with parity
  test where applicable).
- **일부** = partially implemented; remainder tracked to a later unit.
- **참조** = consulted as design/behavior reference but not (yet) reproduced here.
- Wrapped ticket lines use hanging indent; Co-Authored-By stays last,
  blank-line-separated, after the PTIMER-146 footer.

---

## Backlog (dependency order)

Layer: **C** = `:core` (pure Kotlin), **A** = `:app`. Oracle tickets listed are
**완료** unless marked. iOS source dirs under
`ios/PTimerKit/Sources/{PTimerCore,PTimerKit}`.

| # | Unit | Layer | iOS oracle (완료 JIRA tickets) | UI tier · screens |
|---|---|---|---|---|
| 1 | Gradle / module skeleton | C+A | infra (greenfield). Ref: PTIMER-145 (Android skeleton), PTIMER-116/142, **PTIMER-177** (pure state-machine ÷ UIKit = `:core`/`:app` boundary ref) | — |
| 2 | Exposure core (calc, stops, ND, ladder, formatting, snap ε=1e-6, scale modes) | C | 8, 19, 22, 26, 29, 30, 79, 80, 112, 172. Fixture: `exposure-golden.json` | — |
| 2.5 | **SnapWheel spike + validation** (reusable wheel; **live value emission during fling**; throwaway harness feeding unit-2 calc) — validate feel + live recompute on device, decide ND wheel-vs-stepper, then lock the API | A | **64** (continuous result while spinning), 20, 21 (input controls). Throwaway harness, not shipped UI | validate vs `wheel-base-nd-*`, `target-shutter-input-*` |
| 3 | Catalog + reciprocity core (formula, table log-log, threshold, limited, unsupported, confidence, alternate models) | C | 17, 85, 86, 87, 88, 89, 90, 96, 102, 103, 104, 113, 122, 129, 134–140, 160, 162, 163, 164, 166–170. Bugs: 101, 109, 125. Fixture: `catalog-validation-cases.json` | — |
| 4 | Timer core (state machine Running/Paused/Completed/**Canceled**, runtime tick, identity incl. selectedModelLabel, ordering) | C | 9, 10, 27, 37, 50, 171. Ref: 177. **188** = Start New/Cancel/Canceled is already in base (`ec0e61b`/#15); ticket still 해야 할 일 → treat the merged behavior as oracle, fold into unit 6 UI | — |
| 5 | Persistence schemas + `*Store` (timer collection, slot session, custom-film library; schemaVersion=1; corrupt→default) | C | 70, 97 (snapshot/restore behavior) | — |
| 6 | Coordinator + VM + timer persistence + **timer UI** (first runnable app: multi-timer lifecycle, relaunch restore, Start Again, Start New, Cancel, Canceled) | A | 36, 40, 41, 42, 43, 46–52, 54, 55, 70, 72, 126; bug-fixes 71, 124, 127; 188(base) | T1 `timer-list-fullscreen/*` · T2 `bottom-sheet-timer-list/*` |
| 7 | **SnapWheel** + calculator + film selection + alternate-model picker (digital + film corrected result, Start enablement) | A | 7, 20, 21, 24, 58, 59, 63, **64**, 65, 81, 92, 93, 94, 98, 99, 141 | T2 `main-shooting/*` (incl. `wheel-base-nd.png`) · `film-picker/*` |
| 8 | Camera slots + rename (per-slot calc/film/target/model, capture-on-switch, immutable identity) | A | 120, 123 | T2 `camera-slot/*` |
| 9 | Custom film library + formula + table + fitted preview + Create-Formula-from-table (**inspection-only invariant**) | C+A | 84, 85, 165, 178, 179, 180. Ref: 160 | T1 `custom-film-edit/*` |
| 10 | Target Shutter (per-slot target + stop-difference comparison; no fabrication when non-quantified) | A | 25 | T2 `target-shutter/*` |
| 11 | Reciprocity Details (source/model/calc transparency, model picker, custom rows, fitted comparison, reference/error columns) — **DONE, full iOS parity**: source-reference table (metered→correction, color filter sub-line), guidance-boundary rows, status detail sentence (verbatim, manufacturer stop-signal lead), App-derived calc label, round-duration graph axis, source-evidence markers + not-recommended-boundary, full legend chips, Sources citation, legend glossary | A | 95, 100, 119, 130, 143, 159, 161 | T1 `reciprocity-detail/*` |
| 12 | Notifications (completion + ongoing running-timer foreground service) — **DONE**. Notification action buttons **dropped** (the ongoing notification is a single aggregate, so per-timer Pause/Cancel belongs with the per-timer lock-screen Live Activity, not here); instead **tapping the notification opens the expanded timer list** | A | 66, 67, 68, 69 (iOS lock-screen/ActivityKit → Android notification + foreground-service functional analogue) | — |

Notes:
- **#9 may sub-split:** 9a formula authoring / 9b table + fitted preview / 9c
  create-formula-from-table.
- **Hard guardrail (units 9 & 11):** fitted formula + `referenceTableFilmID`
  never enter the active calculation (inspection-only) — unit-tested.
- Protected-area parity = exact (exposure snap, reciprocity policy order,
  confidence mapping, timer state machine, persistence schema); else behavior
  parity.

## Skip — iOS-internal churn (no product behavior to port)

Epic PTIMER-147 (148, 149, 153–157 test consolidation/splits), epic
PTIMER-176 / PTIMER-174 (test-suite scale). **Exception:** PTIMER-177 (decouple
pure timer state machine from UIKit) is *referenced* as the `:core`/`:app`
boundary model, not skipped behaviorally.

## Out of scope — not current iOS behavior (해야 할 일 / Won't Do)

Epic PTIMER-13 Shooting Record System (16, 106, 107, 108); 73 sound
customization; 74 Dynamic Island (Won't Do); 82, 83 reverse recommendation
(Won't Do); 158 enhanced source refs; 186 catalog-structure analysis; 187
alternate ND notation; epic PTIMER-185 release prep (181, 182 accessibility, 183
localization, 184 About, 189). Re-evaluate only if owner explicitly pulls one in.

## Decisions & open questions

- **Theme — DECIDED: dark only** (used day and night). Android app ships a single
  dark theme; captures are dark.
- **ND control — DECIDED: wheel** (unify with iOS; validated on device at unit
  2.5). No stepper. The shared SnapWheel drives base shutter, ND, and target
  shutter.
- **SnapWheel feel — accepted at unit 2.5.** Live-during-fling recompute
  confirmed on device; selection uses dimmed edges + a clear center with
  hairline bounds (not a fill band). Fling damping is slightly lighter than
  iOS — tunable later via the snap fling decay, not a blocker.
- **Notification action buttons** — DECIDED: **dropped**. The ongoing
  notification is a single aggregate ("N timers running"), so per-timer
  Pause/Cancel is ambiguous there; per-timer actions belong with the per-timer
  lock-screen Live Activity (deferred to a separate PR). Instead, **tapping the
  notification opens the app straight into the expanded timer list**.

Unit 2.5 is a **validation gate**: the SnapWheel API is locked only after the
live-during-fling behavior is confirmed on a device; units 6/7/10 build on the
locked component.

## Device-test polish backlog (deferred refinements)

Surface-level refinements found during device review, deferred so they don't
interrupt the current feature flow. Not blockers.

- **[DONE 2026-06-24] Target Shutter — quick + fine adjustment (unit 10).** Added
  a Quick/Fine segmented toggle to `TargetShutterSheet`; Quick is a single
  SnapWheel of presets (1s…8h) parking on the nearest to the current value, Fine
  keeps the h/m/s wheels — both edit the same total (iOS Quick/Fine pages).
- **[DONE 2026-06-24] Target Shutter — tone down the row.** `TargetShutterRow`
  value is now `bodyLarge` SemiBold in `onSurface` (brighter, lighter); the ↑/↓
  arrow + stop-diff dropped to `bodyMedium` and are coloured by direction like
  iOS — accent (longer) / amber (shorter) / green (match) — instead of bold amber
  for everything.
- **[DONE] MiniTimerBar — show all statuses + portrait cards.** The peeking
  `MiniTimerBar` now shows the top-3 timers across every status (active first,
  then most-recent history) with a "+N / View all" overflow tile, so a very
  short / just-finished timer stays briefly visible instead of vanishing the
  instant it leaves the active set (the registered bug). Cards switched from a
  wide 180-dp landscape strip to iOS-style tall portrait cards (96×116).
- **[DONE] Timer sheet behavior.** The expanded list now has a scrim that blocks
  the shooting surface (Reset/wheels unreachable behind it) and collapses on an
  outside tap; starting a timer lands on the mini peek (not half-open); clearing
  the last timer collapses the sheet.
- **[DONE] Per-timer order number (iOS RunningTimerItem.order).** Stable 1-based
  creation number shown beside the slot badge in the full card; persisted.
- **[DONE] Start New / Start Again focus.** A freshly started timer becomes the
  focused/scrolled row so it is visible (was hidden above the previously focused
  card). Also ported to iOS.
- **[DONE] Back navigation.** System Back / swipe-back returns to the main screen
  from every surface (Reciprocity Details, expanded Timers, modal sheets/dialogs)
  instead of exiting the app.
- **[DONE] Notification tap → timer list.** Tapping the ongoing/completion
  notification opens the app straight into the expanded timer list.
- **[DONE] App icon (placeholder).** Ships the iOS app icon as the launcher icon
  until a dedicated Android adaptive-icon ticket.
