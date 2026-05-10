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
struct TargetShutterInputState: Equatable {
    /// Largest duration the wheels can express: 23h 59m 59s.
    static let maxTotalSeconds = 23 * 3600 + 59 * 60 + 59

    /// Default seed when the sheet has neither a per-slot target
    /// nor a recent value: 1 minute.
    static let defaultSeedSeconds = 60

    enum InputMode: Hashable {
        case quick
        case fine
    }

    /// The draft target in whole seconds. Single source of truth
    /// for what **Set** will commit.
    var draftSeconds: Int

    /// Mode the user is currently editing in.
    var activeMode: InputMode

    /// Preset the user most recently chose via the Quick wheel.
    /// `nil` means no preset is bright. Set only by `applyQuickTap`,
    /// cleared by Fine adjustments and by entering Fine mode.
    var quickSelectedPreset: TimeInterval?

    /// Quick wheel parking position. Stored, not derived. Resyncs
    /// from `draftSeconds` only when the user enters Quick mode, so
    /// while the user is scrolling Fine Tune the Quick wheel stays
    /// still even when its peek is visible.
    var quickWheelAnchor: TimeInterval

    /// Fine Tune wheel components. Stored, not derived. Resync from
    /// `draftSeconds` only when the user enters Fine mode, so while
    /// the user is scrolling Quick the Fine wheels stay still.
    var fineHours: Int
    var fineMinutes: Int
    var fineSeconds: Int

    /// Total seconds derived from the draft.
    var totalSeconds: Int { draftSeconds }

    /// True when the draft equals one of the configured presets.
    /// Drives the optional "· Custom" header marker — value-based,
    /// independent of input source.
    func quickIsExactMatch(in presets: [TimeInterval]) -> Bool {
        presets.contains(TimeInterval(draftSeconds))
    }

    /// Builds the initial state from a seed value. Both wheels are
    /// initialized to match the seed so the input sheet opens
    /// internally consistent.
    static func initial(
        seedSeconds: TimeInterval?,
        quickPresets: [TimeInterval]
    ) -> Self {
        let resolved = seedSeconds.flatMap { value -> TimeInterval? in
            value.isFinite && value > 0 ? value : nil
        } ?? TimeInterval(defaultSeedSeconds)
        let total = max(1, Int(resolved.rounded()))
        let clamped = min(total, maxTotalSeconds)
        let nearest = nearestPreset(to: TimeInterval(clamped), in: quickPresets)
            ?? TimeInterval(defaultSeedSeconds)
        return Self(
            draftSeconds: clamped,
            activeMode: .quick,
            quickSelectedPreset: nil,
            quickWheelAnchor: nearest,
            fineHours: clamped / 3600,
            fineMinutes: (clamped % 3600) / 60,
            fineSeconds: clamped % 60
        )
    }

    /// Applies a Quick wheel tap (or a continuous-row emit during
    /// scroll). Writes the preset to the draft and to the Quick
    /// wheel state, marks the preset as the active selection, and
    /// pins the active mode to Quick. Fine wheel state is left
    /// untouched so its peek view stays still.
    mutating func applyQuickTap(_ newPreset: TimeInterval) {
        let clamped = min(max(1, Int(newPreset.rounded())), Self.maxTotalSeconds)
        draftSeconds = clamped
        quickWheelAnchor = newPreset
        quickSelectedPreset = newPreset
        activeMode = .quick
    }

    /// Applies a Fine Tune wheel change (or a continuous-row emit
    /// during scroll). Writes the new total to the draft and to the
    /// Fine wheel state, clears any prior Quick selection, and pins
    /// the active mode to Fine. Quick wheel state is left untouched
    /// so its peek view stays still.
    mutating func applyFineChange(hours: Int, minutes: Int, seconds: Int) {
        let raw = hours * 3600 + minutes * 60 + seconds
        let clamped = max(0, min(raw, Self.maxTotalSeconds))
        draftSeconds = clamped
        fineHours = hours
        fineMinutes = minutes
        fineSeconds = seconds
        quickSelectedPreset = nil
        activeMode = .fine
    }

    /// Mode switch entry point. The entering mode's wheel state
    /// resyncs from the current `draftSeconds`; the exiting mode's
    /// state is preserved so swiping back doesn't snap it.
    /// Switching to Fine clears any Quick selection (the Quick
    /// highlight must not persist while Fine is the active source);
    /// switching to Quick does **not** auto-select — selection
    /// returns only when the user actually taps a preset.
    mutating func setActiveMode(_ mode: InputMode, quickPresets: [TimeInterval]) {
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
    static func nearestPreset(
        to value: TimeInterval,
        in presets: [TimeInterval]
    ) -> TimeInterval? {
        presets.min(by: { abs($0 - value) < abs($1 - value) })
    }
}
