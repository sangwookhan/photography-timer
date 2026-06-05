import Foundation

/// Draft state for the Target Shutter input sheet.
///
/// The input sheet has two modes — Quick presets and Fine Tune
/// (h/m/s). Both edit a single `draftSeconds` (the value Confirm
/// commits), but the wheel positions for each mode are stored
/// **independently**. This is what keeps the inactive mode visually
/// quiet:
///
///   - Scrolling the Quick wheel updates `draftSeconds` and
///     `quickWheelAnchor`. It does **not** touch `fineHours /
///     fineMinutes / fineSeconds`.
///   - Scrolling Fine Tune updates `draftSeconds` and the h/m/s
///     fields. It does **not** touch `quickWheelAnchor`.
///
/// The wheel positions resync from the draft only when the user
/// switches mode — `setActiveMode(_:quickPresets:)` writes the new
/// mode's wheel state from `draftSeconds`, and the previously-active
/// mode's state is left alone (so swiping back doesn't snap it).
///
/// `quickSelectedPreset` is the visual highlight on the Quick wheel.
/// It is set only by `applyQuickTap` (direct user choice) and
/// cleared by Fine adjustments and by entering Fine mode. Entering
/// Quick mode does **not** auto-select; the wheel can park near the
/// draft without claiming a selection.
///
/// Mode transitions are the **only** writer of `activeMode`. The
/// value mutators `applyQuickTap` / `applyFineChange` deliberately
/// do not touch `activeMode`. Combined with view-layer guards that
/// drop wheel-observer / Picker-binding emits whose source mode
/// does not match the current `activeMode`, this kills the bug
/// where a late Fine emit (fired after the user already swiped to
/// Quick) would yank the sheet back to Fine.
public struct TargetShutterInputState: Equatable {
    /// Largest duration the wheels can express: 23h 59m 59s.
    public static let maxTotalSeconds = 23 * 3600 + 59 * 60 + 59

    /// Default seed when the sheet has neither a per-slot target
    /// nor a recent value: 1 minute.
    public static let defaultSeedSeconds = 60

    public enum InputMode: Hashable {
        case quick
        case fine
    }

    /// The draft target in whole seconds. Single source of truth
    /// for what **Set** will commit.
    public var draftSeconds: Int

    /// Mode the user is currently editing in.
    public var activeMode: InputMode

    /// Preset the user most recently chose via the Quick wheel.
    /// `nil` means no preset is bright. Set only by `applyQuickTap`,
    /// cleared by Fine adjustments and by entering Fine mode.
    public var quickSelectedPreset: TimeInterval?

    /// Quick wheel parking position. Stored, not derived. Resyncs
    /// from `draftSeconds` only when the user enters Quick mode, so
    /// while the user is scrolling Fine Tune the Quick wheel stays
    /// still even when its peek is visible.
    public var quickWheelAnchor: TimeInterval

    /// Fine Tune wheel components. Stored, not derived. Resync from
    /// `draftSeconds` only when the user enters Fine mode, so while
    /// the user is scrolling Quick the Fine wheels stay still.
    public var fineHours: Int
    public var fineMinutes: Int
    public var fineSeconds: Int

    /// Set when the photographer flips the sheet's `Use Target
    /// Shutter` switch Off — the draft is intentionally disabled,
    /// distinct from `draftSeconds == 0` (which can result from Fine
    /// wheels parked on 0/0/0 mid-edit). Confirm with this flag set
    /// commits a removal of the Target Shutter; Confirm with this
    /// flag false and `draftSeconds == 0` is rejected as it always
    /// was.
    ///
    /// While the flag is set, `applyQuickTap` / `applyFineChange`
    /// / their continuous-scroll variants are no-ops — stale wheel
    /// emits arriving after the user flipped the switch Off must
    /// not silently re-arm the draft. The flag is cleared **only**
    /// by `reArmDraft(...)` (the toggle-On path). The flag also
    /// survives mode transitions so a user can switch Off in Fine,
    /// swipe to Quick, and still see the disabled state.
    public var isDraftCleared: Bool

    public init(
        draftSeconds: Int,
        activeMode: InputMode,
        quickSelectedPreset: TimeInterval?,
        quickWheelAnchor: TimeInterval,
        fineHours: Int,
        fineMinutes: Int,
        fineSeconds: Int,
        isDraftCleared: Bool
    ) {
        self.draftSeconds = draftSeconds
        self.activeMode = activeMode
        self.quickSelectedPreset = quickSelectedPreset
        self.quickWheelAnchor = quickWheelAnchor
        self.fineHours = fineHours
        self.fineMinutes = fineMinutes
        self.fineSeconds = fineSeconds
        self.isDraftCleared = isDraftCleared
    }

