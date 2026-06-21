// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Granularity of one increment along an exposure scale. Treat
/// `oneThirdStop` as a first-class step, not a display-only
/// formatting choice — the **shutter** ladder changes with the
/// selected mode (the shipping product runs on the one-third-stop
/// shutter ladder; per `docs/specs/Calculator.md` §1.4 the ND ladder
/// stays whole-stop in every shipping mode).
///
/// `.fullStop` is retained as a reserved scale for tests and a future
/// Settings preference; the shipping calculator does not surface a
/// runtime scale selector.
public enum ExposureScaleMode: String, Codable, CaseIterable, Sendable {
    case fullStop
    case oneThirdStop
}

extension ExposureScaleMode {
    /// Stops covered by one step on this scale.
    /// `fullStop` → 1.0; `oneThirdStop` → 1/3.
    public var stopsPerStep: Double {
        switch self {
        case .fullStop:
            return 1.0
        case .oneThirdStop:
            return 1.0 / 3.0
        }
    }
}

/// One shutter-speed entry on an exposure scale's shutter ladder.
/// `seconds` is the value the picker displays and the calc engine
/// consumes; the type is intentionally narrow so future scales can
/// evolve formatting metadata independently of seconds storage.
public struct ShutterStep: Equatable, Hashable, Sendable {
    public let seconds: Double

    public init(seconds: Double) {
        self.seconds = seconds
    }
}

/// One ND-filter entry on an exposure scale's ND ladder, expressed
/// in stops. Fractional values are representable on the type as
/// **reserved domain infrastructure** so a future custom /
/// variable-ND workflow can flow through the same calculation and
/// persistence path; the shipping ND picker enumerates whole stops
/// only (per `docs/specs/Calculator.md` §2.2). `wholeStops` is
/// non-nil only when the step lies on a whole-stop boundary, which
/// is what the legacy integer calc API
/// (`ExposureCalculator.calculate(baseShutterSeconds:stop: Int)`)
/// consumes.
public struct NDStep: Equatable, Hashable, Sendable {
    public let stops: Double

    public init(stops: Double) {
        self.stops = stops
    }

    public var isWholeStop: Bool {
        abs(stops - stops.rounded()) <= ExposureCalculator.stabilityEpsilon
    }

    public var wholeStops: Int? {
        isWholeStop ? Int(stops.rounded()) : nil
    }
}

/// Canonical scale data for one `ExposureScaleMode`. Picker UI
/// reads `shutterSteps` / `ndSteps` from the active scale; the
/// calc layer reads `mode.stopsPerStep` and routes through the
/// fractional-aware `NDStep` overload of the calculator.
///
/// The scale is the single source of truth for "what values does
/// the user pick from": picker rows shall not maintain a parallel
/// list.
public struct ExposureScale: Equatable, Sendable {
    public let mode: ExposureScaleMode
    public let shutterSteps: [ShutterStep]
    public let ndSteps: [NDStep]

    public init(mode: ExposureScaleMode, shutterSteps: [ShutterStep], ndSteps: [NDStep]) {
        self.mode = mode
        self.shutterSteps = shutterSteps
        self.ndSteps = ndSteps
    }
}

extension ExposureScale {
    /// Default scale used by the shipping calculator. Backed by
    /// `ExposureCalculator.fullStopShutterSpeeds` so every change to
    /// the canonical full-stop ladder shows up here without
    /// duplication, and an integer ND ladder spanning 0…30 stops to
    /// match the picker range that's been in production since
    /// PTIMER-19.
    public static let fullStop: ExposureScale = ExposureScale(
        mode: .fullStop,
        shutterSteps: ExposureCalculator.fullStopShutterSpeeds.map(ShutterStep.init(seconds:)),
        ndSteps: (0...maximumWholeNDStops).map { NDStep(stops: Double($0)) }
    )

    /// Densified shutter ladder paired with the whole-stop ND ladder —
    /// the shipping calculator scale. Shutter is the geometric-mean
    /// densified ladder (55 entries spanning 1/8000…30s); ND stays on
    /// the integer `0…maximumWholeNDStops` ladder because the shipping
    /// product treats fractional ND as out-of-scope (real-world fixed
    /// ND filters ship in whole-stop strengths). The fractional-aware
    /// `NDStep` type is retained as a reserved domain primitive (e.g.
    /// `thirdStopCount` for persistence round-trip) so a future
    /// custom/variable-ND workflow can route through the same calc
    /// path without redesigning the model layer; that capability
    /// shall not surface in the shipping ND picker.
    /// (Per Calculator spec §2.2, §2.3.)
    public static let oneThirdStop: ExposureScale = ExposureScale(
        mode: .oneThirdStop,
        shutterSteps: oneThirdStopShutterSteps(
            fromFullStops: ExposureCalculator.fullStopShutterSpeeds
        ),
        ndSteps: (0...maximumWholeNDStops).map { NDStep(stops: Double($0)) }
    )

    /// The shipping calculator scale. Routes through the one-third-stop
    /// ladders; the full-stop scale (`.fullStop`) is kept in the model
    /// only for tests and the future Settings preference described in
    /// `docs/specs/Calculator.md` §1.4.
    public static let `default`: ExposureScale = .oneThirdStop

    /// Maximum whole ND stops the calculator supports. Hoisted to a
    /// single constant so the full-stop scale and the one-third-stop
    /// scale stay in lockstep instead of repeating `0...30`.
    public static let maximumWholeNDStops: Int = 30
}

extension ExposureScale {
    /// Lookup helper used by the calc layer. For whole-stop ND
    /// values, returns the canonical `NDStep` from the ladder; for
    /// fractional values the result is also a valid `NDStep` even
    /// when the scale itself does not enumerate it (the shipping
    /// scale enumerates whole stops only). Kept here so the
    /// fractional-aware calc routing has a single conversion site
    /// when the reserved fractional path is exercised by tests or
    /// a future workflow.
    public static func ndStep(forWholeStops stop: Int) -> NDStep {
        NDStep(stops: Double(stop))
    }

