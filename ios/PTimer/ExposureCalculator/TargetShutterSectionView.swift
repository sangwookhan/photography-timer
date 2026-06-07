import SwiftUI
import PTimerKit

/// Result-area card that surfaces the optional Target Shutter feature.
/// Renders a compact single row in both states:
///   inactive: `Target Shutter ─── Off ─ ›`
///   active:   `Target Shutter ─── {value} {arrow + stop diff} [play]`
///
/// The active row drops the explicit `vs <basis>` text — the
/// presenter still picks Adjusted Shutter (no-film) or Corrected
/// Exposure (film) as the comparison value, and that context is
/// folded into the row's VoiceOver label. The compact row keeps
/// Target Shutter from dominating the page vertically and from
/// crowding the film result card's three rows.
///
/// The view does not own state. All target-state mutations route
/// through closures into the `ExposureCalculatorViewModel` facade so
/// the source-of-truth contract on `TargetShutterModel` stays
/// single-rooted.
struct TargetShutterSectionView: View {
    let displayState: TargetShutterDisplayState
    let canStartTimer: Bool
    let onSetTarget: (TimeInterval) -> Void
    let onClearTarget: () -> Void
    let onStartTargetTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    @State private var inputSheetVisible = false

    var body: some View {
        TargetShutterCard(
            displayState: displayState,
            canStartTimer: canStartTimer,
            onEdit: { inputSheetVisible = true },
            onStartTimer: onStartTargetTimer,
            layout: TargetShutterCardLayout(
                timerAction: TimerActionMetrics(
                    diameter: style.timerActionSize - 8,
                    iconPointSize: style.timerActionIconSize - 1
                )
            )
        )
        .sectionCardStyle(style: style)
        .accessibilityIdentifier("target-shutter-section")
        .sheet(isPresented: $inputSheetVisible) {
            // Sheet dismissal by drag-down / tap-outside resolves
            // to `inputSheetVisible = false` from SwiftUI itself —
            // *none* of the three callbacks below fire in that
            // path. The committed Target Shutter is mutated only
            // when the sheet explicitly invokes `onSet` (Confirm
            // with a positive draft) or `onClearTarget` (Confirm
            // with the switch Off). External dismiss is therefore
            // equivalent to Cancel by construction.
            TargetShutterInputSheet(
                initialSeconds: initialSheetSeconds,
                initialEnabled: initialSheetEnabled,
                onSet: { seconds in
                    onSetTarget(seconds)
                    inputSheetVisible = false
                },
                onClearTarget: {
                    onClearTarget()
                    inputSheetVisible = false
                },
                onCancel: { inputSheetVisible = false }
            )
        }
    }

    /// Sheet seed when opening Target Shutter input.
    ///
    /// Policy: the seed is **only** the active slot's committed target.
    /// A slot with no committed target seeds to `nil` so the sheet
    /// falls back to the input state's default seed (1 minute) — it
    /// must **not** leak the previously-used value from another
    /// camera slot. `TargetShutterModel.lastUsedTargetSeconds` is
    /// a global memory; using it here would surface Camera 1's
    /// 8h 11m on Camera 2 even though Camera 2 has no target,
    /// which is exactly the slot-isolation bug we are preventing.
    private var initialSheetSeconds: TimeInterval? {
        if case .available(let state) = displayState {
            return state.targetSeconds
        }
        return nil
    }

    /// The sheet always opens with `Use Target Shutter` switched On so
    /// the user lands in a ready-to-edit state — tapping the inactive
    /// main row signals **edit intent**, not "review the disabled
    /// state". Combined with `initialSheetSeconds` returning `nil`
    /// for inactive slots, the state seeds to the default (1 minute)
    /// and the user can immediately Confirm to commit a fresh target
    /// or adjust the wheels.
    ///
    /// Switching the toggle Off inside the sheet still works — that
    /// path flips `state.isDraftCleared` and is honoured by Confirm
    /// (commits removal) / Cancel (preserves previous committed
    /// target). It is the explicit-user-intent path; opening the
    /// sheet from an inactive row is the implicit edit-intent path.
    private var initialSheetEnabled: Bool {
        true
    }
}
