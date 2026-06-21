// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum FilmModeReciprocityStateTone: Equatable {
    case trusted
    case measured
    case caution
    case limitedGuidance
    case unsupported
}

public struct FilmModeReciprocityStateDisplayState: Equatable {
    public let badgeText: String
    public let tone: FilmModeReciprocityStateTone
    public let infoText: String
    public let showsInfoAffordance: Bool
    public init(badgeText: String, tone: FilmModeReciprocityStateTone, infoText: String, showsInfoAffordance: Bool) {
        self.badgeText = badgeText
        self.tone = tone
        self.infoText = infoText
        self.showsInfoAffordance = showsInfoAffordance
    }
}

public struct FilmModeTimerActionState: Equatable {
    public let targetSeconds: TimeInterval?
    public let canStartTimer: Bool
    /// True when the timer would start from a formula prediction that
    /// sits outside the manufacturer's supported source range. The
    /// play-button presenter renders a warning-oriented treatment when
    /// this flag is set, but the timer still starts because the user
    /// has a numeric value to commit to.
    public let isOutsideManufacturerGuidance: Bool
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(
        targetSeconds: TimeInterval?,
        canStartTimer: Bool,
        isOutsideManufacturerGuidance: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.targetSeconds = targetSeconds
        self.canStartTimer = canStartTimer
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

public enum FilmModeCorrectedExposureDisplayKind: Equatable {
    case quantified
    case limitedGuidance
    case unsupported
    case noFilmSelected
}

public struct FilmModeCorrectedExposureDisplayState: Equatable {
    public let kind: FilmModeCorrectedExposureDisplayKind
    public let correctedExposureSeconds: TimeInterval?
    public let primaryText: String
    public let secondaryText: String
    public let usesNumericExposure: Bool
    public init(kind: FilmModeCorrectedExposureDisplayKind, correctedExposureSeconds: TimeInterval?, primaryText: String, secondaryText: String, usesNumericExposure: Bool) {
        self.kind = kind
        self.correctedExposureSeconds = correctedExposureSeconds
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.usesNumericExposure = usesNumericExposure
    }
}

public struct FilmModeExposureResultState: Equatable {
    public let adjustedShutterSeconds: TimeInterval
    public let reciprocityState: FilmModeReciprocityStateDisplayState
    public let adjustedShutterAction: FilmModeTimerActionState
    public let correctedExposure: FilmModeCorrectedExposureDisplayState
    public let correctedExposureAction: FilmModeTimerActionState

    public var hasQuantifiedCorrectedExposure: Bool {
        correctedExposure.usesNumericExposure
    }
    public init(adjustedShutterSeconds: TimeInterval, reciprocityState: FilmModeReciprocityStateDisplayState, adjustedShutterAction: FilmModeTimerActionState, correctedExposure: FilmModeCorrectedExposureDisplayState, correctedExposureAction: FilmModeTimerActionState) {
        self.adjustedShutterSeconds = adjustedShutterSeconds
        self.reciprocityState = reciprocityState
        self.adjustedShutterAction = adjustedShutterAction
        self.correctedExposure = correctedExposure
        self.correctedExposureAction = correctedExposureAction
    }
}
