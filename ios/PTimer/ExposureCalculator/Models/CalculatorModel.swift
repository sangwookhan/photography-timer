import Foundation
import Observation
import PTimerKit

/// `CalculatorModel` owns the calculator slice: the pure ND exposure
/// math engine, the user's calculation inputs (`baseShutterSeconds`,
/// `ndStop`), the live preview overlays for in-flight wheel gestures,
/// and the `calculationResult` derived from those inputs.
@MainActor
@Observable
final class CalculatorModel {
    /// Full-stop shutter ladder kept as a stable legacy static so
    /// existing callers (persistence sanitizers, snap-to-full-stop
    /// logic, regression suites) keep reading the 19-value ladder
    /// regardless of which scale the shipping calculator currently
    /// uses. Sourced explicitly from `.fullStop` rather than
    /// `.default` so a future flip of `.default` does not silently
    /// reshape this static.
    nonisolated static let shutterSpeeds = ExposureScale.fullStop.shutterSteps.map(\.seconds)

    /// The pure calculation engine, shared with the view-model facade
    /// so direct call sites (`calculator.formatShutter`, etc.) reach
    /// the same instance.
    let calculator: ExposureCalculator

    /// Active exposure-scale mode. The shipping calculator runs on
    /// `.oneThirdStop`; the field is mutable so tests and the future
    /// Settings preference can flip the active scale without
    /// redesigning the model. The shipping UI does not surface a
    /// runtime selector for this field.
    var scaleMode: ExposureScaleMode {
        didSet {
            // Re-snap committed and live ND values onto the new scale's
            // ladder so a scale flip does not leave stale fractional
            // or whole values that are illegal on the active scale.
            ndStep = sanitizedNDStep(ndStep, for: scaleMode)
            if let live = liveNDStep {
                liveNDStep = sanitizedNDStep(live, for: scaleMode)
            }

            // Same reasoning for the shutter ladder: a scale flip
            // away from the active ladder must collapse the committed
            // shutter value onto the nearest entry on the new ladder,
            // otherwise the wheel index would point at a value the
            // picker no longer enumerates.
            baseShutterSeconds = sanitizedShutter(baseShutterSeconds, for: scaleMode)
            if let live = liveBaseShutter {
                liveBaseShutter = sanitizedShutter(live, for: scaleMode)
            }
        }
    }

    /// Active exposure scale derived from `scaleMode`. Reading the
    /// scale registers an observation on `scaleMode`, so the picker
    /// data sources (`pickerShutterStepSeconds` / `pickerWholeNDStops`)
    /// flip atomically when the mode changes.
    var exposureScale: ExposureScale {
        ExposureScale.scale(for: scaleMode)
    }

    /// Shutter ladder shown by the picker. Reads from the active
    /// scale so swapping `scaleMode` flips the picker without any
    /// view-side conditional.
    var pickerShutterStepSeconds: [Double] {
        exposureScale.shutterSteps.map(\.seconds)
    }

    /// Whole-stop ND values shown by the shipping picker. The
    /// shipping ND ladder is whole-stop in every scale mode (per
    /// `docs/specs/Calculator.md` §2.2), so this helper filters the
    /// scale to the whole-stop subset for any caller still bound to
    /// `Int`. The fractional-aware `pickerNDSteps` surface is the
    /// canonical source for the SwiftUI picker; both views are kept
    /// for the legacy integer binding compatibility.
    var pickerWholeNDStops: [Int] {
        exposureScale.ndSteps.compactMap(\.wholeStops)
    }

    /// Working base shutter in seconds. Persisted committed value;
    /// the live preview overlay (`liveBaseShutter`) takes precedence
    /// for `effectiveBaseShutter` while the user is dragging the wheel.
    var baseShutterSeconds: Double

    /// Canonical ND input as a fractional-aware `NDStep`. Source of
    /// truth for the calc engine; the legacy `ndStop` integer setter
    /// mirrors writes into this field so any integer-bound caller
    /// stays compatible. The shipping picker writes whole-stop
    /// values; the fractional path is reserved infrastructure.
    var ndStep: NDStep

