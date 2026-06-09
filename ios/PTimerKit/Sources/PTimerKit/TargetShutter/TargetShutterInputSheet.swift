import SwiftUI

// The sheet's rendering uses iOS-only SwiftUI surfaces — the wheel
// `Picker`, the paged `TabView`, sheet detents, and inline navigation
// titles — none of which compile on macOS. The kit targets macOS only
// so its pure logic (e.g. TargetShutterInputState) can run off the
// simulator under `swift test`; that logic lives in cross-platform
// files, so guarding this iOS-only view keeps the package building on
// macOS without pulling in UIKit.
#if os(iOS)

/// Input sheet built around a horizontally paged Quick / Fine Tune
/// pair plus a prominent draft-target readout.
///
/// Layout (top → bottom):
///
///   • Horizontal pager: [ Quick wheel ] | [ Fine Tune wheels ]
///     The currently active page is shown; the other side shows a
///     labelled teaser tap target, not live inactive wheels.
///   • Target numbers: large, monospaced read-out of the draft
///     duration. Updates from either Quick or Fine edits and is the
///     visible source of truth while editing.
///   • Confirm + Cancel buttons.
///
/// Both modes are *views* of one `state.draftSeconds`: the Quick
/// anchor and the Fine h/m/s are derived from it, so a Quick change
/// is reflected in Fine immediately and vice versa. Each picker
/// binding's `set` routes through the draft model, which drops the
/// emit unless that picker's mode is the active armed mode — so a
/// wheel still settling after a swap to the other mode cannot
/// overwrite the draft (no feedback loop, no `DispatchQueue` dances,
/// no UIKit observer). `quickSelectedPreset` (the bright highlight)
/// is set only by a direct Quick selection.
///
/// `state.draftSeconds` is the input session's draft. Confirm
/// commits it via `onSet`; Cancel discards it via `onCancel` —
/// the model on the parent ViewModel only learns about the
/// new value when Confirm fires.
public struct TargetShutterInputSheet: View {
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

    /// Host-supplied live wheel telemetry (the observer implementation lives
    /// in the app). `.none` by default — wheels update on settle only.
    @Environment(\.wheelTelemetry) private var wheelTelemetry

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

