# PTimer — Requirements

**Type**: User-scenario-driven requirements document.
**Audience**: Product / engineering / future contributors who need to know what the app shall do.
**Direction of influence**: requirements → behavior contracts → code, one-way. Requirements is normative for product intent; downstream documents may refine how each requirement is specified, structured, or verified. References to downstream documents are navigational only and do not make Requirements depend on those documents. Where a requirement says "the system shall X," the *what* and *why* live here; the *how* is decided downstream.
**Phrasing rule**: every requirement shall describe a *user-visible need* or an *integrity invariant*. Implementation specifics (concrete pixel sizes, refresh intervals, persistence keys, lint rule ids, baseline file names, prop wrapper choices) belong downstream and shall not appear here.

**Document boundary**. This document defines *what the app shall do*. It does not define:

- *how* the system is structured — see `docs/architecture/Architecture.md`;
- *what behavior contracts* realize each requirement — see `docs/specs/`;
- *how* changes are verified — see `docs/verification/Strategy.md`.

When a requirement states a non-functional obligation (e.g. determinism, persistence stability), the obligation lives here; the mechanism that achieves it lives in the relevant downstream document.

---

## 1. Personas

### 1.1 Long-exposure photographer (primary)

A photographer who shoots long exposures with ND filters. Works on a tripod, often outdoors, often metering one shot and then waiting tens of seconds to several minutes per frame. May be using a film camera, a digital camera, or alternating between the two on the same outing. Carries an iPhone in portrait grip while shooting; rarely puts the phone down once a sequence is set up.

### 1.2 Film photographer with reciprocity correction (specialization)

The same photographer when shooting film stocks whose reciprocity behavior departs from the metered value. Needs the metered exposure to be corrected against the active film's published reciprocity data, not just a generic "stops" calculation. Different film stocks have different correction curves; some have only a manufacturer threshold, some publish a quantified formula (with optional manufacturer reference points), some publish only qualitative long-exposure guidance.

### 1.3 Multi-camera photographer (specialization)

The same photographer running two to four cameras through the same scene during one shooting session — for example an analog medium-format body that needs reciprocity correction in parallel with a digital body that doesn't, or two film bodies loaded with different stocks that each need their own reciprocity profile. Common field combinations:

- **Digital plus film** — one digital body and one film body alternated shot-to-shot. Switching between them shall not force the photographer to rebuild the calculator (re-pick the film, re-enter base shutter, re-set ND) every time the active camera changes.
- **Two films, two bodies** — for example Portra 400 in one body and Acros II in another. Each camera needs its own selected film and its own reciprocity result preserved across switches.
- **Multiple simultaneous timers from different cameras** — one camera holding a long exposure while the photographer prepares the next shot on another. Each running timer carries enough identity for the photographer to tell at a glance which camera and which shot it belongs to.
- **Fast field switching** — composition changes are quick; the active-camera switch shall be a single, compact gesture rather than a settings detour, and shall not reset any inactive camera's setup.
- **Two to four active cameras** — the field workflow stays small enough for a phone screen. Beyond four cameras the workspace would shade into an inventory manager, which is out of scope (see §5).

Needs to identify *which* timer belongs to *which* shot at a glance, not memorize an unlabelled queue.

The product is **not** designed for the casual snapshot user, the studio strobe shooter, or the cinematography use case (those have very different metering loops and timer needs).

---

## 2. Core scenarios

Each scenario lists the user goal, the steps the app must support, and the boundary conditions where the app's behavior is non-obvious.

### Scenario 1 — Compute output shutter for an ND filter (digital workflow)

**Goal.** Photographer meters with the camera, then wants to know the shutter speed required after stopping down N stops with an ND filter.

**Steps.**
1. Set base shutter from the 1/3-stop densified ladder with camera-facing labels.
2. Set ND from the whole-stop ND ladder.
3. Read the output shutter on the result row.
4. (Optional) Start a timer from the output shutter when the value is long enough that an in-camera shutter or wristwatch is impractical.

