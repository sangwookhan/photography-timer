import Foundation
import PTimerCore

/// Draft state for the Target Shutter input sheet.
///
/// `draftSeconds` is the single source of truth for the value Confirm
/// commits. The two input modes — Quick presets and Fine Tune
/// (h/m/s) — are two *views* of that one value, not independent
/// stores:
///
///   - The Fine h/m/s components are **derived** from `draftSeconds`,
///     so a Quick change is reflected in Fine the instant it lands —
///     there is no separate copy that can drift out of sync.
///   - The Quick wheel parks on the nearest preset to `draftSeconds`
///     (`quickWheelAnchor(in:)`), also derived.
///
/// Because the inactive mode's wheels are never rendered (the pager
/// shows a teaser, not live inactive wheels), nothing needs to be
/// "frozen" — both representations are pure functions of the draft
/// and are always consistent.
///
/// Late-emit safety is handled **in the model**, not by an external
/// observer: a wheel binding can fire after the user already swiped
/// to the other mode (a decelerating wheel still settling). The value
/// mutators no-op unless their source mode is the active one, so a
/// stale Quick emit arriving after the user moved to Fine (and the
/// reverse) cannot overwrite the draft. `activeMode` is written only
/// by `setActiveMode(_:)`.
///
/// `quickSelectedPreset` is the bright highlight on the Quick wheel.
/// It is set only by a direct Quick selection and cleared by Fine
/// edits and by entering Fine mode; entering Quick does not
/// auto-select.
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

    /// The draft target in whole seconds. Single source of truth for
    /// what Confirm will commit and for both modes' wheel positions.
    public private(set) var draftSeconds: Int

    /// Mode the user is currently editing in. Written only by
    /// `setActiveMode(_:)`.
    public private(set) var activeMode: InputMode

    /// Preset the user most recently chose via the Quick wheel.
    /// `nil` means no preset is bright. Set only by
    /// `applyQuickSelection`, cleared by Fine edits and by entering
    /// Fine mode.
    public private(set) var quickSelectedPreset: TimeInterval?

    /// Set when the photographer flips the sheet's `Use Target
    /// Shutter` switch Off — the draft is intentionally disabled,
    /// distinct from `draftSeconds == 0`. Confirm with this flag set
    /// commits a removal of the Target Shutter; Confirm with this
    /// flag false and `draftSeconds == 0` is rejected. While set, the
    /// value mutators no-op; the flag is cleared only by
    /// `reArmDraft(seedSeconds:)`.
    public private(set) var isDraftCleared: Bool

    /// Transient live value reported by the host's wheel telemetry while a
    /// wheel is moving (see `WheelTelemetry`). It feeds the readout only —
    /// `displaySeconds` prefers it — and is deliberately kept *separate* from
    /// `draftSeconds` so the picker bindings (which derive from
    /// `draftSeconds`) stay still during a spin and the wheel's momentum is
    /// not interrupted. Committed into `draftSeconds` on settle, on a mode
    /// switch, and on confirm; `nil` when no spin is in progress.
    public private(set) var liveDraftSeconds: Int?

    /// Fine Tune hours, derived from the draft.
    public var fineHours: Int { draftSeconds / 3600 }
    /// Fine Tune minutes, derived from the draft.
    public var fineMinutes: Int { (draftSeconds % 3600) / 60 }
    /// Fine Tune seconds, derived from the draft.
    public var fineSeconds: Int { draftSeconds % 60 }

    /// Total seconds derived from the draft.
    public var totalSeconds: Int { draftSeconds }

    /// Value to show in the readout: the live mid-spin value when a wheel is
    /// moving, otherwise the committed draft.
    public var displaySeconds: Int { liveDraftSeconds ?? draftSeconds }

    /// Quick wheel parking position: the nearest preset to the draft.
    /// Derived so the wheel always reflects the current value.
    public func quickWheelAnchor(in presets: [TimeInterval]) -> TimeInterval {
        Self.nearestPreset(to: TimeInterval(draftSeconds), in: presets)
            ?? TimeInterval(draftSeconds)
    }

    /// True when the draft equals one of the configured presets.
    /// Drives the optional "· Custom" header marker — value-based,
    /// independent of input source.
    public func quickIsExactMatch(in presets: [TimeInterval]) -> Bool {
        presets.contains(TimeInterval(draftSeconds))
    }

    private init(
        draftSeconds: Int,
        activeMode: InputMode,
        quickSelectedPreset: TimeInterval?,
        isDraftCleared: Bool
    ) {
        self.draftSeconds = draftSeconds
        self.activeMode = activeMode
        self.quickSelectedPreset = quickSelectedPreset
        self.isDraftCleared = isDraftCleared
        self.liveDraftSeconds = nil
    }

    /// Builds the initial state from a seed value.
    ///
    /// `initialEnabled` controls whether the sheet opens with the
    /// `Use Target Shutter` switch On or Off (no committed target —
    /// the previous duration is preserved as dimmed context but the
    /// wheels are disabled until the user toggles the switch).
    ///
    /// `activeMode` is chosen by the seed's relationship to the Quick
    /// preset ladder: an exact preset match opens in Quick, a custom
    /// duration opens in Fine Tune so the wheels that can express it
    /// are front and centre.
    public static func initial(
        seedSeconds: TimeInterval?,
        quickPresets: [TimeInterval],
        initialEnabled: Bool = true
    ) -> Self {
        let total = sanitizedSeed(seedSeconds)
        let matchesPreset = quickPresets.contains(TimeInterval(total))
        return Self(
            draftSeconds: total,
            activeMode: matchesPreset ? .quick : .fine,
            quickSelectedPreset: nil,
            isDraftCleared: !initialEnabled
        )
    }

    /// Applies a Quick preset selection. Writes the preset to the
    /// draft and marks it as the bright selection.
    ///
    /// No-ops unless Quick is the active mode and the draft is armed —
    /// a stale Quick emit arriving after the user swiped to Fine, or
    /// after they flipped the switch Off, must not mutate the draft.
    public mutating func applyQuickSelection(_ preset: TimeInterval) {
        guard !isDraftCleared, activeMode == .quick else { return }
        draftSeconds = Self.clampValue(preset)
        quickSelectedPreset = preset
        liveDraftSeconds = nil
    }

    /// Applies a Fine Tune wheel change. Writes the new total to the
    /// draft and clears any prior Quick selection.
    ///
    /// No-ops unless Fine is the active mode and the draft is armed —
    /// the symmetric late-emit / Off guard to `applyQuickSelection`.
    public mutating func applyFineSelection(hours: Int, minutes: Int, seconds: Int) {
        guard !isDraftCleared, activeMode == .fine else { return }
        draftSeconds = Self.clampTotal(hours * 3600 + minutes * 60 + seconds)
        quickSelectedPreset = nil
        liveDraftSeconds = nil
    }

    /// Live Quick telemetry (host wheel observer, mid-spin). Updates the
    /// readout value only — never `draftSeconds` or the picker selection —
    /// so the spinning wheel keeps its momentum. No-ops unless Quick is the
    /// active armed mode, so a stale emit from the inactive Quick wheel after
    /// a swap to Fine, or any emit while Off, is ignored.
    public mutating func applyLiveQuick(_ preset: TimeInterval) {
        guard !isDraftCleared, activeMode == .quick else { return }
        liveDraftSeconds = Self.clampValue(preset)
    }

    /// Live Fine telemetry (host wheel observer, mid-spin). Symmetric to
    /// `applyLiveQuick`.
    public mutating func applyLiveFine(hours: Int, minutes: Int, seconds: Int) {
        guard !isDraftCleared, activeMode == .fine else { return }
        liveDraftSeconds = Self.clampTotal(hours * 3600 + minutes * 60 + seconds)
    }

    /// Commits any in-progress live value into the draft (used before a mode
    /// switch and on confirm so the latest mid-spin value is not lost). A
    /// no-op while Off; always clears the live value.
    public mutating func commitLiveIntoDraft() {
        defer { liveDraftSeconds = nil }
        guard !isDraftCleared, let live = liveDraftSeconds else { return }
        draftSeconds = live
        quickSelectedPreset = nil
    }

    /// Mode switch entry point. Flushes any in-progress live value into the
    /// draft first, so switching while a wheel is still in flight carries the
    /// latest value across. The entering mode's wheels then read directly
    /// from the (derived) draft. Switching to Fine clears any Quick
    /// selection; switching to Quick does not auto-select.
    public mutating func setActiveMode(_ mode: InputMode) {
        commitLiveIntoDraft()
        activeMode = mode
        if mode == .fine {
            quickSelectedPreset = nil
        }
    }

    /// Toggles the input session into the cleared state (the sheet's
    /// `Target Shutter` switch flipped Off). `draftSeconds` is
    /// preserved so toggling back On restores the previous value
    /// without a snap; `quickSelectedPreset` is cleared.
    public mutating func clearDraft() {
        quickSelectedPreset = nil
        isDraftCleared = true
        liveDraftSeconds = nil
    }

    /// Re-arms the draft when the user flips the switch back On. If
    /// the preserved `draftSeconds` is already positive (the natural
    /// case), keeps it. Otherwise seeds from `seedSeconds` or the
    /// default.
    public mutating func reArmDraft(seedSeconds: TimeInterval?) {
        isDraftCleared = false
        liveDraftSeconds = nil
        guard draftSeconds == 0 else { return }
        draftSeconds = Self.sanitizedSeed(seedSeconds)
    }

    /// Closest preset to `value` by absolute distance, or `nil` for
    /// an empty preset list.
    public static func nearestPreset(
        to value: TimeInterval,
        in presets: [TimeInterval]
    ) -> TimeInterval? {
        presets.min(by: { abs($0 - value) < abs($1 - value) })
    }

    /// Resolves a seed value to a clamped, positive whole-second
    /// draft, falling back to the default seed for nil / non-finite /
    /// non-positive input.
    private static func sanitizedSeed(_ seedSeconds: TimeInterval?) -> Int {
        let resolved = seedSeconds.flatMap { value -> TimeInterval? in
            value.isFinite && value > 0 ? value : nil
        } ?? TimeInterval(defaultSeedSeconds)
        return min(max(1, Int(resolved.rounded())), maxTotalSeconds)
    }

    /// Clamps a positive Quick preset to `[1, max]`.
    private static func clampValue(_ value: TimeInterval) -> Int {
        min(max(1, Int(value.rounded())), maxTotalSeconds)
    }

    /// Clamps a Fine total to `[0, max]` — Fine wheels can park on
    /// 0/0/0 mid-edit, which is a valid (non-committable) draft.
    private static func clampTotal(_ raw: Int) -> Int {
        max(0, min(raw, maxTotalSeconds))
    }
}
