# PTIMER-199 Execution-Ready Task Spec — Stack up to four standard filter values

Ticket-scoped delivery artifact (expected to disappear with the
ticket, per the `PTIMER-<n>-` filename convention).
Sources: PTIMER-199 ticket, ChatGPT UX agreement (2026-07-15 session),
codebase analysis of ios/ and android/ at main d7755e02.

---

## 1. Goal

Let the user stack one to four standard ND filter wheels on the main
shooting screen. Each wheel selects from the existing standard value
set (integer stops 0–30 plus fractional presets 6.6 / 7.6 / 16.6);
the values are summed into one effective filter value in canonical
stops and fed to the existing exposure calculation. The combined
value can never exceed the existing 30-stop total limit. The
single-filter workflow is preserved: with one wheel, the existing
picker, calculation, and layout behavior remain unchanged except
for the agreed stack-discoverability affordance (the tappable edge
Add control, §4.2).

Success criterion: with two or more wheels, Adjusted Shutter equals
`base × 2^(sum of wheel stops)`; with one wheel, every existing
calculation and interaction test remains unchanged, except for the
agreed edge Add control.

## 2. Non-goals / out of scope (from ticket)

- Physical filter inventory, "My Filters", user-named filters
  (PTIMER-221).
- Restricting duplicate values in a stack (same value on multiple
  wheels is allowed).
- Filter classification (ND / CPL / color), purchase recommendations.
- Changing canonical calculator storage away from stops.
- Per-wheel notation selection (notation stays app-global).
- A dedicated accessibility large-text REDESIGN of the wheel row
  (e.g. an alternate vertical layout for accessibility sizes) is a
  separate ticket. This does NOT waive the baseline usability gate
  in §11 R2: the compressed row must remain operable and readable
  at currently supported text sizes, or the work stops and
  escalates. Known truncation, indistinguishable values, or
  shrunken-below-usable touch targets are merge blockers, not
  follow-up notes.

## 3. Protected areas (do not modify)

- `ExposureCalculator.calculate` — signature, math, snap-to-full-stop,
  `stabilityEpsilon`. Summation happens ABOVE this API; it continues
  to receive one `NDStep`.
- `ReciprocityCalculationPolicyEvaluator`, confidence presentation.
- Timer runtime semantics.
- Existing persistence keys and the meaning of existing snapshot
  fields (new fields are additive; see §7).
- `NDNotationFormatter` value/label policy (per-wheel display reuses
  it unchanged; the Total overlay is always plain stops and does not
  extend the commercial-label table).

## 4. Confirmed UX behavior (agreed with ChatGPT — do not re-litigate)

### 4.1 Layout

- One horizontal row: `Base : ND : ND : ND : ND`. Base Shutter is
  always the leftmost column; ND wheels number 1–4 to its right.
- No vertical stacking of wheels. No separate stack-editor sheet.
- No mode toggle. "Stack" is simply the state of having ≥ 2 wheels.
- As wheel count grows, ND column widths and fonts step down so the
  row stays on one screen. Base Shutter keeps a wider column than
  the ND wheels; at 3+ wheels the Base column caps at roughly half
  its two-column width with condensed values (decided 2026-07-15).
- WHEEL FONT RULE (user rule, 2026-07-15): every wheel on the main
  screen — Base Shutter and all ND wheels — always renders its
  values at the SAME font size for a given wheel count. Density
  steps apply to the whole row together, never to one column alone.
- With 1 wheel the current appearance is preserved, including the
  in-wheel unit band — unchanged except for the agreed
  stack-discoverability affordance (edge Add control, §4.2).
- Per-wheel unit band at ≥ 2 wheels: DECIDED (R2 captures,
  2026-07-15) — the band's unit text is DROPPED at 2+ wheels. The
  keep-first verification showed the fixed band metrics push values
  out of the narrowed columns entirely (M1a capture evidence);
  values center instead, and the unit appears in the Total overlay
  and header. At 1 wheel the original band, including its unit,
  is unchanged.
- The ND header row spans the whole ND group:
  `ND Filter [Stops | OD | ND]` (notation toggle unchanged,
  app-global).

### 4.2 Add / remove wheels (v2, user field-test decision 2026-07-15)

Supersedes the option D long-press menus: 0-stop wheels are
ephemeral and self-cleaning; removal needs no menu surface. The
0-stop wheel's ORIGIN is not tracked — a wheel freshly added
through the Add control and a wheel the photographer zeroed out
follow the same rules (this deliberately reverses the earlier
"wheels added at 0 are never auto-removed" decision).