**Boundary conditions.**
- The base shutter must come from the 1/3-stop densified ladder (55 values spanning 1/8000 .. 30 s) with conventional camera-facing labels. Free-text input is rejected.
- ND values come from the whole-stop ladder `0, 1, 2, …, 30`. One-third-stop applies to the base shutter only; the ND picker stays whole-stop because real-world fixed ND filters are sold in whole-stop strengths. Values outside the range are not accepted.
- The output shutter is reported using conventional photographic notation. In the shipping 1/3-stop scale the calculated value is reported directly (formatted by the standard time-display rules) without snapping to a coarser ladder; the precise value drives any downstream timer.
- A future Settings preference may let a user request a coarser scale (Full / 1/2 stop). When such a preference exists, in-range full-stop results may snap to the conventional reference and long values above 30 s may present in a power-of-two doubling ladder (64, 128, 256 …). In the current release no such selector is exposed; all results follow the 1/3-stop reporting rule.

### Scenario 2 — Compute corrected exposure for a film stock (film workflow)

**Goal.** Photographer with a film camera meters the scene, then wants to know the *corrected* exposure that compensates for the film's reciprocity characteristic.

**Steps.**
1. Open the film picker sheet (the picker is a dedicated sheet, not an in-screen dropdown).
2. Select a preset film stock from the launch catalog.
3. Read the film row's authority subtitle to confirm whether the active reciprocity profile is **Official guidance** (manufacturer-published) or **Unofficial practical** (community-derived). The label is always present for the authorities shipped in the launch dataset.
4. Set base shutter and ND as in Scenario 1.
5. The result section now shows two stable rows: **Adjusted Shutter** (ND-applied, pre-reciprocity) and **Corrected Exposure** (reciprocity-applied final value).
6. (Optional) Open the reciprocity details sheet to see the supporting data — Profile / Formula or Reference / Graph / Sources sections, in that order, with a stable initial detent.

**Boundary conditions.**
- The Corrected Exposure row is *always visible* in film workflow — the layout shape does not change as the user pans through metered values that switch the result between *quantified*, *limited-guidance*, and *unsupported* outcomes.
- A *quantified* corrected exposure surfaces a numeric primary line plus a status badge. The status category is one of *No correction* (inside the manufacturer's no-correction threshold), *Formula-derived* (on the active calculation curve), or *Beyond source range* / *Outside guidance* (the formula keeps producing a numeric continuation past the manufacturer's supported boundary; the badge carries a warning tone).
- A *limited-guidance* result surfaces calm explanatory text in place of a number. The app never fabricates a numeric corrected value when the data does not support one.
- An *unsupported* result with no numeric continuation surfaces a guidance note. The Start Timer button on the corrected row is disabled with an explanatory accessibility hint.
- The base shutter ladder, the ND ladder, and the result-reporting rules are identical to Scenario 1. Film selection does not change the calculator's exposure scale.

### Scenario 3 — Run a long-exposure timer

**Goal.** Photographer fires the shutter on the camera, then starts a timer in the app to measure the open-shutter duration.

**Steps.**
1. From the result section, the user activates a Start Timer affordance on the row whose value they want to time. In film workflow there are two start affordances — one on the Adjusted Shutter row, one on the Corrected Exposure row — and the user picks based on intent.
2. The timer enters a *workspace surface* that remains visible alongside the calculator. The user can adjust ND or swap films for the next shot without dismissing the timer or losing sight of it. The workspace surface's exact placement is a design decision, not a requirement.
3. The workspace surface communicates, for each running timer: remaining time, *some sense of progress* over multiple time scales (so a 30 s timer and a 30 min timer both feel responsive), and a distinguishing identity cue independent of name and time text.
4. The user can switch the workspace surface between a glanceable summary mode and an expanded mode that shows every running, paused, and completed timer together.
5. When the timer's duration elapses, the system surfaces a completion signal that reaches the user even if they are not looking at the phone (camera in hand, phone in pocket), and the timer's card transitions to a "Done" state in-app.

**Boundary conditions.**
- Each timer has a stable identity. Ordering: active group with most recent first, completed group with most recent completion first.
- A timer's duration is rejected at start time if it is not strictly positive *and* finite — `Inf` and `NaN` are forbidden.
- A timer carries an auto-generated name and a basis-summary line so the user can reconstruct *which shot* the timer belongs to. The name reflects the start source (digital result vs. film adjusted vs. film corrected) and includes the film stock name when relevant.

