# Timer Spec

**Domain**: Countdown timer lifecycle, persistence, completion notification, and lock-screen surface.

This document is a behavior contract for the timer runtime. It is platform-neutral but notes platform constraints where the intent depends on a platform feature (notification scheduling, Live Activity).

---

## 1. State machine

### 1.1 States

A timer is in exactly one of three states at any time:

- **running** — actively counting down; remaining time decreases with wall clock.
- **paused** — frozen; remaining time does not change.
- **completed** — terminal; remaining time is zero. Cannot transition out.

A timer's representation shall carry exactly the fields meaningful for its current state: running carries the expected end time, paused carries the frozen remaining duration and the paused-at instant, completed carries the recorded completion timestamp. There are no nullable siblings sharing a record across states; an *invalid* combination (e.g. a running timer with a paused-at instant) is therefore not representable.

### 1.2 Transitions

```
   ┌──────────┐  pause   ┌────────┐
   │ running  │ ───────▶ │ paused │
   │          │ ◀─────── │        │
   └──────────┘  resume  └────────┘
        │
        │ wall clock reaches end
        ▼
   ┌──────────┐
   │completed │   (terminal)
   └──────────┘
```

The only legal transitions are: `running ⇄ paused` and `running → completed`. **paused → completed** is not a direct transition; a paused timer must be resumed before it can complete. Completed is terminal: no transition leaves it.

A timer's `duration` is set at creation and is positive and finite. The system shall reject creation with non-positive, non-finite, or `NaN` duration values.

### 1.3 Snapshot at creation

When a timer is created, the calculator's current result is snapshotted into the timer's metadata: shutter value, ND stops, film identity (if any), reciprocity result. Subsequent calculator changes shall not alter the snapshot. Each timer carries its own creation-time snapshot.

### 1.4 Timer identity

Every timer carries an **identity** — a small bundle of associations describing *which shot* the timer belongs to. Identity is captured at start time and is independent of the runtime state machine (§1.1) and the time-semantics layer (§2).

**Composition.** A timer's identity is the union of:

- the **camera slot** it was started from (active-slot id and the human-readable slot label as it stood at start time, see [Requirements](../requirements/Requirements.md) §3.8 / FR-8.5);
- a **film descriptor** — the canonical stock name and any active profile qualifier when a film was selected, otherwise the explicit *No film* descriptor that signals digital workflow;
- the **exposure source** that produced the duration.

**Exposure-source categories.** The defined sources are:

- *digital result* — non-film calculator (no film selected); timer started from the ND-adjusted output shutter.
- *film-adjusted shutter* — film workflow; timer started from the Adjusted Shutter row.
- *film-corrected exposure* — film workflow; timer started from the Corrected Exposure row.
- *target shutter* — reserved for the Target Shutter workflow described in [Requirements](../requirements/Requirements.md) Persona 1.1 / Scenario 1 boundary; surfaces a distinct identity so a target-shutter timer remains distinguishable from adjusted and corrected timers.
- *manual* — an external precomputed shutter supplied outside the calculator. A manual timer **does not** capture calculator identity: it carries no camera slot, no film descriptor, and no calculator-bound exposure source, and its presentation falls back to a generic *Manual timer* basis label rather than borrowing the active slot's identity. (FR-4.7)

**Capture rule.** Identity capture happens once, at start time. The captured values are frozen on the timer; they are not re-derived from runtime state and they are not overwritten when the user later switches the active camera slot, renames a slot, swaps the active film, or re-picks a profile.

**Stability across timer states.** Identity is invariant across the timer's lifetime. The same identity bundle accompanies the timer when it is *running*, *paused*, *completed*, *reordered* within the workspace, *focused* by the user, *inspected* in the expanded view, or *restored* from persistence. State-machine transitions (§1.2) do not mutate identity.

**Display vs. data.** Identity is data; *how* the workspace renders camera, film, and source as a card label or accessibility string is a presentation concern documented in [UI Spec](UI.md). The data shape of identity is the contract; presentation strings can change without breaking it.

---

## 2. Time semantics

### 2.1 Remaining time

Remaining time is computed, not stored, and depends on state:

- **running** — `remaining = endDate − now`, clamped to `[0, ∞)`.
- **paused** — frozen at the value captured at the moment of pause.
- **completed** — exactly zero.

Reads of remaining time and status shall come from a single source. UI layers shall not snapshot or re-derive these independently; they read from the runtime model.

### 2.2 Tick

Running timers are evaluated against wall clock on a periodic tick of approximately 100 ms. The tick:

- recomputes remaining time for every running timer,
- transitions any timer whose remaining time has reached zero (within a small tolerance ε that protects against floating-point edge cases) to `completed`,
- publishes a current-date stream so subscribed UI redraws.

The tick shall not rebuild the calculator workspace, the calculator's variable section, or any non-timer surface. Only timer display state updates. (Wiki 8880129)

### 2.3 Resume preserves remaining time

When a paused timer is resumed, its frozen remaining time becomes the basis for a new `endDate = now + remaining`. The original `duration` is unchanged; only the `endDate` shifts forward. Pausing immediately re-pauses freezes the new remaining time.

---

## 3. Persistence and restoration

### 3.1 Snapshot persistence

The runtime shall persist the full timer collection across app termination. The persisted form is split into two parts so the runtime split mirrors the layered architecture:

**Per-timer runtime snapshot** — captures everything needed to reconstruct the timer's runtime state:

- **identity** — preserves stable id so cards and actions keep targeting the same item.
- **status** — selects the correct restore rule (running / paused / completed). `paused` here means a frozen, resumable state, not a terminal stop.
- **original duration** — preserves the timer's intended target for display and elapsed calculation.
- **creation time** — preserves provenance and supports stable reconstruction.
- **expected completion time** — lets running timers reconcile against wall clock on relaunch (running status only).
- **paused remaining duration** — keeps paused timers frozen across app-gone time without consuming wall clock (paused status only).
- **paused-at time** — preserves paused-state context shown in UI (paused status only).
- **completed-at time** — preserves the final completion timestamp (completed status only).

**Per-timer display metadata snapshot** — captures display-only state, persisted separately from runtime state so the layer boundary is preserved on disk:

- a **next-order counter** at the collection level — keeps newly created cards ordered after restored cards.
- per-timer **id, order, display name, and basis summary** — preserves card ordering and labeling across relaunches.

The persisted form must round-trip: encoding then decoding shall yield an equivalent collection. An empty collection shall remove the persisted blob entirely (rather than write an empty payload).

The on-disk schema is independent of runtime representation. The persisted record uses a flat shape — a status discriminator alongside the per-state fields above — and the encoder writes that shape regardless of how the runtime represents the state. The decoder reconstructs the appropriate runtime case from the persisted fields.

### 3.2 Backward-compatible status decoding

The decoder shall accept both `"stopped"` and `"paused"` as equivalent paused-state tokens. The encoder shall write only `"paused"`.

### 3.3 Restoration logic

Restoration occurs once at app start, not on subsequent reactivation. For each persisted timer:

- **running** — if `now ≥ endDate − ε`, the timer is restored as `completed` (its end time has passed during termination); otherwise it remains `running` and its tick resumes.
- **paused** — restored as `paused` with its frozen remaining time intact. Wall clock during termination is irrelevant.
- **completed** — restored as `completed` with `endDate` set to the recorded completion time. If a recorded completion time is missing, fall back to the timer's `startDate + duration`.

Restoration shall not fire completion alerts, push notifications, or any user-facing feedback. It is a state recovery only.

### 3.4 Reactivation reconciliation

When the app returns to the foreground, the runtime shall reconcile any running timer against wall clock and update its state if it has reached completion during the inactive period. Completion alerts (sound, haptic) shall not be triggered by reactivation; they fire only via the foreground tick when the user can perceive them.

---

## 4. Completion notification

### 4.1 Foreground feedback

When a timer transitions to `completed` while the application is active and in the foreground, the system shall play a short audio cue and a haptic. Each transition shall produce exactly one cue and exactly one haptic; reactivation-triggered completion shall not produce a cue.

### 4.2 Background and lock-screen delivery

For timers running while the app is in the background or the device is locked, the system shall schedule a local notification at each running timer's expected completion time. The schedule is keyed deterministically by timer identity so:

- creating a timer schedules its notification,
- pausing or removing a timer cancels its notification,
- resuming a timer reschedules at the new completion time,
- a timer transitioning to `completed` cancels any still-pending request.

Duplicate scheduling for the same timer identity shall not occur.

---

## 5. Lock-screen surface

The system exposes a single representative running timer to the lock screen at any time, via the platform's Live Activity facility.

### 5.1 Representative selection

The representative timer is the running timer with the **earliest expected completion time**. Ties shall be broken deterministically (e.g. by stable identity) so the same timer is selected across re-evaluations. If no timer is running, the lock-screen surface shall show a "no active timer" presentation rather than stale data.

### 5.2 Continuity

When the app becomes active, the system shall resolve the existing lock-screen surface rather than recreate one. Adding a timer, completing a timer, or relocking shall keep the same Live Activity instance updating, not spawn parallel activities.

### 5.3 Refresh cadence

The lock-screen surface refreshes its visible time at approximately 1 s cadence. The widget rendering layer is responsible for this refresh; the runtime publishes the target completion time once per relevant change.

---

## 6. Display ordering

The runtime makes one ordering decision; UI layers shall consume it without re-sorting.

- **Active group** — running and paused timers in one stable ordering domain. The ordering policy is **LIFO by creation**: the most recently created timer is first. Running and paused are not separated within this group; both belong to "active".
- **Completed group** — completed timers, sorted by completion time descending (most recent first). The completed group is presented behind the active group.

Compact and expanded surfaces shall use the same ordering. The selected/focused timer (when one is selected) does not reorder; it is highlighted only.

---

## 7. Forbidden patterns

The system shall **not**:

1. Mutate a created timer's metadata snapshot in response to calculator input changes.
2. Maintain a separate copy of timer state inside any UI surface (dock, sheet, overlay, list). All surfaces are read-only projections of the same runtime source.
3. Rebuild the calculator workspace on tick. Tick affects only timer-display state.
4. Run timer state mutation logic inside view-builder code paths. The runtime owns mutation; views only read.
5. Collapse `CalculatorState` and `TimerRuntimeState` into a single mutable structure. Calculator state is an immutable creation-time snapshot; runtime state holds elapsed/paused/completed.
6. Fire completion sound/haptic on app reactivation.
7. Schedule duplicate completion notifications for the same timer identity.
8. Show a lock-screen Live Activity for stale state after all timers have stopped.
9. Allow remaining time to read inconsistent values across UI surfaces. Single source of truth.

---

## 8. Drift and open questions

- **Completed timer retention.** Wiki 8847362 says completed may be limited to "recent items only"; no concrete retention threshold is decided.
- **Selection model for multi-timer operations.** Wiki 9601025 deliberately defers a strong selection model. There is no spec for multi-select, batch actions, or cross-timer linking.
- **Detent thresholds for the bottom sheet** (compact 98 pt + ND reserve 132 pt; large 560 pt; 92 pt up-drag and 64 pt down-drag) are documented in [UI Spec](UI.md) §4.
- **Notification grouping and audio policy.** No spec defines whether multiple background completions within a short window should group, or whether the audio cue varies by timer kind.
- **Live Activity test coverage.** Wiki 19103745 notes that ActivityKit and notification integration tests are missing. The lock-screen behavior is governed by the contract in §5 but not yet verified against system-level integration paths.
- **Pause-during-completion race.** No explicit spec for "user pauses while the runtime is mid-completion-evaluation"; behavior emerges from the tick ordering. Worth clarifying.
- **Notification copy.** No spec for the body text of the local notification beyond "this timer completed".

---

## 9. Sources of intent (reference)

These are *reference material*, not normative.

**Wiki (Confluence pages cited by page id)**
- 8847362 — Floating Timer Dock UI Design (display policy, ordering, dock states, destructive-action placement)
- 8880129 — Floating Timer Dock Architecture (state separation, projection-over-copying, forbidden patterns)
- 9568257 — Bottom Sheet UI 기획 초안 (compact / expanded UX, deferred selection model)
- 9601025 — Bottom Sheet UI Architecture 설계 초안 (layer split: domain / presentation / view)