    public init(
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

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // `Use Target Shutter` row hosts the system switch.
                // Placed inline (not in the toolbar) so SwiftUI renders
                // the standard inline switch rather than the toolbar's
                // compact pill button. Off sets `isDraftCleared`;
                // Confirm then routes through `onClearTarget`. Cancel
                // after Off discards the draft change, preserving the
                // previously-committed target.
                TargetShutterEnabledToggleRow(isOn: targetShutterEnabledBinding)
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
                TargetShutterDraftReadout(
                    text: formattedDraft,
                    isCleared: state.isDraftCleared,
                    accessibilityLabel: targetNumbersAccessibilityLabel
                )
                .padding(.bottom, 6)

                // `.disabled` blocks wheel interaction and auto-dims
                // the pager (including the teaser tap targets) when
                // target is Off. The draft model also no-ops every
                // wheel emit while cleared, so a wheel still
                // mid-deceleration when the user flipped the switch
                // Off cannot mutate the draft.
                horizontalPager
                    .disabled(state.isDraftCleared)

                Spacer(minLength: 0)

                TargetShutterSheetFooter(
                    confirmLabel: confirmButtonLabel,
                    canConfirm: canConfirm,
                    onCancel: cancel,
                    onConfirm: confirm
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("Target Shutter")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
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
                    state.reArmDraft(seedSeconds: initialSeconds)
                } else {
                    state.clearDraft()
                }
            }
        )
    }

    // MARK: - Horizontal pager

    /// Horizontal pager containing the Quick page and the Fine Tune
    /// page. Uses `TabView` with the page style — same idiom as the
    /// camera-slot pager on the main calculator — because the paged
    /// container's gesture model defers cleanly to the nested wheel's
    /// vertical pan. A `ScrollView`-based
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
                    state.setActiveMode(.fine)
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
            // Host-owned live telemetry: reports the wheel's centre row while
            // it moves so the readout tracks the spin. Updates only the live
            // value, never the picker's bound selection, so momentum is kept.
            .background {
                wheelTelemetry.makeObserver { row in
                    guard Self.quickPresets.indices.contains(row) else { return }
                    state.applyLiveQuick(Self.quickPresets[row])
                }
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
                    state.setActiveMode(.quick)
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
                TargetShutterFineColumn(
                    title: "h",
                    range: 0...23,
                    value: fineHoursBinding,
                    accessibilityID: "target-shutter-hours-picker",
                    onLiveRow: { row in
                        // Compose against the *live* other-column values, not
                        // the settled draft, so spinning two wheels at once
                        // does not make the third reading flip back to its
                        // settled value between emits.
                        state.applyLiveFine(
                            hours: row,
                            minutes: state.liveFineMinutes,
                            seconds: state.liveFineSeconds
                        )
                    }
                )
                TargetShutterFineColumn(
                    title: "m",
                    range: 0...59,
                    value: fineMinutesBinding,
                    accessibilityID: "target-shutter-minutes-picker",
                    onLiveRow: { row in
                        state.applyLiveFine(
                            hours: state.liveFineHours,
                            minutes: row,
                            seconds: state.liveFineSeconds
                        )
                    }
                )
                TargetShutterFineColumn(
                    title: "s",
                    range: 0...59,
                    value: fineSecondsBinding,
                    accessibilityID: "target-shutter-seconds-picker",
                    onLiveRow: { row in
                        state.applyLiveFine(
                            hours: state.liveFineHours,
                            minutes: state.liveFineMinutes,
                            seconds: row
                        )
                    }
                )
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Target numbers + actions

    private var targetNumbersAccessibilityLabel: String {
        let base = "Draft target \(formattedDraft)"
        return state.isDraftCleared ? "\(base), Target Shutter off" : base
    }

    // MARK: - Bindings

    /// Mode-switch binding for the `TabView` selection.
    private var activeModeBinding: Binding<TargetShutterInputState.InputMode> {
        Binding(
            get: { state.activeMode },
            set: { newMode in
                state.setActiveMode(newMode)
            }
        )
    }

    /// Quick wheel binding. `get` derives the parking position (the
    /// nearest preset to the draft); `set` routes every selection
    /// through the model, which drops the emit unless Quick is the
    /// active armed mode — so a wheel still settling after a swap to
    /// Fine cannot mutate the draft.
    private var quickAnchorBinding: Binding<TimeInterval> {
        Binding(
            get: { state.quickWheelAnchor(in: Self.quickPresets) },
            set: { newPreset in
                state.applyQuickSelection(newPreset)
            }
        )
    }

    private var fineHoursBinding: Binding<Int> {
        Binding(
            get: { state.fineHours },
            set: { newH in
                state.applyFineSelection(
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
                state.applyFineSelection(
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
                state.applyFineSelection(
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
        // and that intermediate state must not be committable). Uses the
        // displayed value so a confirm tapped mid-spin reflects what the
        // user sees in the readout.
        state.isDraftCleared || state.displaySeconds > 0
    }

    private var formattedDraft: String {
        formattedDuration(state.displaySeconds)
    }

    private var confirmButtonLabel: String {
        "Confirm"
    }

    private func confirm() {
        if state.isDraftCleared {
            onClearTarget()
            return
        }
        // Fold any in-progress live value into the draft so a confirm tapped
        // before the wheel settles commits the value the user is seeing.
        state.commitLiveIntoDraft()
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

// MARK: - Input sheet leaf components

/// Sheet-header On/Off switch. The binding routes to the parent's
/// draft clear / re-arm logic; this leaf only renders the row.
private struct TargetShutterEnabledToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("Use Target Shutter")
                .font(.body)
                .foregroundStyle(.primary)
        }
        .tint(.accentColor)
        .accessibilityIdentifier("target-shutter-enabled-switch")
        .accessibilityHint("When off, Confirm removes the Target Shutter; Cancel restores the previously committed value.")
    }
}

/// Large, monospaced read-out of the current draft. The single
/// visible source of truth while editing — both Quick and Fine
/// edits update it immediately because both write to the draft.
/// Off state dims the readout rather than replacing it with `None` —
/// the duration is what Confirm would remove, so seeing it dimmed
/// previews the action.
private struct TargetShutterDraftReadout: View {
    let text: String
    let isCleared: Bool
    let accessibilityLabel: String

    var body: some View {
        Text(text)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isCleared ? .tertiary : .primary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("target-shutter-draft-readout")
            .accessibilityLabel(accessibilityLabel)
    }
}

/// A single Fine Tune wheel column (h / m / s). Renders a wheel
/// `Picker` bound through the parent's draft model. The picker's
/// settled value commits on settle; the host's live telemetry (if
/// injected) reports the centre row mid-spin via `onLiveRow`.
private struct TargetShutterFineColumn: View {
    @Environment(\.wheelTelemetry) private var wheelTelemetry

    let title: String
    let range: ClosedRange<Int>
    @Binding var value: Int
    let accessibilityID: String
    let onLiveRow: (Int) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: $value) {
                ForEach(range, id: \.self) { value in
                    Text("\(value)")
                        .monospacedDigit()
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            .background {
                wheelTelemetry.makeObserver { row in
                    guard range.contains(row) else { return }
                    onLiveRow(row)
                }
            }
            .accessibilityIdentifier(accessibilityID)
        }
    }
}

/// Confirm / Cancel footer. The parent owns the confirm/cancel flow
/// and the enabled state; this leaf only renders the two buttons.
private struct TargetShutterSheetFooter: View {
    @Environment(\.ptimerComponentTheme) private var theme

    let confirmLabel: String
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.recessedFill)
                    )
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("target-shutter-cancel-button")

            Button(action: onConfirm) {
                Text(confirmLabel)
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
}

/// Visual teaser shown alongside the active page inside the input
/// sheet's `TabView(.page)`. It does **not** render the inactive
/// mode's wheels — moving inactive wheel content while the active
/// wheel is being scrolled is the exact failure mode the C-direction
/// architecture is designed to avoid. The teaser is a labelled,
/// thin-outlined tap target that switches modes through the same
/// `state.setActiveMode(_:)` path the page-dot pager uses; both
/// modes read from the one draft, so the entering mode always shows
/// the current value.
private struct TargetShutterModeTeaser: View {
    enum Direction { case left, right }

    @Environment(\.ptimerComponentTheme) private var theme

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
                    .stroke(theme.separator, lineWidth: 1)
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

#endif