### Scenario 4 — Pause and resume

**Goal.** Photographer wants to pause a running timer (e.g. clouds change, the subject moves) and resume it later from the same logical point.

**Steps.**
1. Tap the running timer's pause affordance.
2. The timer enters paused state. Wall-clock time may pass; the paused timer does not auto-complete.
3. Tap resume; the timer continues from the *frozen remaining time* at the moment of pause, not from the original end date.

**Boundary conditions.**
- A pause whose remaining time has already reached zero short-circuits to *completed* rather than entering a zero-remaining paused state. The user never sees a "paused at 0 s" timer.
- A paused timer's hypothetical completion time is observable for display purposes, but resume always recomputes the end date as *now + remaining time*. The original end date is not preserved across pause.

### Scenario 5 — Run multiple timers in parallel

**Goal.** Photographer running two or more cameras (or two pending exposures from the same camera) keeps a separate timer per shot.

**Steps.**
1. Repeat Scenario 3 to start a second timer. The workspace surface accommodates additional timers without losing the calculator above; each timer carries a unique identity cue so the user can pick a card at a glance without reading text.
2. The user can focus a single timer to inspect it more closely.
3. The user can pause one timer while the others continue running.
4. Completed timers gather in the completed group, most recent completion first.

**Boundary conditions.**
- A timer's identity cue is *stable for the timer's lifetime* — it does not shift when the user reorders, focuses, or moves a timer between active and completed groups.
- The workspace surface remains stable in shape across summary / expanded transitions; switching modes does not recompute layout for cards that were already visible.
- The lock-screen surface (Scenario 6) shows *one* representative timer at a time, even when multiple timers are running. Selection rule lives in Scenario 6.

### Scenario 6 — Lock-screen monitoring

**Goal.** Photographer puts the phone down (or in a pocket) while the shutter is open and uses the device's lock-screen surface to glance at remaining time without unlocking.

**Steps.**
1. Start a timer (Scenario 3).
2. Lock the phone. A lock-screen surface communicates the *representative* timer's name, duration, and end date.
3. The lock-screen surface updates frequently enough that the user perceives time advancing without unlocking.
4. When all timers stop (completed or removed), the lock-screen surface goes away.

**Boundary conditions.**
- The representative is the active timer with the earliest end date. Ties resolve deterministically — the user shall never see the surface flicker between two timers because the implementation broke a tie inconsistently.
- Continuity through app-active / background transitions: the surface shall not flicker between two representatives during a scene-phase change unless the underlying selection actually shifted.
- The lock-screen surface shall never display a timer that no longer exists — once every running/paused timer has stopped, the surface ends.

### Scenario 7 — App restart with timers in flight

**Goal.** Photographer's phone restarts (battery, manual force-quit, OS update) while one or more timers are running or paused. On reopen the timers are still there.

**Steps.**
1. With timers running and paused in the workspace, force-quit the app or restart the phone.
2. Reopen the app. The previously running timers are restored — running timers reflect wall-clock progress while the app was dead, paused timers are unchanged.
3. A running timer whose end date has already passed restores as completed; the completion timestamp is the original end date, not the restoration moment.

**Boundary conditions.**
- Persisted timer state shall evolve only via backward-compatible additions: a snapshot written by an older release must continue to restore correctly under the current release.
- A persisted paused timer whose freeze metadata is missing or inconsistent is treated as corrupted input. The system surfaces such an entry as completed rather than fabricating a plausible-looking timestamp; the user never sees a paused timer with a "paused-at" time that did not actually happen.
- A timer whose duration is non-finite never enters persistence — the input guard at start time rejects it before any state is written.

### Scenario 8 — Restart with a film selection in flight

**Goal.** Photographer's selected film stock and the calculator's working context survive app restart so they don't have to re-pick them after every interruption.

**Steps.**
1. Select a film, set base shutter and ND.
2. Force-quit the app.
3. Reopen. The same film, base shutter, and ND are restored.

