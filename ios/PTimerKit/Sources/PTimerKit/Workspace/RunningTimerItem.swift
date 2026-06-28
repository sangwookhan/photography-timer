// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

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
public struct RunningTimerItem: Identifiable, Equatable {
    private static let stabilityEpsilon = ExposureCalculator.stabilityEpsilon

    public let id: UUID
    public let order: Int
    public let name: String
    public let basisSummary: String
    public let duration: TimeInterval
    public let startDate: Date
    public let endDate: Date?
    public let pausedRemainingTime: TimeInterval?
    public let pausedAt: Date?
    public let status: TimerStatus
    public let referenceDate: Date
    /// Camera slot the timer was started from. Optional so manual or
    /// non-camera-slot timers (e.g., timers restored from older
    /// snapshots without slot identity) stay decoupled from slot
    /// identity. Kept as a separate axis from the timer's
    /// exposure-source tag.
    public let cameraSlot: CameraSlotIdentity?
    /// Canonical film stock name captured at start time.
    /// `nil` indicates a digital workflow (no film selected).
    public let filmDisplayName: String?
    /// Optional profile qualifier (e.g. `"Unofficial"`) captured at
    /// start time so a later switch of the active film does not
    /// retroactively rewrite this timer's identity.
    public let filmProfileQualifier: String?
    /// Which exposure stream this timer was started from. Optional so
    /// older snapshots without the field decode unchanged; UI surfaces
    /// fall back gracefully when absent.
    public let exposureSource: ExposureTimerSource?
    /// Captured-at-start flag: true when the timer was started from a
    /// formula prediction outside the supported source range. Defaults
    /// to `false` for older snapshots and for the supported quantified
    /// path.
    public let isOutsideManufacturerGuidance: Bool
    /// Captured-at-start identity summary for timers started
    /// from a custom (`.userDefined`) profile. Optional so preset /
    /// unofficial / non-film timers and older snapshots decode
    /// unchanged.
    public let customProfileSummary: String?
    /// Captured-at-start display label of the selected reciprocity
    /// model (PTIMER-171). Non-nil only for non-default model
    /// selections; `nil` (default model / older snapshot) renders
    /// exactly as before.
    public let selectedModelLabel: String?
    /// Canonical ND strength in stops captured at start (PTIMER-187).
    /// Source of truth for the timer card's basis ND token, rendered
    /// in the current notation mode. `nil` when no ND value applies.
    public let ndStops: Double?
    /// Base shutter (seconds) captured at start (PTIMER-187).
    public let baseShutterSeconds: TimeInterval?
    /// Reciprocity-adjusted shutter (seconds) captured at start
    /// (PTIMER-187); the basis `Adj` segment for corrected/target
    /// timers.
    public let adjustedShutterSeconds: TimeInterval?
    /// Remaining time recorded when the timer was canceled. Non-nil
    /// only for canceled records; lets the history surface show how
    /// much was left at the stop (e.g. "Canceled · 51s left").
    public let canceledRemainingTime: TimeInterval?

    public init(
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
        isOutsideManufacturerGuidance: Bool = false,
        customProfileSummary: String? = nil,
        selectedModelLabel: String? = nil,
        ndStops: Double? = nil,
        baseShutterSeconds: TimeInterval? = nil,
        adjustedShutterSeconds: TimeInterval? = nil,
        canceledRemainingTime: TimeInterval? = nil
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
        self.customProfileSummary = customProfileSummary
        self.selectedModelLabel = selectedModelLabel
        self.ndStops = ndStops
        self.baseShutterSeconds = baseShutterSeconds
        self.adjustedShutterSeconds = adjustedShutterSeconds
        self.canceledRemainingTime = canceledRemainingTime
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
    public var identitySnapshot: ExposureTimerIdentitySnapshot? {
        guard let exposureSource else {
            return nil
        }

        return ExposureTimerIdentitySnapshot(
            cameraSlot: cameraSlot,
            filmDisplayName: filmDisplayName,
            filmProfileQualifier: filmProfileQualifier,
            exposureSource: exposureSource,
            isOutsideManufacturerGuidance: isOutsideManufacturerGuidance,
            customProfileSummary: customProfileSummary,
            selectedModelLabel: selectedModelLabel
        )
    }

    public var remainingTime: TimeInterval {
        assert(duration.isFinite && duration > 0, "Timer duration must be finite and positive.")
        switch status {
        case .running:
            guard let endDate else {
                return 0
            }
            return sanitizeRemainingTime(endDate.timeIntervalSince(referenceDate))
        case .paused:
            return sanitizeRemainingTime(pausedRemainingTime ?? 0)
        case .completed, .canceled:
            return 0
        }
    }

    public var elapsedTime: TimeInterval {
        assert(!remainingTime.isNaN, "Remaining time must not be NaN.")
        return max(0, duration - remainingTime)
    }

    public var completedAt: Date? {
        guard status == .completed, let endDate else {
            return nil
        }

        return endDate
    }

    /// Terminal timestamp used to order the history area: completion
    /// time for completed timers, cancellation time for canceled
    /// timers. `nil` for active (running/paused) timers, which sort in
    /// their own group ahead of the history section.
    public var terminalAt: Date? {
        switch status {
        case .completed, .canceled:
            return endDate
        case .running, .paused:
            return nil
        }
    }

    private func sanitizeRemainingTime(_ value: TimeInterval) -> TimeInterval {
        assert(!value.isNaN, "Remaining time input must not be NaN.")
        let clamped = max(0, value)
        return clamped < Self.stabilityEpsilon ? 0 : clamped
    }
}

/// Stable presentation order for the timer workspace: active timers
/// (running + paused) first in LIFO insertion order, then terminal
/// records (completed + canceled) in terminal-time-desc order, with a
/// final tiebreak on stable `id.uuidString` so equal keys produce a
/// deterministic sequence.
public enum TimerWorkspaceOrdering {
    public static func sort(_ timers: [RunningTimerItem]) -> [RunningTimerItem] {
        timers.sorted(by: areInPresentationOrder(lhs:rhs:))
    }

    public static func areInPresentationOrder(lhs: RunningTimerItem, rhs: RunningTimerItem) -> Bool {
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
            if lhs.terminalAt != rhs.terminalAt {
                return (lhs.terminalAt ?? .distantPast) > (rhs.terminalAt ?? .distantPast)
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
        case .completed, .canceled:
            return 1
        }
    }
}
