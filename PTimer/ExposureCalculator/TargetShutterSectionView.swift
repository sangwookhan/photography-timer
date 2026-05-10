import SwiftUI

/// Result-area card that surfaces the optional Target Shutter feature.
/// Renders the current target (or a `Set Target` affordance), the
/// stop-difference comparison against the active workflow's primary
/// value, and a play affordance to start a target-driven timer.
///
/// The view does not own state. All target-state mutations route
/// through closures into the `ExposureCalculatorViewModel` facade so
/// the source-of-truth contract on `TargetShutterModel` stays
/// single-rooted.
struct TargetShutterSectionView: View {
    let displayState: TargetShutterDisplayState
    let canStartTimer: Bool
    let lastUsedTargetSeconds: TimeInterval?
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let onSetTarget: (TimeInterval) -> Void
    let onClearTarget: () -> Void
    let onStartTargetTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    @State private var inputSheetVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if isActive {
                    Button(action: onClearTarget) {
                        Text("Clear")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("target-shutter-clear-button")
                    .accessibilityHint("Clears the Target Shutter and hides the comparison")
                }
            }

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle(style: style)
        .accessibilityIdentifier("target-shutter-section")
        .sheet(isPresented: $inputSheetVisible) {
            TargetShutterInputSheet(
                initialSeconds: initialSheetSeconds,
                onSet: { seconds in
                    onSetTarget(seconds)
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
            inactiveContent
        case .unavailable(.noComparisonAvailable):
            unavailableComparisonContent(targetSeconds: nil)
        case .available(let availableState):
            availableContent(availableState)
        }
    }

    private var inactiveContent: some View {
        Button(action: { inputSheetVisible = true }) {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Set Target")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("target-shutter-set-button")
        .accessibilityLabel("Set target shutter duration")
        .accessibilityHint("Opens a sheet to choose or enter a target duration")
    }

    @ViewBuilder
    private func availableContent(_ state: TargetShutterAvailableState) -> some View {
        // Single-line layout: large target value on the leading edge,
        // arrow + stop-difference text in the middle, play button on
        // the trailing edge. Tapping anywhere on the duration / stop
        // area opens the input sheet so editing is reachable without
        // hunting for a small affordance.
        HStack(alignment: .center, spacing: 14) {
            Button(action: { inputSheetVisible = true }) {
                HStack(spacing: 14) {
                    Text(targetText(state.targetSeconds))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityIdentifier("target-shutter-target-value")

                    stopDifferenceLabel(state)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit target shutter")
            .accessibilityHint("Opens a sheet to change the target duration")
            .accessibilityIdentifier("target-shutter-edit-button")

            TargetTimerActionView(
                canStart: canStartTimer,
                onStart: onStartTargetTimer,
                style: style
            )
        }
    }

    @ViewBuilder
    private func stopDifferenceLabel(_ state: TargetShutterAvailableState) -> some View {
        if let stopDifference = state.stopDifference {
            HStack(spacing: 4) {
                Image(systemName: stopDifferenceArrow(stopDifference.kind))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(stopDifferenceColor(for: stopDifference.kind))
                    .accessibilityHidden(true)
                Text(stopDifference.formattedText)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(stopDifferenceColor(for: stopDifference.kind))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(stopDifferenceAccessibility(stopDifference))
            .accessibilityIdentifier("target-shutter-stop-difference")
        } else {
            Text("—")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Comparison unavailable")
                .accessibilityIdentifier("target-shutter-stop-difference")
        }
    }

    @ViewBuilder
    private func unavailableComparisonContent(targetSeconds: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Target comparison unavailable")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("target-shutter-unavailable-text")
        }
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

    private func stopDifferenceAccessibility(_ value: TargetShutterStopDifference) -> String {
        switch value.kind {
        case .match:
            return "Target matches calculated exposure"
        case .longerThanComparison:
            return "Target is \(value.formattedText) longer"
        case .shorterThanComparison:
            return "Target is \(value.formattedText) shorter"
        }
    }

    private var headerTitle: String {
        switch displayState {
        case .available(let state):
            if let comparison = state.comparison {
                return "Target Shutter · vs \(comparison.label)"
            }
            return "Target Shutter"
        case .unavailable, .available:
            return "Target Shutter"
        }
    }

    private var isActive: Bool {
        switch displayState {
        case .unavailable(.inactive):
            return false
        case .unavailable(.noComparisonAvailable), .available:
            return true
        }
    }

    private var initialSheetSeconds: TimeInterval? {
        if case .available(let state) = displayState {
            return state.targetSeconds
        }
        return lastUsedTargetSeconds
    }

    private func targetText(_ seconds: TimeInterval) -> String {
        // Mirror the CTA shape ("3m 20s") so the displayed value reads
        // the same as what the photographer set in the input sheet.
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

private struct TargetTimerActionView: View {
    let canStart: Bool
    let onStart: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        Button(action: onStart) {
            Image(systemName: "play.fill")
                .font(.system(size: style.timerActionIconSize + 1, weight: .semibold))
                .foregroundStyle(canStart ? Color.accentColor : Color.secondary.opacity(0.8))
                .frame(width: style.timerActionSize + 4, height: style.timerActionSize + 4)
                .background(
                    Circle()
                        .fill(canStart ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill))
                )
                .overlay(
                    Circle()
                        .stroke(Color(.separator).opacity(0.55), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .accessibilityIdentifier("target-shutter-start-timer-button")
        .accessibilityLabel("Start timer from target shutter")
        .accessibilityHint("Starts a timer using the photographer-supplied target duration")
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
        3600, 7200, 14_400, 28_800  // 1h, 2h, 4h, 8h
    ]

    /// Default initial duration when the photographer has neither a
    /// per-slot target nor a recent value: 1 minute.
    static let defaultInitialSeconds: TimeInterval = TimeInterval(TargetShutterInputState.defaultSeedSeconds)

    init(
        initialSeconds: TimeInterval?,
        onSet: @escaping (TimeInterval) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSeconds = initialSeconds
        self.onSet = onSet
        self.onCancel = onCancel

        _state = State(
            initialValue: TargetShutterInputState.initial(
                seedSeconds: initialSeconds,
                quickPresets: Self.quickPresets
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                horizontalPager
                    .padding(.top, 8)

                targetNumbersDisplay
                    .padding(.top, 8)
                    .padding(.bottom, 4)

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
                        guard Self.quickPresets.indices.contains(row) else {
                            return
                        }
                        state.applyQuickTap(Self.quickPresets[row])
                    },
                    onInteractionEnd: {}
                )
            }
            .accessibilityIdentifier("target-shutter-quick-picker")
        }
        .padding(.vertical, 4)
    }

    private var finePage: some View {
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
                        guard (0...23).contains(row) else { return }
                        state.applyFineChange(
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
                        guard (0...59).contains(row) else { return }
                        state.applyFineChange(
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
                        guard (0...59).contains(row) else { return }
                        state.applyFineChange(
                            hours: state.fineHours,
                            minutes: state.fineMinutes,
                            seconds: row
                        )
                    }
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.vertical, 4)
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
    /// `state.draftSeconds` directly.
    private var targetNumbersDisplay: some View {
        Text(formattedDraft)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("target-shutter-draft-readout")
            .accessibilityLabel("Draft target \(formattedDraft)")
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
    private var quickAnchorBinding: Binding<TimeInterval> {
        Binding(
            get: { state.quickWheelAnchor },
            set: { newPreset in
                state.applyQuickTap(newPreset)
            }
        )
    }

    private var fineHoursBinding: Binding<Int> {
        Binding(
            get: { state.fineHours },
            set: { newH in
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
        state.draftSeconds > 0
    }

    private var formattedDraft: String {
        formattedDuration(state.draftSeconds)
    }

    private var confirmButtonLabel: String {
        guard state.draftSeconds > 0 else { return "Confirm" }
        return "Confirm"
    }

    private func confirm() {
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