**Boundary conditions.**
- A persisted film id that no longer exists in the catalog drops the selection silently and writes a clean snapshot back so subsequent reads are not confused.
- Base shutter and ND are sanitized on restore against the active exposure scale's ladders: out-of-range values are rejected, only ladder values are accepted.
- A snapshot written by an older release that predates the exposure scale token (or fractional ND) shall continue to restore correctly: missing fields shall resolve to the shipping 1/3-stop scale, and a legacy whole-stop value shall be accepted because the shipping ladder is a strict superset of the legacy full-stop ladder.

---

## 3. Functional requirements

Each requirement is a "system shall" obligation with a back-reference to the originating scenario. The wording is intentionally close to acceptance-criteria style.

### 3.1 Calculator

- **FR-1.1** The user shall enter base shutter values only from the shipping 1/3-stop densified ladder with conventional camera-facing labels (sub-1 s as `1/N` reciprocal fractions, ≥ 1 s as integer or `N.Ns` per camera convention). Free-form numeric entry is not accepted. (Scenario 1, 2)
- **FR-1.2** The user shall enter ND values only from the whole-stop ladder `0, 1, 2, …, 30`. The supported range is wide enough to cover stacked-ND practical use. One-third-stop applies to the base shutter only; the ND ladder stays whole-stop in every shipping mode. (Scenario 1)
- **FR-1.3** The system shall compute the output shutter from base shutter and ND using exposure-stop arithmetic. (Scenario 1)
- **FR-1.4** The system shall present the output shutter using conventional photographic notation. In the shipping 1/3-stop scale the calculated value is reported directly, formatted by the standard time-display rules, without snapping back to a coarser ladder. The exact value is preserved for downstream timer use. A future Settings preference may enable snapping to a full-stop ladder (and the power-of-two ladder above 30 s) when the user opts into a coarser scale; until then no such snap is applied. (Scenario 1)
- **FR-1.5** The system shall reject calculation inputs that produce non-finite results (overflow / NaN) by surfacing a typed failure to the caller rather than a number that could mislead. (Scenario 1 boundary)
- **FR-1.6** While the user is dragging an input value, the system shall preview the resulting output without committing to the input until the gesture ends. The user can release on the original value to revert. (Scenario 1)

### 3.2 Reciprocity

- **FR-2.1** The system shall present a curated set of preset films at launch, each with exactly one published reciprocity profile. The launch catalog shall be sourced from current official manufacturer documentation and shall cover both quantified formula profiles (with optional manufacturer source-evidence rows) and limited-guidance profiles whose long-exposure section is qualitative only. It shall preserve published guidance — threshold ranges, color-filter recommendations, development-time hints, and stop-signal boundaries — in a form the user can drill into. (Scenario 2)
- **FR-2.2** Given a metered exposure and an active profile, the system shall classify the result into exactly one of three forms — *quantified*, *limited-guidance*, or *unsupported* — and shall not allow a result that represents more than one form at once. (Scenario 2)
- **FR-2.3** A *quantified* result shall carry a corrected exposure value, a status badge the user can read at a glance, and provenance the user can drill into to see the formula expression and any manufacturer reference points. (Scenario 2)
- **FR-2.4** A *limited-guidance* result shall present calm guidance text instead of a corrected number. The system shall not fabricate a numeric corrected value when the underlying data does not support one. (Scenario 2 boundary)
- **FR-2.5** An *unsupported* result with no numeric continuation shall present a guidance note and shall disable the Start Timer affordance on the corrected-exposure row, with an accessibility hint explaining why. An *unsupported* result that carries a formula prediction outside the supported range (when the formula keeps producing a value past its source-range boundary) shall surface the value with a warning-toned badge and shall keep the Start Timer affordance enabled. (Scenario 2 boundary)
- **FR-2.6** Reciprocity evaluation shall be deterministic — the same profile and metered value shall always produce the same result form, corrected value, and status indication. (NFR-D.1)
- **FR-2.7** The user shall reach the film selection through a dedicated, dismissible surface rather than an inline dropdown that competes with the calculator for screen room. (Scenario 2)
- **FR-2.8** Reciprocity coverage shall not be limited to films with a quantified formula. Threshold-only and limited-guidance published guidance are first-class scope rather than lesser fallbacks, and the domain shall reserve capacity for future unofficial or user-defined entries. (Scenario 2 boundary; complements FR-2.2)