    /// Returns the canonical scale for a given mode. Single conversion
    /// site so the ViewModel and persistence boundaries can flip
    /// `ExposureScaleMode` without re-deriving the ladder data.
    public static func scale(for mode: ExposureScaleMode) -> ExposureScale {
        switch mode {
        case .fullStop:
            return .fullStop
        case .oneThirdStop:
            return .oneThirdStop
        }
    }
}

extension NDStep {
    /// Count of one-third-stop increments this step represents. Exact
    /// integer identity for any third-stop value (0, 1/3, 2/3, 1, …).
    /// Stable integer representation for serialized or persisted
    /// third-stop values, so fractional ND can round-trip without
    /// `Double` becoming the source of truth.
    public var thirdStopCount: Int {
        Int((stops * 3).rounded())
    }

    /// Builds an `NDStep` from a count of one-third-stops. Inverse of
    /// `thirdStopCount` for any value that may be serialized.
    public static func fromThirdStopCount(_ thirds: Int) -> NDStep {
        NDStep(stops: Double(thirds) / 3.0)
    }
}

private extension ExposureScale {
    /// Builds a 1/3-stop densified shutter ladder from the canonical
    /// full-stop ladder by inserting two intermediate steps between
    /// each pair of neighbors at the geometric-mean ratios `2^(1/3)`
    /// and `2^(2/3)`. Using ratios off the lower neighbor preserves
    /// round-trip behavior at every full-stop boundary, which matters
    /// when calculation is routed through this ladder.
    static func oneThirdStopShutterSteps(fromFullStops fullStops: [Double]) -> [ShutterStep] {
        guard fullStops.count >= 2 else {
            return fullStops.map(ShutterStep.init(seconds:))
        }

        let oneThirdRatio = pow(2.0, 1.0 / 3.0)
        let twoThirdsRatio = pow(2.0, 2.0 / 3.0)

        var steps: [ShutterStep] = []
        steps.reserveCapacity(fullStops.count * 3 - 2)

        for index in fullStops.indices {
            let lower = fullStops[index]
            steps.append(ShutterStep(seconds: lower))

            guard index < fullStops.count - 1 else { continue }

            steps.append(ShutterStep(seconds: lower * oneThirdRatio))
            steps.append(ShutterStep(seconds: lower * twoThirdsRatio))
        }

        return steps
    }
}

extension ExposureScale {
    /// Camera-facing labels for each entry on `oneThirdStop.shutterSteps`,
    /// indexed by ladder position. Real cameras and external meters
    /// expose 1/3-stop shutter speeds with conventional rounded labels
    /// (`1/20`, `1/2`, `1.3s`) rather than the canonical geometric-
    /// mean seconds. The picker shows these labels so the value matches
    /// what the photographer can find on the camera dial; the
    /// underlying calculation continues to use the canonical seconds
    /// from `oneThirdStop.shutterSteps`.
    ///
    /// The table has the same length and ordering as
    /// `oneThirdStop.shutterSteps` (19 full-stop anchors + 36
    /// one-third-stop intermediates = 55 entries).
    ///
    /// Notation rules (Nikon Z7-derived numeric ladder, with PTIMER's
    /// existing `s` suffix kept for ≥ 1s):
    /// - sub-1-second values always render as a reciprocal fraction
    ///   `1/N` and never carry an `s` suffix — including the slow
    ///   end `1/3, 1/2.5, 1/2, 1/1.6, 1/1.3` — so the slow-shutter
    ///   range stays visually consistent with the fast-shutter range
    /// - values ≥ 1s render as integer or `N.Ns` per camera
    ///   convention.
    ///
    /// Underlying canonical seconds in `oneThirdStop.shutterSteps`
    /// are unchanged; calculation continues to advance by stop-step
    /// index so a transition like `1/10 + 3 stops` lands on the row
    /// labeled `1/1.3`.
    public static let oneThirdStopShutterCameraLabels: [String] = [
        // 1/8000 anchor + 2 intermediates → 1/4000 anchor + 2 → …
        "1/8000", "1/6400", "1/5000",
        "1/4000", "1/3200", "1/2500",
        "1/2000", "1/1600", "1/1250",
        "1/1000", "1/800", "1/640",
        "1/500", "1/400", "1/320",
        "1/250", "1/200", "1/160",
        "1/125", "1/100", "1/80",
        "1/60", "1/50", "1/40",
        "1/30", "1/25", "1/20",
        "1/15", "1/13", "1/10",
        "1/8", "1/6", "1/5",
        "1/4", "1/3", "1/2.5",
        "1/2", "1/1.6", "1/1.3",
        "1s", "1.3s", "1.6s",
        "2s", "2.5s", "3s",
        "4s", "5s", "6s",
        "8s", "10s", "13s",
        "15s", "20s", "25s",
        "30s",
    ]

    /// Returns the camera-facing label for a one-third-stop shutter
    /// value if the value sits on the canonical 1/3-stop ladder. Falls
    /// back to `nil` for values that aren't on the ladder so callers
    /// can use the standard formatter.
    public static func oneThirdStopShutterCameraLabel(forSeconds seconds: Double) -> String? {
        let ladder = oneThirdStop.shutterSteps
        guard ladder.count == oneThirdStopShutterCameraLabels.count else {
            return nil
        }
        for (index, step) in ladder.enumerated()
        where abs(step.seconds - seconds) <= ExposureCalculator.stabilityEpsilon {
            return oneThirdStopShutterCameraLabels[index]
        }
        return nil
    }
}