#### 4.2.1 Add — edge Add control

- No separate add/remove button row and no persistent remove
  button.
- The trailing-edge hint is a real, tappable control, not
  decoration: rendered small (dim ghost column with a "+" glyph)
  with a touch target of at least 44 pt (iOS) / 48 dp (Android),
  borrowing the wheel row's full height.
- Tap appends one new wheel at the right, always starting at
  0 stops (the calculation result must not change on add).
- AVAILABILITY (C1): a wheel can be added only while
  `wheel count < 4` AND the NEW wheel's allowed ladder contains at
  least one value greater than 0. A remaining budget above zero is
  NOT sufficient — if the ladder truncated to the remaining budget
  is `[0]` only (e.g. sum 29.6 leaves 0.4, below every integer and
  preset), the control hides. It reappears when the condition
  holds again.
- Exposed to VoiceOver / TalkBack as "Add filter" (same
  availability rule).
- Capture checkpoint R5: must read as an add control — not as a
  horizontal scroll indicator and not as a real wheel.

#### 4.2.2 Automatic cleanup of 0-stop wheels

A CLEANABLE 0-stop wheel is a 0-stop wheel whose removal would
change the stack while preserving the minimum-one-wheel rule.

- A0 — BUDGET-SATURATION IMMEDIATE CLEANUP: when, after a commit
  OR a state re-examination (restore, slot activation, slot
  switch — see A3), the sum of the non-zero wheels reaches the
  30-stop cap, the
  remaining 0-stop wheels are cleaned up IMMEDIATELY, with no
  grace period ([29, 1, 0, 0] → [29, 1]; [30, 0] → [30]). The
  minimum-one-wheel rule still applies.
- A1 — IDLE CLEANUP: a 4-second timer starts when a cleanable
  0-stop wheel comes to exist, and restarts in full on committed
  stack writes and wheel-identity re-syncs. When it fires while the
  machine is busy, nothing is cleaned and a full grace period is
  waited again (see A3) — raw interaction defers cleanup through
  that fire-time judgment, not by restarting the timer. Wheel
  origin is irrelevant.
- A2 — CLEANUP RULE: if at least one non-zero wheel exists, ALL
  0-stop wheels are removed; if every wheel is 0-stop, exactly one
  remains ([7, 0] → [7]; [7, 0, 0] → [7]; [0, 0, 0, 0] → [0]).
- A3 — FIRE-TIME JUDGMENT (architecture v2; replaces the earlier
  cancel/re-arm rule): the timer is only ever ARMED (whenever a
  cleanable 0-stop wheel exists) and judges AT FIRE TIME — cleanup
  executes only when no wheel is in motion and no finger rests on
  any wheel; otherwise the timer re-arms for another full grace
  period. Raw interaction never cancels the timer, so no
  interaction bookkeeping (and no touch-start signal) is required —
  disarm/re-arm remains part of structural transitions (reshaping,
  slot switch, Reset); a wheel still never vanishes under a finger
  or mid-scroll. Notation
  changes neither defer nor cancel the timer. Slot switches and
  Reset re-arm against the ARRIVING state.
- A4 — cleanup animates as fade + width collapse and persists the
  slot immediately afterwards.
- A5 — the 4-second grace period is a FIXED initial value (revised
  down from 5 s by user field feel; subject to later tuning). Not
  user-configurable.
- A6 — the pending flag and timer are transient session UI state;
  they are never persisted.

#### 4.2.3 Manual removal — overscroll-past-zero gesture

- B1 — ARM CONDITION: the gesture arms only when the touch BEGINS
  on a wheel already SETTLED at 0. Scrolling a wheel down to 0 and
  pushing it out are therefore always two separate touches — a
  fast scroll toward 0 can never delete in the same gesture.
- B2 — TRIGGER: accumulating downward overscroll past the 0 end of
  at least one row height (initial threshold), and RELEASING while
  past the threshold, deletes that wheel. Releasing below the
  threshold rubber-bands back — a no-op.
- B3 — one deletion at most per gesture (latch).
- B4 — the last remaining wheel is never deleted by the gesture
  (same minimum-one rule as cleanup).
- B5 — deletion uses the same fade + width-collapse animation
  grammar as automatic cleanup. Android (custom Compose wheel)
  renders the live "pushed off the screen" displacement while
  dragging; iOS (UIPickerView) approximates with a threshold
  haptic and the post-release collapse.