### 3.3 Timer lifecycle

- **FR-3.1** The system shall start a timer only with a duration that is strictly positive and finite. Infinite, NaN, or non-positive durations are rejected at the entry point, before any persisted state is written. (Scenario 3 boundary)
- **FR-3.2** A timer shall move only along these state transitions: *running → paused*, *paused → running*, *running → completed*, *paused → completed* (via resume when the frozen remaining time has reached zero). Other transitions are not representable. (Scenario 3, 4)
- **FR-3.3** A paused timer shall not consume wall-clock time toward its completion. The frozen remaining time is preserved as the user left it. (Scenario 4)
- **FR-3.4** Resume shall restart the timer from *now + frozen remaining time*; the original end date is not preserved across pause. (Scenario 4 boundary)
- **FR-3.5** A pause whose remaining time has already reached zero shall short-circuit to completed rather than enter a zero-remaining paused state. (Scenario 4 boundary)
- **FR-3.6** Each transition into completed shall produce exactly one external completion signal to the user. Pending signals shall be cancelled when a timer is removed or transitions running → paused. (Scenario 3)
- **FR-3.7** Active timers shall be presented most-recent-first; completed timers shall be presented most-recently-completed-first; ties shall resolve deterministically so the user does not see an unstable order. (Scenario 5)

### 3.4 Multi-timer + lock-screen

- **FR-4.1** The system shall support multiple concurrent timers, each with a stable identity that survives running, paused, completed, reordered, focused, and inspected transitions. (Scenario 5)
- **FR-4.2** Each timer shall carry a non-text identity cue (e.g. a tint, shape, or pattern) that distinguishes it from sibling timers at a glance, without depending on the user reading name or time text. The cue shall be stable for the timer's lifetime. (Scenario 5)
- **FR-4.3** The lock-screen surface shall show at most one timer at a time. The selection rule (earliest end date, deterministic tiebreak) is documented in Scenario 6. (Scenario 6)
- **FR-4.4** When no running or paused timer remains, the lock-screen surface shall end. The user shall never see a lock-screen timer that no longer exists. (Scenario 6)
- **FR-4.5** The lock-screen surface shall update frequently enough that the user perceives time advancing without unlocking the phone. (Scenario 6)
- **FR-4.6** Each timer shall carry enough identity metadata — at minimum the camera slot it was started from, its film selection (if any), and the exposure-source kind that produced it — to let the user associate it with the intended camera, shot, and exposure. Identity metadata is captured at start time and shall not drift across the timer's lifetime even when the active camera slot or active film selection later changes. (Scenario 5; Persona 1.3)
- **FR-4.7** A timer started without a calculator-bound source — the *manual* path, used when an external precomputed shutter is supplied — shall not inherit camera-slot, film, or exposure-source identity from whatever is active at start time. The presentation layer falls back to a generic basis label rather than borrowing the active slot's identity. (Scenario 5; Persona 1.3)

### 3.5 Persistence

- **FR-5.1** Timer state (running / paused / completed information needed for the state machine) and timer presentation metadata (the name, the basis-summary line, and the LIFO insertion order the user sees) shall both survive an app restart. (Scenario 7)
- **FR-5.2** The calculator context — selected film, exposure scale token, base shutter, ND, and Target Shutter duration when set (FR-9.1, FR-9.5) — shall survive an app restart so the user does not redo the picker on every interruption. The exposure scale token is recorded so a future Settings preference can carry the user's prior choice across an upgrade rather than overwriting it. (Scenario 8)
- **FR-5.3** Persisted shapes shall evolve only via backward-compatible additions. A snapshot written by an older release of the app must continue to restore correctly under the current release; in particular, status tokens that older releases used must continue to be accepted on read. (Scenario 7)
- **FR-5.4** A running timer whose end date has already passed during the app's downtime shall restore as completed, with the original end date as the completion timestamp — not the moment of restoration. (Scenario 7 boundary)
- **FR-5.5** A persisted paused timer whose freeze metadata is missing or inconsistent shall be treated as corrupted input. The system shall surface such an entry as completed rather than fabricating a plausible-looking timestamp. (Scenario 7 boundary)
- **FR-5.6** On restore, a film selection whose id is no longer present in the catalog shall be dropped silently. The system shall write a clean snapshot back so subsequent reads are not confused. (Scenario 8 boundary)