    /// Working ND stop, integer-binding compatibility wrapper around
    /// `ndStep`. Setting writes a whole-stop `NDStep`; reading
    /// returns the whole-stop equivalent (rounded for any fractional
    /// value). The wrapper is kept for the integer binding
    /// compatibility surface; the canonical `ndStep` is the
    /// fractional-aware source of truth.
    var ndStop: Int {
        get { ndStep.wholeStops ?? Int(ndStep.stops.rounded()) }
        set { ndStep = NDStep(stops: Double(newValue)) }
    }

    /// Transient base shutter shown while the user drags the wheel,
    /// before the gesture commits to `baseShutterSeconds`. Cleared by
    /// `clearLiveBaseShutterPreview()` or implicitly when the preview
    /// equals the committed value.
    var liveBaseShutter: Double?

    /// Transient ND step shown while the user drags the ND wheel,
    /// before the gesture commits to `ndStep`. Stored as `NDStep` so
    /// the field never needs widening if a future custom /
    /// variable-ND workflow ever feeds the reserved fractional path
    /// through this preview.
    var liveNDStep: NDStep?

    /// Integer-binding compatibility wrapper around `liveNDStep` for
    /// the existing whole-stop drag gesture. Setting writes a
    /// whole-stop `NDStep`; reading returns the whole-stop equivalent.
    var liveNDStop: Int? {
        get { liveNDStep?.wholeStops ?? liveNDStep.map { Int($0.stops.rounded()) } }
        set { liveNDStep = newValue.map { NDStep(stops: Double($0)) } }
    }

    /// Effective base shutter — the value the calculator actually uses.
    /// Returns the live preview when set, otherwise the committed value.
    var effectiveBaseShutter: Double {
        liveBaseShutter ?? baseShutterSeconds
    }

    /// Effective ND step — the value the calculator actually uses.
    /// Returns the live preview when set, otherwise the committed value.
    var effectiveNDStep: NDStep {
        liveNDStep ?? ndStep
    }

    /// Whole-stop view of `effectiveNDStep`, kept for callers still
    /// bound to the legacy `Int` ND surface. The shipping ND picker
    /// emits whole-stop values, so this view is exact for shipping
    /// drag gestures and falls back to a rounded integer only when
    /// reserved-path fractional `NDStep` values reach the model.
    var effectiveNDStop: Int {
        effectiveNDStep.wholeStops ?? Int(effectiveNDStep.stops.rounded())
    }

    init(
        calculator: ExposureCalculator,
        baseShutterSeconds: Double = 1.0 / 30.0,
        ndStep: NDStep = NDStep(stops: 0),
        scaleMode: ExposureScaleMode = .oneThirdStop
    ) {
        self.calculator = calculator
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStep = ndStep
        self.scaleMode = scaleMode
    }

    /// Convenience init for the legacy `(ndStop: Int, exposureScale:
    /// ExposureScale)` shape. Wraps `ndStop` in a whole-stop `NDStep`
    /// and derives `scaleMode` from the supplied scale so PTIMER-79
    /// call sites compile without changes.
    convenience init(
        calculator: ExposureCalculator,
        baseShutterSeconds: Double = 1.0 / 30.0,
        ndStop: Int,
        exposureScale: ExposureScale = .default
    ) {
        self.init(
            calculator: calculator,
            baseShutterSeconds: baseShutterSeconds,
            ndStep: NDStep(stops: Double(ndStop)),
            scaleMode: exposureScale.mode
        )
    }

