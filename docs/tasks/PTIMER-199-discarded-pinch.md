# PTIMER-199 Discarded Idea — Pinch add/remove for the ND filter stack

Ticket-scoped record (expected to disappear with the ticket, per
the `PTIMER-<n>-` filename convention). Companion to
`docs/tasks/PTIMER-199-task-spec.md` §4.2, which adopted option D
(tappable edge Add control + ND header long-press menu) instead.

Status: DISCARDED for PTIMER-199 by product decision, 2026-07-15.
The R1 spike verdict was technically GO — the idea failed on
product grounds, not feasibility. Kept as a record so a future
ticket can revisit it without re-deriving anything.

---

## 1. The discarded design

Originally agreed UX (before option D):

- Pinch out on the ND wheel area: append one new wheel at the
  right, always starting at 0 stops. Max 4.
- Pinch in: remove one 0-stop wheel (rightmost; zeros are
  guaranteed rightmost by the auto-sort rule). Wheels holding a
  non-zero value are never removed. Min 1.
- One action per gesture (latch rule): a single pinch performs at
  most one add or remove — the action triggers once when the scale
  first crosses the dead-zone threshold, then latches until the
  gesture ends; a gesture that ends inside the dead zone is a
  no-op. Spike starting thresholds: 1.15 (expand) / 0.87
  (contract).
- Long-press menu + VoiceOver/TalkBack custom actions as required
  auxiliary paths (these survived into option D as primary paths).

## 2. Why it was discarded

- Discoverability: a first-time user has no way to find the
  gesture; the feature would hide behind an invisible affordance.
- One-handed field use is difficult (film photography context).
- Weak semantic link between "pinch" and "add a filter wheel".
- The accessibility/menu path had to exist anyway, so pinch never
  reduced the required surface — it only added a redundant one.
- Real usage on the simulator felt awkward; even if hardware feels
  better, the above points stand for a PRIMARY path.
- Related alternative, edge DRAG, was also rejected: it conflicts
  with the camera-slot pager's horizontal swipe, and restricting
  its start zone would re-create the discoverability problem.

## 3. R1 spike result (technical GO — observed during the throwaway spike)

Throwaway spike on branch `spike/PTIMER-199-pinch` (app root
swapped behind a `-spike-pinch` launch argument; HUD counters +
NSLog markers as instrumentation). iPhone 17 simulator (iOS 26.3),
manual Option-drag input.

The spike branch and full raw logs were NOT retained. The excerpt
below is the only preserved evidence. These findings are an
investigation record and must be re-verified against the current
code before reuse.

Observed during the throwaway spike:

- Coexistence: a `UIPinchGestureRecognizer` installed on an
  ancestor (window level, `shouldRecognizeSimultaneously = true`)
  fired while UIPickerView one-finger scrolling kept working —
  interleaved pinch actions and wheel scroll events in the same
  session.
- Latch: one action per gesture; continuous scale updates after
  the threshold did not repeat the action.
- Boundary no-ops: expand attempts at 4 wheels stayed at 4;
  contract was blocked at 1 wheel and when only value-holding
  wheels remained.
- Only window-level attach was exercised; ND-row scoping was NOT
  verified.

Preserved log excerpt (simulator unified log, 2026-07-15):

```text
03:13:30.327 SPIKE action contract wheels=2
03:13:31.063 SPIKE gesture ended fired=1
03:13:31.493 SPIKE scroll wheel=1 value=5
03:13:31.494 SPIKE scroll wheel=0 value=1
03:13:31.878 SPIKE action expand wheels=3
03:13:32.674 SPIKE gesture ended fired=1
03:13:34.424 SPIKE action expand wheels=4   <- no-op at max
03:13:34.741 SPIKE gesture ended fired=1
03:13:37.392 SPIKE action contract wheels=2 <- blocked: wheels held 3 and 6
03:13:37.462 SPIKE gesture ended fired=1
```

## 4. Implementation learnings (for any future gesture bridge)

1. One-shot recognizer attach silently detached: attaching once to
   `observedView.superview` stopped delivering events after SwiftUI
   reparented the hierarchy. Re-verify the attach target EVERY
   layout pass (the `WheelPickerContinuousObserver` pattern is the
   correct template).
2. Window-level attach observed working; ND-row scoping remains
   unverified (open task for any revisit).
3. No programmatic multi-touch on the simulator in this
   environment (`simctl` has no touch synthesis; CGEvent posting
   blocked by TCC): true pinch verification needs a human
   Option-drag or an XCUITest UI-test target
   (`pinch(withScale:velocity:)`), which the project does not have.

### Spike environment notes (condensed; general simulator gotchas)

- Debug builds install as `com.sangwook.PTimer.dev`; launching
  `com.sangwook.PTimer` runs whatever stale build is already
  installed.
- Use an explicit `-derivedDataPath` to avoid stale multi-hash
  DerivedData products; app code lives in `PTimer.debug.dylib`
  (the executable is a small stub).
- Launch ARGUMENTS (`ProcessInfo.arguments`) reached the app;
  `SIMCTL_CHILD_*` environment did not in this setup.

## 5. Conditions for revisiting

Only via a new ticket, and only as an optional shortcut layered on
top of the option D primary paths (which must remain sufficient on
their own). A real-device ergonomics check is the first gate; the
spike's coexistence + latch findings above can be reused as-is.