### 3.6 Calculator screen and workspace

- **FR-6.1** Calculation and timer execution shall live on a single primary surface. The user shall not navigate to a separate "timer screen" to monitor a running exposure. (Scenario 3, 5)
- **FR-6.2** The primary surface shall adapt to the device's vertical room without rearranging its conceptual structure: the same elements are present at every density, only the spacing changes. (Scenario 1)
- **FR-6.3** The workspace surface shall offer the user two distinct presentations — a glanceable summary that prioritizes the calculator above, and an expanded view that prioritizes the timer list. Intermediate states are out of scope. (Scenario 3, 5)
- **FR-6.4** The workspace surface shall coexist with the calculator without obscuring it; the user can adjust calculator inputs while a timer runs without dismissing or moving the timer surface. (Scenario 3, 5; placement is a design choice, not a requirement.)
- **FR-6.5** The reciprocity details surface shall present its sections in a fixed order — *Profile / source authority* first, then *Formula or Reference data*, then *Graph*, then *Sources*. The order communicates that the trustworthy guidance comes from the data, not from the visual aid. (Scenario 2)

### 3.7 Orientation and inputs

- **FR-7.1** The app shall lock orientation so the photographer can hold the phone in a single grip while metering and adjusting. The current release supports portrait only. (Persona 1.1)
- **FR-7.2** Base shutter and ND shall be entered through controls that snap to valid values. Free-text numeric input is not accepted, so a typo cannot put the calculator into an unphotographic state. (Scenario 1)

### 3.8 Camera slots

- **FR-8.1** The system shall expose multiple camera slots within a single shooting session. The supported range is two to four slots; configurations outside that range are not part of the shooting workspace's scope. (Persona 1.3; out-of-scope for the inventory case is recorded in §5)
- **FR-8.2** Each camera slot shall preserve its own calculator state — workflow mode (digital vs. film), selected film and active reciprocity profile (when film workflow), base shutter, ND, exposure scale, the most recently derived reciprocity result, and the slot's Target Shutter state (FR-9.1). Slots are independent: a calculator change made on the active slot — including enabling, disabling, or editing the Target Shutter — shall not propagate to inactive slots. (Persona 1.3; Scenario 1, 2)
- **FR-8.3** Switching the active slot shall preserve every inactive slot's calculator state untouched. The transition shall not invoke any "reset" path on the calculator, the film selection, or the reciprocity result; the active-input set is replaced, not mutated. (Persona 1.3)
- **FR-8.4** The user shall be able to switch the active camera slot from the main shooting workspace through a single, glanceable affordance — not a settings detour. The exact affordance (paged TabView, segmented control, swipe gesture, or other) is a design decision; the requirement is that the switch is one gesture away from the calculator. (Persona 1.3)
- **FR-8.5** Each camera slot shall expose enough identity information — at minimum a stable id and a human-readable display label — for the user to associate calculator state, timers, and (eventually) record-system handoffs with the intended camera. The stable id is independent of the display label and shall not change when the user renames the slot. (Persona 1.3; complements FR-4.6 / FR-8.7)
- **FR-8.6** Camera-slot session state — the active slot id, every slot's preserved calculator state (including the slot's Target Shutter duration when set, FR-9.5), and any photographer-supplied custom slot labels — shall survive an app restart on the same terms as the calculator working context (FR-5.2). Persisted slot state shall evolve only via backward-compatible additions (NFR-S.2); a snapshot written by an older release that did not yet record a custom slot label or a slot Target Shutter shall continue to restore correctly, with the missing fields treated as absent. (Persona 1.3; Scenario 8)
- **FR-8.7** The user shall be able to rename a camera slot's display label to a photographer-supplied value, and shall be able to reset a renamed slot back to the canonical *Camera N* default. The rename affordance shall live on the slot title in the main shooting workspace, not behind a settings detour. (Persona 1.3)
- **FR-8.8** Empty or whitespace-only rename input shall be treated as a reset request rather than persisted as a blank label. A rename shall not modify the slot's stable id, calculator state, film selection, reciprocity result, any other slot's state, or the slot label captured on any timer that started before the rename. (Persona 1.3 boundary; complements FR-4.6 / FR-8.5)