    /// Variant of the convenience init that accepts an explicit
    /// `exposureScale` while keeping `ndStep` zero. Lets PTIMER-79
    /// tests construct a one-third-stop model with a single argument.
    convenience init(
        calculator: ExposureCalculator,
        exposureScale: ExposureScale
    ) {
        self.init(
            calculator: calculator,
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 0),
            scaleMode: exposureScale.mode
        )
    }

    /// Sets the live preview value. If the preview equals the committed
    /// value the overlay is cleared instead, so a wheel gesture that
    /// settles on the committed value leaves no transient state.
    func updateLiveBaseShutter(_ value: Double) {
        liveBaseShutter = value == baseShutterSeconds ? nil : value
    }

    /// Sets the live ND-stop preview, with the same
    /// equal-clears-preview rule as `updateLiveBaseShutter`.
    /// Integer-binding compatibility wrapper around
    /// `updateLiveNDStep(_:)`; the shipping ND drag gesture writes
    /// whole-stop values through this entry point.
    func updateLiveNDStop(_ value: Int) {
        updateLiveNDStep(NDStep(stops: Double(value)))
    }

    /// Fractional-aware preview update. The shipping picker drives
    /// this through whole-stop NDStep values; the fractional path is
    /// exercised by tests covering the reserved infrastructure.
    /// Equal-clears-preview keeps the same idle-state rule as the
    /// integer overload.
    func updateLiveNDStep(_ value: NDStep) {
        liveNDStep = value == ndStep ? nil : value
    }

    func clearLiveBaseShutterPreview() {
        liveBaseShutter = nil
    }

    func clearLiveNDStopPreview() {
        liveNDStep = nil
    }

    /// Computes the calculation result from the current inputs with the
    /// stable contract: same `Result` shape, same error mapping, same
    /// payload.
    var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculate(baseShutterSeconds: baseShutterSeconds, ndStep: ndStep)
    }

    /// Whole-stop overload of `calculate(baseShutterSeconds:ndStep:)`.
    /// Wraps `ndStop` in a whole-stop `NDStep`; preserves the byte-for-
    /// byte legacy behavior (snap-to-full-stop) for whole-stop callers.
    func calculate(
        baseShutterSeconds: Double,
        ndStop: Int
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculate(
            baseShutterSeconds: baseShutterSeconds,
            ndStep: NDStep(stops: Double(ndStop))
        )
    }

    /// Computes a calculation result for an arbitrary input pair using
    /// the model's current `scaleMode`. Used when callers need to
    /// evaluate `effectiveBaseShutter` / `effectiveNDStep` (the live
    /// preview overlay) without mutating the model's stored inputs.
    /// Routes through the scale-aware engine so a 1/3-stop shutter
    /// value with whole-stop ND keeps its fractional precision instead
    /// of snapping back to the full-stop ladder.
    func calculate(
        baseShutterSeconds: Double,
        ndStep: NDStep
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        do {
            let resultShutter = try calculator.calculate(
                baseShutterSeconds: baseShutterSeconds,
                ndStep: ndStep,
                scaleMode: scaleMode
            )

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: baseShutterSeconds,
                    ndStep: ndStep,
                    resultShutterSeconds: resultShutter
                )
            )
        } catch let error as ExposureCalculatorError {
            return .failure(error)
        } catch {
            return .failure(.overflow)
        }
    }

    /// Re-snaps an `NDStep` onto the ladder for `mode`. For full-stop
    /// mode any fractional component is dropped to the nearest whole;
    /// for one-third-stop mode any value is snapped onto the third-stop
    /// grid. Centralized here so a `scaleMode` flip can keep committed
    /// and live ND values legal on the active scale.
    private func sanitizedNDStep(
        _ step: NDStep,
        for mode: ExposureScaleMode
    ) -> NDStep {
        switch mode {
        case .fullStop:
            return NDStep(stops: step.stops.rounded())
        case .oneThirdStop:
            return NDStep(stops: Double((step.stops * 3).rounded()) / 3.0)
        }
    }

    /// Re-snaps a shutter value onto the ladder for `mode`. Looks up
    /// the nearest entry on the active scale's shutter ladder by
    /// absolute distance in seconds. If the ladder is empty (which
    /// should never happen for a real scale) the original value is
    /// returned unchanged.
    private func sanitizedShutter(
        _ seconds: Double,
        for mode: ExposureScaleMode
    ) -> Double {
        // Preserve non-positive / non-finite values verbatim so the
        // calc engine can surface them as `nonPositiveBaseShutter` /
        // `overflow` failures. Snapping zero to the nearest ladder
        // entry would silently rewrite a zero input into `1/8000` and
        // mask the typed failure.
        guard seconds > 0, seconds.isFinite else {
            return seconds
        }
        let ladder = ExposureScale.scale(for: mode).shutterSteps
        guard let nearest = ladder.min(
            by: { abs($0.seconds - seconds) < abs($1.seconds - seconds) }
        ) else {
            return seconds
        }
        return nearest.seconds
    }
}