    /// Total seconds derived from the draft.
    public var totalSeconds: Int { draftSeconds }

    /// True when the draft equals one of the configured presets.
    /// Drives the optional "· Custom" header marker — value-based,
    /// independent of input source.
    public func quickIsExactMatch(in presets: [TimeInterval]) -> Bool {
        presets.contains(TimeInterval(draftSeconds))
    }

    /// Builds the initial state from a seed value. Both wheels are
    /// initialized to match the seed so the input sheet opens
    /// internally consistent.
    ///
    /// `initialEnabled` controls whether the sheet opens with the
    /// `Use Target Shutter` switch On (a committed target exists or
    /// the caller wants the user editing immediately) or Off (no
    /// committed target — the previous duration is preserved as
    /// dimmed context but the wheels are disabled until the user
    /// toggles the switch).
    ///
    /// `activeMode` is chosen by the seed's relationship to the
    /// Quick preset ladder:
    ///   - seed exactly matches a Quick preset → `.quick`
    ///   - seed is a custom duration (e.g. `2h 9m`) → `.fine`
    /// This means re-opening the sheet on a custom value drops the
    /// user directly into Fine Tune so the wheels they need are
    /// front and centre.
    public static func initial(
        seedSeconds: TimeInterval?,
        quickPresets: [TimeInterval],
        initialEnabled: Bool = true
    ) -> Self {
        let resolved = seedSeconds.flatMap { value -> TimeInterval? in
            value.isFinite && value > 0 ? value : nil
        } ?? TimeInterval(defaultSeedSeconds)
        let total = max(1, Int(resolved.rounded()))
        let clamped = min(total, maxTotalSeconds)
        let nearest = nearestPreset(to: TimeInterval(clamped), in: quickPresets)
            ?? TimeInterval(defaultSeedSeconds)
        let matchesPreset = quickPresets.contains(TimeInterval(clamped))
        return Self(
            draftSeconds: clamped,
            activeMode: matchesPreset ? .quick : .fine,
            quickSelectedPreset: nil,
            quickWheelAnchor: nearest,
            fineHours: clamped / 3600,
            fineMinutes: (clamped % 3600) / 60,
            fineSeconds: clamped % 60,
            isDraftCleared: !initialEnabled
        )
    }

    /// Applies a settled Quick preset selection (Picker binding setter
    /// on settle). Writes the preset to the draft, **writes back to
    /// the Quick wheel anchor**, and marks the preset as the active
    /// selection. Fine wheel state is left untouched.
    ///
    /// **Does not change `activeMode`.** The caller is responsible
    /// for filtering out stale Quick emits that fire after the user
    /// already swiped away from Quick — the view-layer wheel
    /// observers and Picker binding setters guard on the current
    /// `activeMode` before invoking this method.
    ///
    /// **No-ops when `isDraftCleared` (target is Off).** The sheet's
    /// `Use Target Shutter` switch is the only path to re-enable;
    /// stale wheel emits arriving after the user flips the switch
    /// Off (mid-deceleration, etc.) must not silently re-arm the
    /// draft. Call `reArmDraft(...)` to exit the Off state.
    ///
    /// Use `applyQuickContinuousScroll(_:)` instead for mid-scroll
    /// observer callbacks — that variant deliberately skips the
    /// wheel-anchor write so UIPickerView's deceleration is not
    /// interrupted by a SwiftUI-driven `selectRow(_:animated:)`.
    public mutating func applyQuickTap(_ newPreset: TimeInterval) {
        guard !isDraftCleared else { return }
        let clamped = min(max(1, Int(newPreset.rounded())), Self.maxTotalSeconds)
        draftSeconds = clamped
        quickWheelAnchor = newPreset
        quickSelectedPreset = newPreset
    }

    /// Mid-scroll Quick observer variant. Updates the draft readout
    /// and the visual `quickSelectedPreset` highlight, but
    /// **deliberately does not touch `quickWheelAnchor`** — the
    /// Picker reads its selection from that field, and writing to it
    /// mid-deceleration triggers SwiftUI to call
    /// `UIPickerView.selectRow(_:animated:)` which interrupts the
    /// natural ease-out. The anchor catches up on settle via
    /// `applyQuickTap`.
    ///
    /// **No-ops when `isDraftCleared`.** Same rationale as
    /// `applyQuickTap`.
    public mutating func applyQuickContinuousScroll(_ newPreset: TimeInterval) {
        guard !isDraftCleared else { return }
        let clamped = min(max(1, Int(newPreset.rounded())), Self.maxTotalSeconds)
        draftSeconds = clamped
        quickSelectedPreset = newPreset
    }

