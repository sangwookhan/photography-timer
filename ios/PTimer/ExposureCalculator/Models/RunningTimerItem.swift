import Foundation

/// View-facing snapshot of a single running/paused/completed timer, the
/// emission shape consumed by the workspace UI (compact dock + large
/// view + lock-screen coordinator). Carries the metadata strings that
/// the ViewModel composes (timer `name`, `basisSummary`) alongside a
/// frozen `referenceDate` so display state computed off this struct
/// stays deterministic across renders.
///
/// `TimerWorkspaceModel` builds and publishes these as the source of
/// truth; the view-model facade republishes the same array so existing
/// view bindings continue to read the same surface.
struct RunningTimerItem: Identifiable, Equatable {
    private static let stabilityEpsilon = ExposureCalculator.stabilityEpsilon

    let id: UUID
    let order: Int
    let name: String
    let basisSummary: String
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date?
    let pausedRemainingTime: TimeInterval?
    let pausedAt: Date?
    let status: TimerStatus
    let referenceDate: Date
    /// Camera slot the timer was started from. Optional so manual or
    /// non-camera-slot timers (e.g., timers restored from older
    /// snapshots without slot identity) stay decoupled from slot
    /// identity. Kept as a separate axis from the timer's
    /// exposure-source tag.
    let cameraSlot: CameraSlotIdentity?
    /// Canonical film stock name captured at start time.
    /// `nil` indicates a digital workflow (no film selected).
    let filmDisplayName: String?
    /// Optional profile qualifier (e.g. `"Unofficial"`) captured at
    /// start time so a later switch of the active film does not
    /// retroactively rewrite this timer's identity.
    let filmProfileQualifier: String?
    /// Which exposure stream this timer was started from. Optional so
    /// older snapshots without the field decode unchanged; UI surfaces
    /// fall back gracefully when absent.
    let exposureSource: ExposureTimerSource?
    /// Captured-at-start flag: true when the timer was started from a
    /// formula-extrapolated corrected exposure outside manufacturer
    /// guidance. Defaults to `false` for older snapshots and for the
    /// supported quantified path.
    let isOutsideManufacturerGuidance: Bool

    init(
        id: UUID,
        order: Int,
        name: String,
        basisSummary: String,
        duration: TimeInterval,
        startDate: Date,
        endDate: Date?,
        pausedRemainingTime: TimeInterval?,
        pausedAt: Date?,
        status: TimerStatus,
        referenceDate: Date,
        cameraSlot: CameraSlotIdentity? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSource: ExposureTimerSource? = nil,
        isOutsideManufacturerGuidance: Bool = false
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.basisSummary = basisSummary
        self.duration = duration
        self.startDate = startDate
        self.endDate = endDate
        self.pausedRemainingTime = pausedRemainingTime
        self.pausedAt = pausedAt
        self.status = status
        self.referenceDate = referenceDate
        self.cameraSlot = cameraSlot
        self.filmDisplayName = filmDisplayName
        self.filmProfileQualifier = filmProfileQualifier
        self.exposureSource = exposureSource
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
    }

    /// Convenience packaging of the slot + film + source identity
    /// fields. Used by the workspace snapshot to compose dock/sheet
    /// identity cues without re-deriving the same composition rule
    /// in two places.
    ///
    /// Returns `nil` when the timer has no exposure source — that's
    /// the "manual" path (external precomputed shutter) which must
    /// not inherit camera/film/source identity. Identity-bearing
    /// timers always carry a non-nil `exposureSource`; the snapshot
    /// is built from those fields and never has to fabricate one.
    var identitySnapshot: ExposureTimerIdentitySnapshot? {
        guard let exposureSource else {
            return nil
        }

        return ExposureTimerIdentitySnapshot(
            cameraSlot: cameraSlot,
            filmDisplayName: filmDisplayName,
            filmProfileQualifier: filmProfileQualifier,
            exposureSource: exposureSource,
            isOutsideManufacturerGuidance: isOutsideManufacturerGuidance
        )
    }

    var remainingTime: TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return sanitizeRemainingTime(endDate.timeIntervalSince(referenceDate))
        case .paused:
            return sanitizeRemainingTime(pausedRemainingTime ?? 0)
        case .completed:
            return 0
        }
    }

    var elapsedTime: TimeInterval {
        assert(!remainingTime.isNaN, "Remaining time must not be NaN.")
        return max(0, duration - remainingTime)
    }

    var completedAt: Date? {
        guard status == .completed, let endDate else {
            return nil
        }

        return endDate
    }

    private func sanitizeRemainingTime(_ value: TimeInterval) -> TimeInterval {
        assert(!value.isNaN, "Remaining time input must not be NaN.")
        let clamped = max(0, value)
        return clamped < Self.stabilityEpsilon ? 0 : clamped
    }
}

/// Stable presentation order for the timer workspace: active timers
/// (running + paused) first in LIFO insertion order, then completed
/// timers in completion-desc order, with a final tiebreak on stable
/// `id.uuidString` so equal keys produce a deterministic sequence.
enum TimerWorkspaceOrdering {
    static func sort(_ timers: [RunningTimerItem]) -> [RunningTimerItem] {
        timers.sorted(by: areInPresentationOrder(lhs:rhs:))
    }

    static func areInPresentationOrder(lhs: RunningTimerItem, rhs: RunningTimerItem) -> Bool {
        let lhsGroup = presentationGroup(lhs.status)
        let rhsGroup = presentationGroup(rhs.status)

        if lhsGroup != rhsGroup {
            return lhsGroup < rhsGroup
        }

        switch lhsGroup {
        case 0:
            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
        case 1:
            if lhs.completedAt != rhs.completedAt {
                return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }

            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
        default:
            break
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func presentationGroup(_ status: TimerStatus) -> Int {
        switch status {
        case .running, .paused:
            return 0
        case .completed:
            return 1
        }
    }
}