- B6 — the semantic rules (arm condition, threshold, latch,
  minimum-one) are shared across iOS and Android; feel (resistance
  curve, haptics, animation timing) follows each platform.

- While any OTHER wheel is still in motion, the overscroll release
  does not remove the wheel (removal would reorder positions under
  an active interaction); the 0-stop wheel is left to the normal
  cleanup rules at epoch close.

#### 4.2.4 Accessibility path

- VoiceOver / TalkBack custom actions on the ND group are the
  screen-reader user's removal path (timers and gestures are not
  accessible):
  - "Add filter" — availability per C1 (4.2.1).
  - "Remove empty filter" — available while a cleanable 0-stop
    wheel exists; performing it runs THE SAME cleanup rule as A2
    (all 0-stop wheels removed at once; one remains when every
    wheel is 0-stop), so a screen-reader user cleans up in one
    action instead of repeating it.

#### 4.2.5 Considered and not adopted

- LONG-PRESS MENUS (ND header, Add control): REMOVED by user
  product decision — the self-cleaning rules above eliminate the
  removal-menu need, and a hidden long-press surface was hard to
  discover in field use.
- Pinch add/remove: evaluated in the R1 spike and DISCARDED
  (discoverability, one-handed use, weak semantic link).
  Record: `docs/tasks/PTIMER-199-discarded-pinch.md`.
- Edge DRAG add/remove (dragging the hint inward): REJECTED
  (conflicts with the camera-slot pager's horizontal swipe).

### 4.3 Auto-sort

- Wheels sort descending by stops, 0-stop wheels always rightmost,
  equal values keeping their existing relative order (stable).
- Selections commit as ONE SET (interaction epoch): several wheels
  may be in motion at once (multi-touch, or a fling still settling
  while another wheel is grabbed). The epoch opens at the first
  touch and closes when EVERY wheel has settled. During the epoch
  the committed stack does not change: each wheel's selection is
  recorded per wheel, wheel positions and ladders stay frozen, and
  no cleanup (4.2.2) examination or removal runs — a wheel never
  reorders, reloads, or vanishes under an active interaction.
- While any trace of an interaction exists (an active touch, a
  recorded selection awaiting the set commit, or a live overlay
  value), the Add and Remove affordances are UNAVAILABLE — the Add
  control keeps its layout slot (wheels must not resize under a
  moving finger) but dims and ignores taps, and the commands refuse
  even when invoked directly.
- At epoch close the recorded selections apply in settle order; a
  selection that would push the total past the 30-stop limit is
  rejected and that wheel reverts to its previous value (reject,
  never clamp). Then the stack sorts once and cleanup re-examines
  once. A single-wheel interaction is simply an epoch of one: it
  commits and sorts at settle, exactly as before.
- Epoch selections persist at the set commit; selections still in
  flight are lost if the app terminates mid-epoch.
- A selection event for a wheel with no active user interaction is
  refused (screen-reader adjustments excepted): wheel pickers emit
  system-generated selection events — on attach, restore, and while
  wheels animate — and an unguarded one can silently overwrite a
  wheel's committed value.
- Whenever an idle wheel's visible selection diverges from its
  committed value (a rejected commit, a transient picker desync),
  the display re-synchronizes to the committed value. Never while
  that wheel is being interacted with.
- Never reorder while any wheel is being scrolled. Animate the
  reorder after the epoch closes.
- The epoch/set-commit machinery is realized by the v2
  architecture (see `PTIMER-199-nd-wheel-architecture-ios-v2.md`): an
  IDLE/SCROLLING/RESHAPING state machine with per-wheel unresolved
  tracking, an OWNED wheel picker whose delegate the app controls
  (a selection event outside a programmatic-change lock and under
  the current generation is a user selection by construction),
  input BLOCKED — not dropped — during the reshaping window, and
  generation tokens invalidating late callbacks. Wheel identity is
  a monotonically increasing integer starting at 101.
- Sorting never changes the effective sum or the calculation result.
- Reorder presentation (user-tested decision): each wheel carries a
  stable identity, and a reorder animates as wheels MOVING to their
  new positions (same duration/curve family as the removal
  collapse). The simpler first implementation — reassigning sorted
  values to fixed wheel positions — was field-tested and rejected:
  without positional motion the values appear to teleport, which
  startles at commit time. Android expresses the same semantics
  with key-based wheel identity.

### 4.4 30-stop structural enforcement

- Each wheel's selectable ladder = standard ladder truncated FROM
  THE TOP to `30 − (sum of the other wheels' committed values)`.
- Truncation from the top preserves remaining row indices, so the
  selected row never jumps on reload (verify on device).
- Fractional presets above the remaining budget drop out of that
  wheel's ladder naturally.
- Sibling ladders are recomputed ON COMMIT ONLY — never during a
  live scroll of another wheel.
- No clamp, no error state, no over-limit representation. Consistent
  with the current "not representable through the picker" spec
  philosophy.

### 4.5 Live preview

- The display-effective value = the sum, over all wheels, of each
  wheel's in-motion selection when it has one, else its committed
  value. Adjusted Shutter and all downstream results update live.
  With one moving wheel this reduces to today's rule (live wheel +
  committed others); with several moving wheels each contributes its
  own live value — the preview never flickers between wheels.
