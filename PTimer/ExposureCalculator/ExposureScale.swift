import Foundation

/// Granularity of one increment along an exposure scale. Treat
/// `oneThirdStop` as a first-class step, not a display-only formatting
/// choice — both the shutter ladder and the ND ladder change with the
/// selected mode.
///
/// PTIMER-79 introduces the abstraction; PTIMER-80 will route the
/// calculation engine through it; PTIMER-81 will surface the mode in
/// the UI selector.
enum ExposureScaleMode: String, Codable, CaseIterable, Sendable {
    case fullStop
    case oneThirdStop
}

extension ExposureScaleMode {
    /// Stops covered by one step on this scale.
    /// `fullStop` → 1.0; `oneThirdStop` → 1/3.
    var stopsPerStep: Double {
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
struct ShutterStep: Equatable, Hashable, Sendable {
    let seconds: Double

    init(seconds: Double) {
        self.seconds = seconds
    }
}

/// One ND-filter entry on an exposure scale's ND ladder, expressed in
/// stops. Fractional values are first-class so a future
/// `oneThirdStop` ND ladder can include `1/3`, `2/3`, `1 1/3`, … as
/// distinct steps. `wholeStops` is non-nil only when the step lies on
/// a whole-stop boundary, which is what the legacy integer calc API
/// (`ExposureCalculator.calculate(baseShutterSeconds:stop: Int)`)
/// consumes today.
struct NDStep: Equatable, Hashable, Sendable {
    let stops: Double

    init(stops: Double) {
        self.stops = stops
    }

    var isWholeStop: Bool {
        abs(stops - stops.rounded()) <= ExposureCalculator.stabilityEpsilon
    }

    var wholeStops: Int? {
        isWholeStop ? Int(stops.rounded()) : nil
    }
}

/// Canonical scale data for one `ExposureScaleMode`. Picker UI reads
/// `shutterSteps` / `ndSteps` from the active scale; the calc layer
/// reads `mode.stopsPerStep` (full routing through fractional ND lands
/// in PTIMER-80).
///
/// The scale is the single source of truth for "what values does the
/// user pick from": picker rows shall not maintain a parallel list.
struct ExposureScale: Equatable, Sendable {
    let mode: ExposureScaleMode
    let shutterSteps: [ShutterStep]
    let ndSteps: [NDStep]
}

extension ExposureScale {
    /// Default scale used by the shipping calculator. Backed by
    /// `ExposureCalculator.fullStopShutterSpeeds` so every change to
    /// the canonical full-stop ladder shows up here without
    /// duplication, and an integer ND ladder spanning 0…30 stops to
    /// match the picker range that's been in production since
    /// PTIMER-19.
    static let fullStop: ExposureScale = ExposureScale(
        mode: .fullStop,
        shutterSteps: ExposureCalculator.fullStopShutterSpeeds.map(ShutterStep.init(seconds:)),
        ndSteps: (0...maximumWholeNDStops).map { NDStep(stops: Double($0)) }
    )

    /// Densified shutter and ND ladders for one-third-stop work. PTIMER-80
    /// will route calculation through this scale and PTIMER-81 will expose
    /// the mode in the UI; PTIMER-79 only declares the data so later work
    /// has a stable model to build on.
    static let oneThirdStop: ExposureScale = ExposureScale(
        mode: .oneThirdStop,
        shutterSteps: oneThirdStopShutterSteps(
            fromFullStops: ExposureCalculator.fullStopShutterSpeeds
        ),
        ndSteps: oneThirdStopNDSteps(maxWholeStops: maximumWholeNDStops)
    )

    /// The mode the app currently ships with. Kept as a single
    /// reference so test/setup paths can compare against the active
    /// default without re-deriving it.
    static let `default`: ExposureScale = .fullStop

    /// Maximum whole ND stops the legacy picker supports. Hoisted to
    /// a single constant so the full-stop scale and the one-third-stop
    /// scale stay in lockstep instead of repeating `0...30`.
    static let maximumWholeNDStops: Int = 30
}

extension ExposureScale {
    /// Lookup helper used by the calc layer. For whole-stop ND values,
    /// returns the canonical `NDStep` from the ladder; for fractional
    /// values the result is also a valid `NDStep` even when the scale
    /// itself does not enumerate it. Kept here so future PTIMER-80
    /// fractional routing has a single conversion site.
    static func ndStep(forWholeStops stop: Int) -> NDStep {
        NDStep(stops: Double(stop))
    }
}

private extension ExposureScale {
    /// Builds a 1/3-stop densified shutter ladder from the canonical
    /// full-stop ladder by inserting two intermediate steps between
    /// each pair of neighbors at the geometric-mean ratios `2^(1/3)`
    /// and `2^(2/3)`. Using ratios off the lower neighbor preserves
    /// round-trip behavior at every full-stop boundary, which matters
    /// when PTIMER-80 routes calculation through this ladder.
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

    /// ND ladder for one-third-stop mode. Walks `0…maxWholeStops` and
    /// inserts the `+1/3` and `+2/3` steps between whole stops; the
    /// last whole stop has no trailing fractional steps so the ladder
    /// ends cleanly on a whole boundary.
    static func oneThirdStopNDSteps(maxWholeStops: Int) -> [NDStep] {
        guard maxWholeStops >= 0 else { return [] }

        var steps: [NDStep] = []
        steps.reserveCapacity(maxWholeStops * 3 + 1)

        for whole in 0...maxWholeStops {
            steps.append(NDStep(stops: Double(whole)))

            guard whole < maxWholeStops else { continue }

            steps.append(NDStep(stops: Double(whole) + 1.0 / 3.0))
            steps.append(NDStep(stops: Double(whole) + 2.0 / 3.0))
        }

        return steps
    }
}
