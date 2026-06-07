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
        content
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

    @ViewBuilder
    private var content: some View {
        switch displayState {
        case .unavailable(.inactive):
            inactiveRow
        case .available(let availableState):
            activeRow(availableState)
        case .unavailable(.noComparisonAvailable):
            // Reserved enum case; the presenter never emits this form
            // today (target-set + comparison-unavailable goes through
            // `.available` with `comparison: nil`). Render inactive
            // so any future routing change still produces something
            // sensible instead of an empty card.
            inactiveRow
        }
    }

    private var inactiveRow: some View {
        Button {
            inputSheetVisible = true
        } label: {
            HStack(spacing: 12) {
                Text("Target Shutter")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Off")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            // Broad tap target — without `.frame(maxWidth:.infinity)`
            // the Button's label would shrink-wrap to its content and
            // tapping the empty trailing area inside the section card
            // would miss the Button.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("target-shutter-set-button")
        .accessibilityLabel("Target Shutter is off")
        .accessibilityHint("Opens a sheet to enable Target Shutter")
    }

    @ViewBuilder
    private func activeRow(_ state: TargetShutterAvailableState) -> some View {
        // Compact single-row layout.
        // [edit-area: label + value + stop diff] [play].
        //
        // The edit-area is a real `Button` (matching the inactive
        // row's structure) so VoiceOver, Switch Control, Voice
        // Control, and external-keyboard focus navigation all treat
        // it as a first-class actionable element. The play `Button`
        // is a sibling — both buttons live side by side in the outer
        // HStack, never nested, so SwiftUI routes taps to each
        // independently. Clear is intentionally **not** on the main
        // row — the input sheet's `Use Target Shutter` switch owns
        // target removal.
        //
        // The explicit `vs <basis>` text from the previous two-row
        // design is dropped to keep the row compact; the basis still
        // drives the presenter's comparison and is folded into the
        // edit Button's combined accessibility label so blind users
        // still get the same information.
        HStack(spacing: 12) {
            Button {
                inputSheetVisible = true
            } label: {
                HStack(spacing: 8) {
                    Text("Target Shutter")
                        // PTIMER-172: keep the label on one line so the
                        // row never grows to two lines on a narrow phone.
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Text(targetText(state.targetSeconds))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("target-shutter-target-value")
                    compactStopDifference(state)
                }
                // Broad tap target — without `.frame(maxWidth:.infinity)`
                // the Button's label would shrink-wrap, leaving the
                // gap between the value and the play button untappable.
                // The play button stays a sibling outside this Button,
                // so taps on the play glyph still route to the start-
                // timer action rather than to edit.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(activeRowAccessibilityLabel(state))
            .accessibilityHint("Opens a sheet to change the target duration")
            .accessibilityIdentifier("target-shutter-edit-button")

            TimerActionButton(
                isEnabled: canStartTimer,
                metrics: TimerActionMetrics(
                    diameter: style.timerActionSize - 8,
                    iconPointSize: style.timerActionIconSize - 1
                ),
                style: .tintedWhenEnabled,
                accessibilityLabel: "Start target shutter timer",
                accessibilityHint: "Starts a timer using the photographer-supplied target duration",
                accessibilityIdentifier: "target-shutter-start-timer-button",
                action: onStartTargetTimer
            )
        }
    }

    /// Compact arrow + stop-difference glyph for the active row.
    /// Sized to subheadline so it matches the row's overall scale.
    /// Accessibility is intentionally hidden here — the enclosing
    /// edit-area's combined label already conveys the same info.
    @ViewBuilder
    private func compactStopDifference(_ state: TargetShutterAvailableState) -> some View {
        if let stopDifference = state.stopDifference {
            HStack(spacing: 4) {
                Image(systemName: stopDifferenceArrow(stopDifference.kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(stopDifferenceColor(for: stopDifference.kind))
                Text(stopDifference.formattedText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stopDifferenceColor(for: stopDifference.kind))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("target-shutter-stop-difference")
            }
            .accessibilityHidden(true)
        } else {
            Text("—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-shutter-stop-difference")
                .accessibilityHidden(true)
        }
    }

    /// VoiceOver label for the combined edit-area accessibility
    /// element. Folds the (no-longer-visible) comparison basis and
    /// stop-difference into a single readable sentence so blind
    /// users still get the same information sighted users used to
    /// read on the dropped second row.
    private func activeRowAccessibilityLabel(_ state: TargetShutterAvailableState) -> String {
        let value = "Target Shutter \(targetText(state.targetSeconds))"
        let basis: String
        if let comparison = state.comparison {
            basis = " vs \(comparison.label)"
        } else {
            basis = ""
        }
        if let stopDifference = state.stopDifference {
            switch stopDifference.kind {
            case .match:
                return "\(value)\(basis), matches calculated exposure"
            case .longerThanComparison:
                return "\(value)\(basis), \(stopDifference.formattedText) longer"
            case .shorterThanComparison:
                return "\(value)\(basis), \(stopDifference.formattedText) shorter"
            }
        }
        return "\(value)\(basis)"
    }

    private func stopDifferenceArrow(_ kind: TargetShutterStopDifferenceKind) -> String {
        switch kind {
        case .match:
            return "equal"
        case .longerThanComparison:
            return "arrow.up"
        case .shorterThanComparison:
            return "arrow.down"
        }
    }

    private func stopDifferenceColor(for kind: TargetShutterStopDifferenceKind) -> Color {
        switch kind {
        case .match:
            return Color(.systemGreen)
        case .longerThanComparison:
            return Color(.systemBlue)
        case .shorterThanComparison:
            return Color(.systemOrange)
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

    private func targetText(_ seconds: TimeInterval) -> String {
        // Compact h/m/s formatting (`3m 20s`, `2h 16m`) — same shape
        // the input sheet's Fine Tune readout uses, so the main card
        // and the sheet stay typographically aligned.
        let total = max(1, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        if h > 0 {
            if m == 0 && s == 0 {
                return "\(h)h"
            }
            if s == 0 {
                return "\(h)h \(m)m"
            }
            return "\(h)h \(m)m \(s)s"
        }
        if m > 0 {
            if s == 0 {
                return "\(m)m"
            }
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }
}


/// Input sheet built around a horizontally paged Quick / Fine Tune
/// pair plus a prominent draft-target readout.
///
/// Layout (top → bottom):
///
///   • Horizontal pager: [ Quick wheel ] [ Fine Tune wheels ]
///     The currently active page snaps centred; the other peeks
///     so the photographer can see "you can swipe for precision".
///   • Target numbers: large, monospaced read-out of the draft
///     duration. Updates immediately from either Quick or Fine
///     edits and is the visible source of truth while editing.
///   • Confirm + Cancel buttons.
///
/// Quick and Fine **do not** live-couple. Both modes write to a
/// single `state.draftSeconds`, and each mode's wheel state is
/// derived from the draft via computed bindings (`get` reads from
/// the draft, `set` mutates the draft). When the photographer
/// taps Quick, only the Quick setter fires; the Fine wheels'
/// bindings re-render via SwiftUI's state observation, but their
/// setters are *not* invoked. The same applies in reverse, so
/// there is no Quick→Fine→Quick feedback loop and no need for
/// `DispatchQueue.main.async` flag dances. `quickSelectedPreset`
/// is only ever set by `applyQuickTap` (direct user choice).
///
/// `state.draftSeconds` is the input session's draft. Confirm
/// commits it via `onSet`; Cancel discards it via `onCancel` —
/// the model on the parent ViewModel only learns about the
/// new value when Confirm fires.
struct TargetShutterInputSheet: View {
    let initialSeconds: TimeInterval?
    let onSet: (TimeInterval) -> Void
    /// Called when the photographer Confirms after flipping the
    /// `Use Target Shutter` switch Off. The parent view treats this
    /// as "remove the committed Target Shutter" — Cancel or sheet
    /// dismissal instead bypasses this callback, so the previously
    /// committed target is preserved.
    let onClearTarget: () -> Void
    let onCancel: () -> Void

    /// Draft state for the input session. Both Quick and Fine modes
    /// edit `draftSeconds`; their wheel bindings derive from it.
    @State private var state: TargetShutterInputState

    /// Quick presets — values the photographer is most likely to dial
    /// in for long-exposure work. The first half follows the photo
    /// shutter ladder (1, 2, 4, 8, 15, 30 seconds, 1, 2 minutes); the
    /// long end uses rounded, photographer-friendly steps (4, 8, 15,
    /// 30 minutes, 1, 2, 4, 8 hours) rather than strict doublings.
    static let quickPresets: [TimeInterval] = [
        1, 2, 4, 8, 15, 30,        // seconds
        60, 120, 240, 480,          // 1m, 2m, 4m, 8m
        900, 1800,                  // 15m, 30m
        3600, 7200, 14_400, 28_800,  // 1h, 2h, 4h, 8h
    ]

    /// Default initial duration when the photographer has neither a
    /// per-slot target nor a recent value: 1 minute.
    static let defaultInitialSeconds: TimeInterval = TimeInterval(TargetShutterInputState.defaultSeedSeconds)

    init(
        initialSeconds: TimeInterval?,
        initialEnabled: Bool,
        onSet: @escaping (TimeInterval) -> Void,
        onClearTarget: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSeconds = initialSeconds
        self.onSet = onSet
        self.onClearTarget = onClearTarget
        self.onCancel = onCancel

        _state = State(
            initialValue: TargetShutterInputState.initial(
                seedSeconds: initialSeconds,
                quickPresets: Self.quickPresets,
                initialEnabled: initialEnabled
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // `Use Target Shutter` row hosts the native iOS
                // switch. Placed inline (not in the toolbar) so SwiftUI
                // renders the standard `UISwitch` rather than the
                // toolbar's compact pill button. Off sets
                // `isDraftCleared`; Confirm then routes through
                // `onClearTarget`. Cancel after Off discards the draft
                // change, preserving the previously-committed target.
                enabledToggleRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Draft target value sits above the wheel pager so the
                // value being edited is introduced before its controls.
                // Off state dims the readout to tertiary rather than
                // replacing the duration with a separate `None` label —
                // the duration the user committed last is what the Off
                // state's Confirm would *remove*, so seeing it dimmed
                // matches the action they're about to take.
                targetNumbersDisplay
                    .padding(.bottom, 6)

                // `.disabled` blocks wheel interaction and auto-dims
                // the pager (including the teaser tap targets) when
                // target is Off. Continuous observer / Picker binding
                // setters additionally guard at the view layer so a
                // wheel still mid-deceleration when the user flipped
                // the switch Off cannot mutate the draft.
                horizontalPager
                    .disabled(state.isDraftCleared)

                Spacer(minLength: 0)

                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Target Shutter")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var enabledToggleRow: some View {
        Toggle(isOn: targetShutterEnabledBinding) {
            Text("Use Target Shutter")
                .font(.body)
                .foregroundStyle(.primary)
        }
        .tint(.accentColor)
        .accessibilityIdentifier("target-shutter-enabled-switch")
        .accessibilityHint("When off, Confirm removes the Target Shutter; Cancel restores the previously committed value.")
    }

    /// Toggle binding for the sheet-header On/Off switch.
    /// `get` derives from `state.isDraftCleared` — Off = cleared.
    /// `set` routes to `clearDraft()` or `reArmDraft(...)`, which
    /// preserve / restore the underlying draft seconds so toggling
    /// Off then On lands back on the user's previous value without
    /// a snap.
    private var targetShutterEnabledBinding: Binding<Bool> {
        Binding(
            get: { !state.isDraftCleared },
            set: { isOn in
                if isOn {
                    state.reArmDraft(
                        seedSeconds: initialSeconds,
                        quickPresets: Self.quickPresets
                    )
                } else {
                    state.clearDraft()
                }
            }
        )
    }

    // MARK: - Horizontal pager

    /// Horizontal pager containing the Quick page and the Fine Tune
    /// page. Uses `TabView` with the page style — same idiom as the
    /// camera-slot pager on the main calculator — because
    /// `UIPageViewController`'s gesture model defers cleanly to the
    /// nested `UIPickerView`'s vertical pan. A `ScrollView`-based
    /// pager with peek would fight the wheel for the touch and slide
    /// the page sideways during a vertical wheel scroll, so we trade
    /// the peek affordance for reliable scrolling. The page-dot
    /// indicator below the pager communicates that there are two
    /// modes available.
    private var horizontalPager: some View {
        TabView(selection: activeModeBinding) {
            quickPage
                .tag(TargetShutterInputState.InputMode.quick)

            finePage
                .tag(TargetShutterInputState.InputMode.fine)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 220)
        .accessibilityIdentifier("target-shutter-input-pager")
    }

    private var quickPage: some View {
        HStack(alignment: .top, spacing: 8) {
            quickActivePanel
                .frame(maxWidth: .infinity)
            // Right-edge teaser hints that Fine Tune lives one swipe
            // away. Tapping the teaser routes through the same mode-
            // switch path the page-dot pager uses, so the entering
            // Fine wheels reseed from the current draft.
            TargetShutterModeTeaser(
                label: "Fine\nTune",
                direction: .right,
                onTap: {
                    state.setActiveMode(.fine, quickPresets: Self.quickPresets)
                }
            )
            .frame(width: 64)
            .accessibilityIdentifier("target-shutter-fine-teaser")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var quickActivePanel: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Quick")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !state.quickIsExactMatch(in: Self.quickPresets) {
                    Text("· Custom")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("target-shutter-quick-custom-marker")
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            Picker("Quick target", selection: quickAnchorBinding) {
                ForEach(Self.quickPresets, id: \.self) { value in
                    Text(quickLabel(for: value))
                        .monospacedDigit()
                        // A row renders bright only when it is the
                        // *user-selected* preset — i.e. the photographer
                        // tapped Quick. Entering Fine mode (or any
                        // Fine adjustment) clears `quickSelectedPreset`,
                        // so the wheel can park on a preset position
                        // without claiming it as the active selection.
                        .foregroundStyle(
                            state.quickSelectedPreset == value
                                ? Color.primary
                                : Color.secondary
                        )
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: .infinity)
            .clipped()
            // Display-link-driven mid-scroll observer matches the Base
            // Shutter / ND Filter responsiveness on the main calculator.
            // Without this, the Picker only reports a new value on snap,
            // so Target numbers visibly lag behind the wheel.
            .background {
                WheelPickerContinuousObserver(
                    onSelectedRowChange: { row in
                        // Drop emits arriving after the user already
                        // swiped to Fine or flipped the target switch
                        // Off. Without these guards a late observer
                        // pulse would mutate the draft and (before
                        // the model-level changes) yank `activeMode`
                        // back to `.quick` or silently re-arm the
                        // cleared draft.
                        guard !state.isDraftCleared,
                              state.activeMode == .quick,
                              Self.quickPresets.indices.contains(row) else {
                            return
                        }
                        // Use the continuous-scroll variant so we do
                        // not write back to `quickWheelAnchor` while
                        // the wheel is decelerating — that write
                        // would re-fire `UIPickerView.selectRow(...)`
                        // and kill momentum. The anchor catches up on
                        // settle via `quickAnchorBinding`.
                        state.applyQuickContinuousScroll(Self.quickPresets[row])
                    },
                    onInteractionEnd: {}
                )
            }
            .accessibilityIdentifier("target-shutter-quick-picker")
        }
    }

    private var finePage: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left-edge teaser hints that Quick lives one swipe away.
            // Same mode-switch path as the page-dot pager — entering
            // Quick re-anchors the Quick wheel to the nearest preset
            // for the current draft.
            TargetShutterModeTeaser(
                label: "Quick",
                direction: .left,
                onTap: {
                    state.setActiveMode(.quick, quickPresets: Self.quickPresets)
                }
            )
            .frame(width: 64)
            .accessibilityIdentifier("target-shutter-quick-teaser")
            fineActivePanel
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var fineActivePanel: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Fine Tune")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: 0) {
                fineColumn(
                    title: "h",
                    range: 0...23,
                    binding: fineHoursBinding,
                    accessibilityID: "target-shutter-hours-picker",
                    onContinuousRowChange: { row in
                        // Drop late Fine emits arriving after the user
                        // already swiped to Quick or flipped the
                        // switch Off — see `quickAnchorBinding` for
                        // the symmetric case.
                        guard !state.isDraftCleared,
                              state.activeMode == .fine,
                              (0...23).contains(row) else { return }
                        // Continuous-scroll variant updates draft only,
                        // not `state.fineHours`, so the column's own
                        // Picker binding does not see a state change
                        // mid-deceleration. The h field catches up on
                        // settle via `fineHoursBinding`.
                        state.applyFineContinuousScroll(
                            hours: row,
                            minutes: state.fineMinutes,
                            seconds: state.fineSeconds
                        )
                    }
                )
                fineColumn(
                    title: "m",
                    range: 0...59,
                    binding: fineMinutesBinding,
                    accessibilityID: "target-shutter-minutes-picker",
                    onContinuousRowChange: { row in
                        guard !state.isDraftCleared,
                              state.activeMode == .fine,
                              (0...59).contains(row) else { return }
                        state.applyFineContinuousScroll(
                            hours: state.fineHours,
                            minutes: row,
                            seconds: state.fineSeconds
                        )
                    }
                )
                fineColumn(
                    title: "s",
                    range: 0...59,
                    binding: fineSecondsBinding,
                    accessibilityID: "target-shutter-seconds-picker",
                    onContinuousRowChange: { row in
                        guard !state.isDraftCleared,
                              state.activeMode == .fine,
                              (0...59).contains(row) else { return }
                        state.applyFineContinuousScroll(
                            hours: state.fineHours,
                            minutes: state.fineMinutes,
                            seconds: row
                        )
                    }
                )
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func fineColumn(
        title: String,
        range: ClosedRange<Int>,
        binding: Binding<Int>,
        accessibilityID: String,
        onContinuousRowChange: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: binding) {
                ForEach(range, id: \.self) { value in
                    Text("\(value)")
                        .monospacedDigit()
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            // Same display-link mid-scroll observer pattern as Base
            // Shutter / ND Filter on the main calculator. Each Fine
            // column attaches its own observer; `locatePicker` walks
            // up from the observation view's frame so the observer
            // reliably binds to the local h / m / s picker rather
            // than a sibling column.
            .background {
                WheelPickerContinuousObserver(
                    onSelectedRowChange: onContinuousRowChange,
                    onInteractionEnd: {}
                )
            }
            .accessibilityIdentifier(accessibilityID)
        }
    }

    // MARK: - Target numbers + actions

    /// Large, monospaced read-out of the current draft. The single
    /// visible source of truth while editing — both Quick and Fine
    /// edits update it immediately because both write to
    /// `state.draftSeconds` directly. Off state dims the readout
    /// rather than replacing it with `None` — the duration is what
    /// Confirm would remove, so seeing it dimmed previews the action.
    private var targetNumbersDisplay: some View {
        Text(formattedDraft)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(state.isDraftCleared ? .tertiary : .primary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("target-shutter-draft-readout")
            .accessibilityLabel(targetNumbersAccessibilityLabel)
    }

    private var targetNumbersAccessibilityLabel: String {
        let base = "Draft target \(formattedDraft)"
        return state.isDraftCleared ? "\(base), Target Shutter off" : base
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: cancel) {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("target-shutter-cancel-button")

            Button(action: confirm) {
                Text(confirmButtonLabel)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canConfirm ? Color.accentColor : Color.accentColor.opacity(0.3))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
            .accessibilityIdentifier("target-shutter-set-button-confirm")
        }
    }

    // MARK: - Bindings

    /// Mode-switch binding for the `TabView` selection. Routes
    /// through `setActiveMode(_:quickPresets:)` so the entering
    /// wheel reseeds from the current draft (and Quick selection is
    /// cleared when Fine becomes active).
    private var activeModeBinding: Binding<TargetShutterInputState.InputMode> {
        Binding(
            get: { state.activeMode },
            set: { newMode in
                state.setActiveMode(newMode, quickPresets: Self.quickPresets)
            }
        )
    }

    /// Quick wheel binding. Reads/writes the *stored* Quick wheel
    /// anchor — independent of Fine state, so the Fine peek view
    /// stays still while the user is scrolling Quick.
    ///
    /// The setter guards on `state.activeMode == .quick` so a stale
    /// Picker emit fired after the user already swiped to Fine
    /// cannot mutate the draft. Combined with the matching guard on
    /// the continuous observer below, this is what prevents the
    /// "user swipes from Fine to Quick mid-scroll, sheet jumps back
    /// to Fine" bug — the late Fine emit reaches this setter after
    /// `activeMode` is already `.quick`, and the guard drops it.
    private var quickAnchorBinding: Binding<TimeInterval> {
        Binding(
            get: { state.quickWheelAnchor },
            set: { newPreset in
                guard !state.isDraftCleared,
                      state.activeMode == .quick else { return }
                state.applyQuickTap(newPreset)
            }
        )
    }

    private var fineHoursBinding: Binding<Int> {
        Binding(
            get: { state.fineHours },
            set: { newH in
                guard !state.isDraftCleared,
                      state.activeMode == .fine else { return }
                state.applyFineChange(
                    hours: newH,
                    minutes: state.fineMinutes,
                    seconds: state.fineSeconds
                )
            }
        )
    }

    private var fineMinutesBinding: Binding<Int> {
        Binding(
            get: { state.fineMinutes },
            set: { newM in
                guard !state.isDraftCleared,
                      state.activeMode == .fine else { return }
                state.applyFineChange(
                    hours: state.fineHours,
                    minutes: newM,
                    seconds: state.fineSeconds
                )
            }
        )
    }

    private var fineSecondsBinding: Binding<Int> {
        Binding(
            get: { state.fineSeconds },
            set: { newS in
                guard !state.isDraftCleared,
                      state.activeMode == .fine else { return }
                state.applyFineChange(
                    hours: state.fineHours,
                    minutes: state.fineMinutes,
                    seconds: newS
                )
            }
        )
    }

    // MARK: - Action handlers and helpers

    private var canConfirm: Bool {
        // Cleared draft is always confirmable — Confirm commits the
        // removal of the Target Shutter. A non-cleared draft requires
        // a positive duration (Fine wheels can park on 0/0/0 mid-edit
        // and that intermediate state must not be committable).
        state.isDraftCleared || state.draftSeconds > 0
    }

    private var formattedDraft: String {
        formattedDuration(state.draftSeconds)
    }

    private var confirmButtonLabel: String {
        "Confirm"
    }

    private func confirm() {
        if state.isDraftCleared {
            onClearTarget()
            return
        }
        guard state.draftSeconds > 0 else { return }
        onSet(TimeInterval(state.draftSeconds))
    }

    private func cancel() {
        // Discard the draft and let the parent dismiss without
        // committing. The draft state is local to this view and is
        // discarded with the sheet, so no separate revert step is
        // needed here.
        onCancel()
    }

    private func quickLabel(for value: TimeInterval) -> String {
        formattedDuration(Int(value.rounded()))
    }

    private func formattedDuration(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 { parts.append("\(s)s") }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }
}

/// Visual teaser shown alongside the active page inside the input
/// sheet's `TabView(.page)`. It does **not** render the inactive
/// mode's wheels — moving inactive wheel content while the active
/// wheel is being scrolled is the exact failure mode the C-direction
/// architecture is designed to avoid. The teaser is a labelled,
/// thin-outlined tap target that switches modes through the same
/// `state.setActiveMode(_:quickPresets:)` path the page-dot pager
/// uses, so the entering mode reseeds from the current draft and
/// the exiting mode's wheel state is preserved.
private struct TargetShutterModeTeaser: View {
    enum Direction { case left, right }

    let label: String
    let direction: Direction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if direction == .left {
                    chevron
                }
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if direction == .right {
                    chevron
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(label.replacingOccurrences(of: "\n", with: " "))")
        .accessibilityHint("Opens the alternate input mode")
    }

    private var chevron: some View {
        Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
    }
}