### 3.9 Target Shutter

- **FR-9.1** The app shall support an optional Target Shutter workflow for comparing a desired final exposure duration against the current calculated result. (Persona 1.1; Scenarios 1, 2)
- **FR-9.2** In non-film workflow the comparison value shall be the Adjusted Shutter; in film workflow with a quantified corrected exposure the comparison value shall be the Corrected Exposure. In film states where no quantified corrected exposure exists, the system shall not present a fabricated comparison. (Scenarios 1, 2; complements FR-2.4)
- **FR-9.3** The target duration shall remain fixed while base shutter, ND, film selection, or reciprocity policy results change; only the comparison value updates. Editing the target is the only way to mutate it. (Scenarios 1, 2)
- **FR-9.4** The user shall be able to start a timer from the Target Shutter. A timer started this way shall use the target duration itself as its duration and shall carry a distinct exposure-source identity that keeps it distinguishable from Adjusted Shutter and Corrected Exposure timers across the timer's lifetime (extends FR-4.6). (Scenarios 3, 5)
- **FR-9.5** Target Shutter state shall be scoped per camera slot (extends FR-8.2). Switching the active slot shall replace the target along with the rest of the slot's inputs; an inactive slot's stored target shall not surface on another slot, and per-slot persistence shall not be seeded from session-global last-used target memory. (Persona 1.3)

---

## 4. Non-functional requirements

### 4.1 Determinism

- **NFR-D.1** Reciprocity evaluation, exposure calculation, and timer state-machine transitions shall be deterministic functions of their inputs. The current time is always supplied by the caller, never read from an ambient source inside the evaluator. The same input shall always produce the same output.
- **NFR-D.2** Persisted formats shall round-trip without loss — encoding a snapshot and decoding it back shall produce a value indistinguishable from the original.

### 4.2 Type safety

- **NFR-T.1** Illegal state combinations shall be unrepresentable. A reciprocity result cannot simultaneously be quantified and limited-guidance; a timer cannot simultaneously be running and paused. Where the language supports it, this is enforced at compile time.
- **NFR-T.2** Once an integrity invariant has been raised from a runtime check to a structural one, code patterns that would silently lower it back to a runtime check shall be blocked from re-entering the codebase. The mechanism (lint, code review, type-system feature) is a downstream choice; the obligation is that the regression cannot land unnoticed.

### 4.3 Architectural fitness

- **NFR-A.1** Production code shall not detect whether it is running under tests. The seam between production and test collaborators is dependency injection, not runtime branching.
- **NFR-A.2** Concerns that belong to a specific external surface (lock-screen widget, notifications) shall not leak into the view model. Each external surface has a dedicated owner.
- **NFR-A.3** Feature-scoped state shall be partitioned so no two features depend on each other directly. Cross-feature wiring is the responsibility of a composition seam. (The current decomposition is described in `docs/architecture/Architecture.md`.)
- **NFR-A.4** A view shall observe at most one feature's state directly. Cross-cutting display state is composed at a higher seam.

### 4.4 Verification

- **NFR-V.1** Domain and policy logic shall have unit-test coverage that materially detects regressions on the values the user sees. The numeric target is recorded in `docs/verification/Strategy.md`.
- **NFR-V.2** Type-driven changes (reciprocity result form, timer state representation) shall be guarded by mechanisms that prove the externally observable behavior is unchanged across the change.
- **NFR-V.3** Cross-cutting display state — what the calculator screen shows in each user scenario — shall be locked so an internal restructure cannot silently alter what the user sees.
- **NFR-V.4** Cross-platform parity fixtures shall be consumed by the iOS test suite so a fixture mutation surfaces against the runtime immediately, not at port time.