- Only an ACTIVE gesture drives a wheel's live preview: the window
  opens at touch-down (or row tap) on that wheel and closes at its
  commit or settle, so finger-up deceleration still previews.
  System-generated wheel events outside that window — attach,
  restore, wheels animating across during a reorder — never alter
  the live result or the Total.
- Derived actions taken mid-epoch (starting a timer from a result
  row) read the display-effective value.
- During a multi-wheel epoch the frozen ladders can transiently
  allow a combined selection above 30 stops; the display shows the
  actual transient sum, and the set commit resolves it by rejection
  (4.3).
- After the epoch closes: auto-sort may reorder, but the effective
  sum and results must not change.

### 4.6 Total overlay (transient, non-blocking)

- 1 wheel: no overlay, ever.
- ≥ 2 wheels: on any wheel value change or wheel add, show a
  translucent `Total 19 stops` overlay over the ND wheel group
  (above the selection band or top-center of the ND group — final
  position chosen from device captures so it never covers the
  selected values).
- Always expressed in stops (sums like 6.6 + 6.6 = 13.2 have no
  standard OD/ND-factor label).
- Updates live during scroll; fades out ~1–2 s after the last
  interaction; shows slightly longer right after a wheel add.
- Touch pass-through: the overlay never intercepts touches
  (iOS `.allowsHitTesting(false)`; Android non-clickable
  composable). Starting a new wheel interaction re-shows it.
- When the sum reaches exactly 30: show `Total 30 stops · Maximum`
  briefly.
- Accessibility: the total is ALWAYS part of the ND group's
  accessibility value regardless of visual state, e.g.
  "Four filters, total 19 stops".

### 4.7 Notation

- The Stops / OD / ND toggle stays app-global and applies to all
  wheels simultaneously. Per-wheel values render in the active
  notation via the existing `NDNotationFormatter`.

## 5. Platform order

**iOS first, then Android**, in this ticket, as separate sequenced
phases (user instruction 2026-07-15). Functional semantics must end
up identical (max 4, new wheel = 0 stops, descending sort with zeros
right, structural 30-stop limit, global notation, identical sum
math); the Add control's visual treatment, overscroll feedback,
and accessibility actions follow each platform's idiom. Shared golden fixtures keep calculation parity.

## 6. Domain and state design (iOS names; Android mirrors)

### 6.1 PTimerCore (Foundation-only)

New value type `NDFilterStack` (suggested; final naming may follow
review) in `ios/PTimerKit/Sources/PTimerCore/Exposure/`:

- Holds 1–4 `NDStep` entries in display order.
- `effectiveStep: NDStep` — sum of entries (Double addition of
  `stops`; use the existing third-stop/exact serialization helpers
  only at the persistence boundary, not for the sum).
- `remainingBudget(excluding index:) -> Double` =
  `30 − sum(others)`.
- Sorted-commit helper implementing §4.3 (descending, zeros last,
  stable).
- Invariant: every entry ≥ 0, sum ≤ `ExposureScale.maximumWholeNDStops`
  (+ existing epsilon discipline).

`ExposureScale`: add a ladder helper that returns
`shippingNDLadder` truncated to a maximum stop value (used per
wheel with the remaining budget). Reuse the existing ladder
construction; do not duplicate it.

`ExposureCalculator` unchanged. The model passes
`stack.effectiveStep` into the existing `calculate` path.