    /// Applies a settled Fine Tune row commit (Picker binding setter
    /// on settle). Writes the new total to the draft **and to the
    /// Fine wheel state**, and clears any prior Quick selection.
    /// Quick wheel state is left untouched.
    ///
    /// **Does not change `activeMode`.** Same rationale as
    /// `applyQuickTap`: stale Fine emits arriving after a mode
    /// switch are filtered out at the view layer.
    ///
    /// **No-ops when `isDraftCleared`.**
    ///
    /// Use `applyFineContinuousScroll(hours:minutes:seconds:)`
    /// instead for mid-scroll observer callbacks.
    public mutating func applyFineChange(hours: Int, minutes: Int, seconds: Int) {
        guard !isDraftCleared else { return }
        let raw = hours * 3600 + minutes * 60 + seconds
        let clamped = max(0, min(raw, Self.maxTotalSeconds))
        draftSeconds = clamped
        fineHours = hours
        fineMinutes = minutes
        fineSeconds = seconds
        quickSelectedPreset = nil
    }

    /// Mid-scroll Fine observer variant. Updates the draft readout
    /// only — **deliberately does not write `fineHours`, `fineMinutes`,
    /// or `fineSeconds`** — so the per-column Picker bindings see no
    /// state change and UIPickerView's deceleration is not
    /// interrupted. The Fine field values catch up on settle via
    /// `applyFineChange`.
    ///
    /// **No-ops when `isDraftCleared`.**
    public mutating func applyFineContinuousScroll(hours: Int, minutes: Int, seconds: Int) {
        guard !isDraftCleared else { return }
        let raw = hours * 3600 + minutes * 60 + seconds
        let clamped = max(0, min(raw, Self.maxTotalSeconds))
        draftSeconds = clamped
        quickSelectedPreset = nil
    }

    /// Toggles the input session into the cleared state (the sheet's
    /// `Target Shutter` switch flipped Off). Confirm after this
    /// commits a removal of the Target Shutter (the sheet's
    /// `onClearTarget` runs); Cancel after this preserves the
    /// previously-committed target because the sheet only mutates
    /// committed state on Confirm.
    ///
    /// `quickSelectedPreset` is cleared, but `draftSeconds`,
    /// `quickWheelAnchor`, and `fineHours / fineMinutes / fineSeconds`
    /// are intentionally preserved so toggling the switch back On
    /// can restore the previous draft without a snap.
    public mutating func clearDraft() {
        quickSelectedPreset = nil
        isDraftCleared = true
    }

    /// Re-arms the draft when the user flips the Target Shutter
    /// switch back On after toggling it Off. If the preserved
    /// `draftSeconds` is already positive (the natural case — the
    /// switch only toggled the flag), keeps it as-is. Otherwise
    /// seeds the draft from the provided seed value (e.g. the
    /// initial committed target / last-used memory) or falls back
    /// to the default seed.
    public mutating func reArmDraft(seedSeconds: TimeInterval?, quickPresets: [TimeInterval]) {
        isDraftCleared = false
        guard draftSeconds == 0 else {
            return
        }
        let resolved = seedSeconds.flatMap { value -> TimeInterval? in
            value.isFinite && value > 0 ? value : nil
        } ?? TimeInterval(Self.defaultSeedSeconds)
        let total = min(max(1, Int(resolved.rounded())), Self.maxTotalSeconds)
        draftSeconds = total
        fineHours = total / 3600
        fineMinutes = (total % 3600) / 60
        fineSeconds = total % 60
        if let nearest = Self.nearestPreset(
            to: TimeInterval(total),
            in: quickPresets
        ) {
            quickWheelAnchor = nearest
        }
    }

    /// Mode switch entry point. The entering mode's wheel state
    /// resyncs from the current `draftSeconds`; the exiting mode's
    /// state is preserved so swiping back doesn't snap it.
    /// Switching to Fine clears any Quick selection (the Quick
    /// highlight must not persist while Fine is the active source);
    /// switching to Quick does **not** auto-select — selection
    /// returns only when the user actually taps a preset.
    public mutating func setActiveMode(_ mode: InputMode, quickPresets: [TimeInterval]) {
        activeMode = mode
        switch mode {
        case .quick:
            if let nearest = Self.nearestPreset(
                to: TimeInterval(draftSeconds),
                in: quickPresets
            ) {
                quickWheelAnchor = nearest
            }
        case .fine:
            fineHours = draftSeconds / 3600
            fineMinutes = (draftSeconds % 3600) / 60
            fineSeconds = draftSeconds % 60
            quickSelectedPreset = nil
        }
    }

    /// Closest preset to `value` by absolute distance, or `nil` for
    /// an empty preset list.
    public static func nearestPreset(
        to value: TimeInterval,
        in presets: [TimeInterval]
    ) -> TimeInterval? {
        presets.min(by: { abs($0 - value) < abs($1 - value) })
    }
}