(Verification mechanisms are described in `docs/verification/Strategy.md`.)

### 4.5 Performance

- **NFR-P.1** A single reciprocity evaluation shall fit comfortably within the interactive frame budget on supported devices. Re-measurement is required when the dataset grows by an order of magnitude or a new estimation family is introduced.
- **NFR-P.2** The user-input live preview shall not stutter on the launch catalog or any catalog of comparable size.

### 4.6 Persistence stability

- **NFR-S.1** Storage locations for persisted state are stable contracts. Renaming a storage location is a breaking change that requires explicit migration consideration.
- **NFR-S.2** Persisted shapes evolve only via backward-compatible additions. The decoder accepts older shapes; the encoder may stop writing a deprecated field but a previously-written snapshot must still restore correctly.

---

## 5. Out of scope (current release)

The product intentionally excludes:

- Aperture and ISO controls in the variable section. The four-variable model from wiki 3866625 is reserved for a future Epic; the current release is base-shutter + ND only.
- Free-text shutter input.
- A user-facing exposure scale selector. The shipping calculator runs only on the 1/3-stop scale; a Full / 1/2 / 1/3 stop preference is reserved for a future Settings surface (see [Calculator Spec](../specs/Calculator.md) §1.4).
- Dropping a film selection by tapping outside a sheet without explicit confirmation. The "Clear" affordance is the only way to remove a selection.
- Timer queueing / chaining (start B when A finishes). Multi-timer is independent timers running in parallel, not a sequence.
- Studio strobe / flash duration modes.
- Video mode / cinematography.
- Cross-device sync. Each phone keeps its own catalog and persisted state.
- TCA / Redux-style global stores.

---

## 6. Open questions and reserved decisions

These are not requirements — they are points where the wiki / tickets reserve a future decision. Listed here so they don't drift into implicit requirements.

- **User-defined films.** Wiki 15138817 lists user-defined films as a future validation target; the entry/edit UX, validation rules, and persistence boundary are not specified.
- **Multi-profile per identity.** The domain reserves the ability to attach multiple profiles to one identity, but the launch dataset ships one profile per identity and the active-profile selection rule is not pinned.
- **Color correction metadata.** Velvia-style "M color correction" is mentioned in wiki 15138817 but has no schema entry yet.
- **Android port.** A future Android port is anticipated and shared test-fixture material is being curated for cross-platform parity, but the Android codebase itself is not in scope for the current release.
- **Aperture / ISO variable model.** Wiki 3866625 proposes a four-variable derivative model; the current release does not implement it.

---

## 7. Living document

This file is the *requirements* layer. It sits between the user-need ground truth (the wiki problem statement) and everything downstream of requirements. References to downstream documents (architecture, specs, verification) are navigational only. Update triggers:

- A new user scenario is added, or a scenario is closed (e.g. multi-profile selection ships).
- A new functional requirement is introduced or an existing one is retired.
- A non-functional requirement threshold changes (e.g. coverage target raised, perf budget tightened).
- An open question (§6) is resolved.

Each update shall cite the wiki page or PR that drove it.

---

## 8. Sources of intent (reference)

The product intent is anchored in the wiki. For implementation and
conflict resolution, follow the source-of-truth order in `AGENTS.md`;
the wiki references below are supporting product-intent sources.

- Wiki 3244033 — 사진가용 타이머 앱 — 문제 정의 (the seven problems this app addresses)
- Wiki 3375105 — 제품 방향 초안 (product direction)
- Wiki 3866625 — 화면 흐름 초안 (single screen unifies calculation and execution)
- Wiki 16482307 — Film Selection and Reciprocity Calculator UI (workflow direction, terminology)
- Wiki 9601025 — Bottom Sheet UI Architecture (current workspace shell implementation)
- Wiki 8847362 — Floating Timer Dock UI Design (current multi-timer surface implementation)

These are *reference material*, not normative. The seven problems from wiki 3244033 are the user-need ground truth that every requirement traces back to.