Snap-to-full-stop note: the existing gate
(`scaleMode == .fullStop && ndStep.isWholeStop`) now evaluates the
EFFECTIVE step. Sum of whole stops is whole, so single-wheel
behavior is untouched; a sum involving presets (e.g. 13.2) is not
whole and does not snap — same rule as today for a single preset.
Do not change the gate.

### 6.2 PTimerKit (model / view model / display state)

- `CalculatorModel`: replace the single canonical `ndStep` with the
  stack (1 entry = today's behavior). ONE meaning per accessor —
  never call-site-dependent:
  - `ndStep` (kept for compatibility) = the EFFECTIVE step (sum),
    everywhere, for every caller.
  - A separate accessor (e.g. `ndFilterSteps` /
    `filterStack.entries`) = the individual wheel values, in
    display order. UI that needs wheel 1 reads the array's first
    element explicitly.
  - With a single wheel the two coincide, which is what keeps
    existing single-wheel tests passing unchanged.
  Preserve `liveNDStep` semantics per §4.5 (live entry + committed
  others).
- `ExposureCalculatorViewModel`: published stack state; commands
  for adding a wheel, running the A2 cleanup, and the per-wheel
  gesture removal (names follow the implementation); each no-ops
  when unavailable, and the availability rules feed the
  accessibility actions and gesture handling; per-wheel commit +
  live-change entry points (wheel index + `NDStep`); sort-on-commit
  invocation; per-wheel picker ladders (budget-truncated); Total
  overlay display state (visible / text / emphasized-maximum /
  show-longer-after-add trigger token) — computed, not stored,
  following the `*DisplayState` convention. Overlay fade TIMING is
  view-layer ephemeral state; the view model only exposes the
  trigger + content.
- `CameraSlotCalculatorSnapshot` (runtime per-slot type): single
  `ndStep` becomes the stack (or gains a stack alongside; prefer
  replacing with stack of 1 to avoid dual sources of truth).
- Reset semantics: slot Reset returns to one wheel at 0 stops
  (current default), discarding extra wheels.

### 6.3 App layer (ios/PTimer)

- `ExposureWorkspaceMainLayoutStyle.swift`: extend the density
  system with a wheel-count-aware tier (fonts / column widths /
  unit-band visibility per 1–4 wheels). Base column wider than ND
  columns; ~50 pt per ND column at 4 wheels on 375 pt devices is
  the working target, subject to the capture checkpoint.
- `VariableSectionView` restructure: header row spans the ND group
  (`ND Filter [Stops|OD|ND]`); wheel row renders Base + N ND wheels;
  per-wheel `WheelPickerContinuousObserver` wiring (existing
  pattern, one per wheel).
- Edge Add control (§4.2.1): tappable trailing-edge element in the
  wheel row — plain SwiftUI Button, small visual, ≥ 44 pt touch
  target spanning the wheel row height; visible only while the C1
  availability rule holds.
- Automatic cleanup (§4.2.2): the view model owns the 4-second
  re-examination timer (transient, never persisted) and the
  budget-saturation immediate pass; wheels leave with the shared
  fade + width-collapse transition.
- Overscroll-past-zero gesture (§4.2.3): detected through the
  existing `WheelPickerContinuousObserver` pan hook — arm when the
  touch begins on a wheel settled at 0, accumulate downward
  translation past the end, threshold haptic, delete on release.
- Total overlay view: `.overlay(alignment:)` on the ND group,
  `.allowsHitTesting(false)`, fade animation + idle timer in the
  view layer.
- VoiceOver custom actions on the ND group (§4.2.4); group
  `accessibilityValue` includes the total per §4.6.

## 7. Persistence

`PersistentCameraSlotCalculatorSnapshot`
(`ios/PTimerKit/Sources/PTimerKit/Persistence/PersistentCameraSlotSession.swift`):

- Add an OPTIONAL additive field, e.g. `ndStack: [Entry]?`, where
  each entry reuses the existing lossless triple discipline
  (`ndStop: Int?` / `ndStopThirds: Int?` / `ndStopsExact: Double?`)
  as a small codable entry struct. Do not change existing fields'
  meaning or the store key.
- Write path: always write the stack array. The legacy scalar
  fields carry THE MAXIMUM stack entry, selected explicitly at
  write time (max over entries — NOT positional `stack[0]`), so
  the rule holds even if the array is momentarily unsorted (live
  state, future code changes). An older app version restoring the
  snapshot then degrades to a valid single filter instead of
  falling back to default (sum could be off-ladder, e.g. 13.2,
  which legacy validation would reject).
- Decode isolation (REQUIRED): a decoding failure of the new
  `ndStack` field must never propagate into a decoding failure of
  the rest of the snapshot. A malformed array, or any malformed
  entry inside it, is treated exactly as if `ndStack` were absent
  (decode the field failably — e.g. a lenient custom decode —
  rather than a plain `decodeIfPresent` that throws through).
  Restore then proceeds legacy scalar → defaults as usual.
- Restore path (`CalculatorContextRestorePlanBuilder`): if
  `ndStack` decoded → validate every entry against the standard
  ladder envelope ([0, 30], whole / preset-exact values only) AND
  the sum ≤ 30 (+ epsilon); ANY violation — structural or
  semantic — drops the whole stack and falls back to the legacy
  scalar path, then to defaults — matching the existing
  reject-don't-clamp philosophy. No partial recovery: restoring a
  subset would silently change the saved combination's sum. If
  absent → legacy single-filter restore, producing a 1-entry stack.
- Required corruption test cases (BOTH platforms):
  1. the array itself is malformed (wrong type);
  2. one entry has a wrong type;
  3. decodes cleanly but an entry value is off-ladder;
  4. entries individually valid but the sum exceeds 30.
  Each case must restore via legacy scalar → defaults, and the
  rest of the snapshot (base shutter, scale mode, film, …) must
  restore normally in cases 1–2.
- Legacy single-context snapshot (`PersistentCalculatorContextSnapshot`)
  stays untouched (migration source only).
- Display settings (notation) persistence unchanged.
- `docs/specs/DomainSchema.md`: document the new snapshot field.

## 8. Spec document updates (same ticket, English canon)

- `docs/specs/Calculator.md` §2.2: stack of 1–4 standard inputs;
  per-wheel ladder truncated to remaining budget; effective value =
  sum in canonical stops; total not representable above 30 by
  construction; single-input workflow unchanged. Keep the "no
  densified fractional ND picker" rule — sums may be fractional,
  picker values may not.
- `docs/specs/UI.md` §2.2: wheel row `Base : ND × 1–4`, edge Add
  control with the C1 availability rule, automatic 0-stop cleanup
  (A0–A6), overscroll-past-zero removal (B1–B6), accessibility
  actions (§4.2.4), auto-sort rule, transient Total overlay
  behavior (§4.6), unit-band visibility rule (as decided at R2),
  global notation across wheels.
- `docs/requirements/Requirements.md`: extend the relevant FR
  (FR-1.2 area) with the stacking scenario ("system shall" wording,
  scenario back-reference).
- `docs/specs/DomainSchema.md`: persistence schema addition (§7).
- Korean DOCUMENT translations under `docs/translations/` are
  human-owned. App UI Korean strings for this feature are in scope
  (user-approved).

## 9. Verification plan

### iOS (phase A)

- `PTimerCoreTests`: `NDFilterStack` sum / budget / sort / invariant
  cases incl. preset sums (6.6+6.6=13.2), budget truncation of
  presets, stable sort, zeros-right; ladder-truncation helper
  (top-truncation preserves prefix indices).
- `PTimerKitTests`: model/view model state — add/remove command
  availability, live-preview sum (live + committed), sort-on-commit
  result invariance, per-wheel ladders, overlay display state
  triggers, Reset semantics; persistence round-trip (stack write /
  restore, legacy scalar stores the explicitly selected maximum
  stack entry, absent-field legacy
  restore, invalid-stack rejection fallback, and the four §7
  corruption cases).
- App-hosted `PTimerTests` only if an OS-boundary surface needs it
  (prefer manual + unit seams). The Add control and accessibility
  actions are plain surfaces — testable at the package/UI level
  without OS-boundary hosting.
- Full verification = `swift test --package-path ios/PTimerKit` AND
  `xcodebuild … -testPlan PTimer test` (both, per repo rule).
- Manual capture checkpoints on simulator (existing capture naming
  convention `NN_<set-type>_<timestamp>.png` in scratch/):
  R2 4-wheel readability / accessibility gate / unit-band decision
  at 375 pt width — including the 3-wheels+Add-control row, which
  is as dense as 4 wheels; R3 no picker jump on ladder truncation;
  R4 overlay position; R5 Add control reads as an add control (not
  a scroll indicator, not a real wheel).

### Android (phase B)

- `android/core` unit tests mirroring the PTimerCore cases; golden
  fixtures extended at `shared/test-fixtures/` for stack-sum →
  effective-stops → result parity (iOS side adds the same fixture
  consumption in phase A so fixtures are authored once).
- `./gradlew test` and `./gradlew lint`; emulator verification on
  emulator-5554 (build, install, drive, screenshot) — no real alarm
  playback.
- Compose: Add control as a tappable trailing element
  (`minimumInteractiveComponentSize` 48 dp); overscroll-past-zero
  gesture with the live pushed-off feedback (§4.2.3). Avoid
  unrelated `SnapWheel` rewrites; changes required for the
  overscroll gesture are in scope. TalkBack custom actions merged
  into the existing `clearAndSetSemantics` group.

## 10. Sequencing — user-verifiable milestones

The sequence is organized as user-verifiable use-case milestones.
Each milestone ends in a state the user can exercise on a device or
simulator; each has a named verification.

Commit rule (review-mandated): commits are split by USER-TESTABLE
USE-CASE SLICES, not by technical layer. Do NOT stack standalone
Core → Model/ViewModel → UI → test commits; the domain and view
model changes a flow needs land INSIDE the commit (or short commit
pair) that completes that user flow. Staged step N/M commits remain
fine within a slice, converging to green at the slice boundary.

Pre-work (NOT a commit): R1 pinch investigation — COMPLETED
2026-07-15. Technical verdict was GO, but the pinch affordance was
DISCARDED for this ticket by product decision (option D, §4.2).
Full investigation record, evidence, and pitfalls:
`docs/tasks/PTIMER-199-discarded-pinch.md`. No milestone work
depends on it.

Milestone 0 (only if needed): behavior-invariant pre-refactor —
e.g. `VariableSectionView` / model seams reshaped to accept N
wheels while still rendering exactly one.
→ verify: full existing suite green; 1-wheel screen visually
unchanged (capture diff).

Milestone 1 — iOS in-session stack use-case, split into three
user-flow slices (persistence not yet included; the stack resets
to the legacy scalar on relaunch — any PR reviewed at this
boundary must say so explicitly in its description):

- M1a — "I can add and remove filter wheels": 1–4 horizontal
  wheels render and are individually selectable. M1a covers the
  add/remove SURFACES and interaction mechanics from §4.2 — the
  edge Add control, the 0-wheel cleanup timer shell, the
  overscroll gesture, and the accessibility actions — with minimal
  state (each wheel holds a value; sum/budget/sort may be
  placeholder). Budget-dependent final behavior from §4.2 — the C1
  availability rule and the A0 budget-saturation cleanup — lands
  with M1b, where real summation and per-wheel ladders are
  introduced. Includes whatever model/VM seams this flow needs —
  no standalone layer commits first. UI-level tests + captures
  (the Add control and accessibility actions are directly
  testable).
  Intermediate-state honesty: because summation lands in M1b, M1a
  and M1b share ONE user-verification boundary — M1a is not
  demoed, PR'd, or user-verified standalone while a multi-wheel
  selection would show a misleading Adjusted Shutter. Technical
  checks (suite + captures) still run at the M1a commit boundary.
  → verify (technical only): package suite green incl. unchanged
  single-wheel tests; R2 captures (readability, accessibility
  gate, unit-band decision); VoiceOver pass on add/remove. User
  verification happens at the M1b boundary.
- M1b — "the stack computes my exposure": real summation into the
  existing calculate path, live preview (live wheel + committed
  others), budget-truncated per-wheel ladders (30-stop structural
  limit), auto-sort on commit. The `NDFilterStack` domain type +
  ladder helper land here, inside this slice, with their tests.
  → verify: package suite green; golden fixtures authored +
  consumed; R3 capture (no picker jump on truncation).
- M1c — "the UI tells me what the stack is doing": Total overlay
  (§4.6), final density/font tuning (the Add control itself ships
  in M1a as the add path; its final visual treatment is confirmed
  here with R5).
  → verify: R4 + R5 captures; accessibility value includes the
  total; final R2 re-check at 4 wheels.

Milestone 2 — iOS save/restore use-case: the stack survives
relaunch and slot switching; corrupted or invalid stacks restore
safely (all four §7 corruption cases); Reset returns to
1 wheel · 0 stops.
→ verify: persistence round-trip + corruption tests green; manual
relaunch-restore procedure (docs/verification/RelaunchRestore.md)
extended and passed.

Milestone 3 — Android same use-case (phase B): the same user-flow
slices as M1a/M1b/M1c + M2 (add/remove flow, computation flow,
feedback flow, save/restore flow), each slice carrying its own
domain + state + Compose UI + tests — same no-layer-commit rule.
Covers domain mirror + golden-fixture consumption, controller/
state, persistence codec, Compose UI (row, Add control,
overscroll-past-zero gesture, TalkBack actions, overlay).
→ verify: `./gradlew test` + `lint` green; emulator-5554 build /
install / drive / captures (no real alarm playback); same
corruption cases.

Milestone 4 — docs, fixtures finalization, version:
- Golden fixtures for stack-sum parity are AUTHORED in M1b (iOS
  consumption) so Android consumes, not re-derives, them in
  milestone 3; this milestone only reconciles/finalizes.
- Spec doc updates (§8).
- Patch version bump (three files, read current values from
  `project.pbxproj` and `build.gradle.kts` first), own commit.
→ verify: docs cross-references single-rooted; version values
match in all three places.

PR: draft, user test steps included, ticket footer per commit
conventions.

## 11. Risks / open items

- R2 4-wheel readability + accessibility gate at ~50 pt columns on
  375 pt devices — capture checkpoint before finalizing fonts.
  HARD GATE: if operation or value identification becomes
  impossible at currently supported text sizes / accessibility
  settings, STOP and escalate — do not merge with known
  truncation, indistinguishable values, or unusable touch
  targets, and do not keep shrinking fonts if the fixed 4-wheel
  horizontal layout does not hold (that is a UX re-decision, not
  an implementation knob). The unit-band keep/drop decision is
  also made here (§4.1).
- R3 picker reload on ladder truncation — expected no-jump
  (top-truncation), verify on device.
- R4 overlay final position (above selection band vs top-center) —
  chosen from captures.
- R5 edge Add control — must read as an add control, not a
  horizontal scroll indicator and not a real wheel; verify from
  captures. User feedback (2026-07-15, from M1a/M1b captures): the
  first implementation rendered the control as wide as a wheel —
  shrink the visual to hint width (~24–28 pt) and recover the
  44 pt touch target from the surrounding card padding/gaps
  (M1c work).
- Drag-in add gesture (user suggestion 2026-07-15): reviewed and
  CLOSED — stays rejected with the edge-drag option (camera-slot
  pager swipe conflict); tap is the primary add path. Not an open
  item.
- Base Shutter unit glyph (decided 2026-07-15, user): at 3+ wheels
  the width-capped Base column HIDES the in-band "s" and renders
  condensed, centered values — confirmed as a product decision from
  the SE 375 pt captures (shutter values like "1/30" read
  unambiguously without the unit; the released width goes to the
  glyphs). At 1–2 wheels the original Base column, including "s",
  is unchanged.
- Korean strings for the new stack UI (Add control,
  overscroll/accessibility actions, Total
  overlay, accessibility value): user-approved scope exception
  (2026-07-15) — Claude-authored ko entries ship with the feature;
  the spec's human-owned clause is narrowed to the document
  translations under `docs/translations/`.
- Wheel-count density rule (user directive 2026-07-15): as wheels
  grow, per-wheel fonts AND paddings must both step down so values
  stay fully legible in the narrower columns — the M1c density
  tier covers font size, insets, and the minimum-scale floor
  together, not fonts alone.
- Accessibility large-text REDESIGN (alternate layout for
  accessibility sizes) — separate ticket; baseline usability is
  gated by R2 above, not deferred.
- Older-app downgrade reads the legacy scalar = the explicitly
  selected maximum stack entry (information loss by design;
  documented in DomainSchema).

## 12. Escalation triggers

- Affordance changes (e.g. the Add control's shape or placement,
  reintroducing any discarded gesture, or adding a new gesture
  beyond §4.2) are product decisions — do not
  improvise alternatives beyond §4.2 (option D) without
  escalating.
- R2 readability or accessibility gate fails at 4 wheels → UX
  revisit (wheel-count cap, layout change, or accessibility
  fallback is a product decision; do not merge a degraded state).
- Any pressure to touch `ExposureCalculator.calculate`,
  reciprocity, or timer semantics → stop, escalate.
- Test placement doubts → follow the PTIMER-174 rule (module-owned
  tests; app-hosted only for OS-boundary).
