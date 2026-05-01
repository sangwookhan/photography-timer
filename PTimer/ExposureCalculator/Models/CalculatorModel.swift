import Foundation
import Observation

/// `CalculatorModel` owns the calculator slice: the pure ND exposure
/// math engine, the user's calculation inputs (`baseShutterSeconds`,
/// `ndStop`), the live preview overlays for in-flight wheel gestures,
/// and the `calculationResult` derived from those inputs.
@MainActor
@Observable
final class CalculatorModel {
    /// Full-stop shutter ladder used by the digital shutter wheel and
    /// the snap-to-full-stop logic.
    nonisolated static let shutterSpeeds = ExposureCalculator.fullStopShutterSpeeds

    /// The pure calculation engine, shared with the view-model facade
    /// so direct call sites (`calculator.formatShutter`, etc.) reach
    /// the same instance.
    let calculator: ExposureCalculator

    /// Working base shutter in seconds. Persisted committed value;
    /// the live preview overlay (`liveBaseShutter`) takes precedence
    /// for `effectiveBaseShutter` while the user is dragging the wheel.
    var baseShutterSeconds: Double

    /// Working ND stop. Persisted committed value; the live preview
    /// overlay (`liveNDStop`) takes precedence for `effectiveNDStop`.
    var ndStop: Int

    /// Transient base shutter shown while the user drags the wheel,
    /// before the gesture commits to `baseShutterSeconds`. Cleared by
    /// `clearLiveBaseShutterPreview()` or implicitly when the preview
    /// equals the committed value.
    var liveBaseShutter: Double?

    /// Transient ND stop shown while the user drags the ND wheel,
    /// before the gesture commits to `ndStop`.
    var liveNDStop: Int?

    /// Effective base shutter — the value the calculator actually uses.
    /// Returns the live preview when set, otherwise the committed value.
    var effectiveBaseShutter: Double {
        liveBaseShutter ?? baseShutterSeconds
    }

    /// Effective ND stop — the value the calculator actually uses.
    /// Returns the live preview when set, otherwise the committed value.
    var effectiveNDStop: Int {
        liveNDStop ?? ndStop
    }

    init(
        calculator: ExposureCalculator,
        baseShutterSeconds: Double = 1.0 / 30.0,
        ndStop: Int = 0
    ) {
        self.calculator = calculator
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStop = ndStop
    }

    /// Sets the live preview value. If the preview equals the committed
    /// value the overlay is cleared instead, so a wheel gesture that
    /// settles on the committed value leaves no transient state.
    func updateLiveBaseShutter(_ value: Double) {
        liveBaseShutter = value == baseShutterSeconds ? nil : value
    }

    /// Sets the live ND-stop preview, with the same equal-clears-preview
    /// rule as `updateLiveBaseShutter`.
    func updateLiveNDStop(_ value: Int) {
        liveNDStop = value == ndStop ? nil : value
    }

    func clearLiveBaseShutterPreview() {
        liveBaseShutter = nil
    }

    func clearLiveNDStopPreview() {
        liveNDStop = nil
    }

    /// Computes the calculation result from the current inputs with the
    /// stable contract: same `Result` shape, same error mapping, same
    /// payload.
    var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculate(baseShutterSeconds: baseShutterSeconds, ndStop: ndStop)
    }

    /// Computes a calculation result for an arbitrary input pair. Used
    /// when callers need to evaluate `effectiveBaseShutter` /
    /// `effectiveNDStop` (the live preview overlay) without mutating
    /// the model's stored inputs.
    func calculate(
        baseShutterSeconds: Double,
        ndStop: Int
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        do {
            let resultShutter = try calculator.calculate(
                baseShutterSeconds: baseShutterSeconds,
                stop: ndStop
            )

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: baseShutterSeconds,
                    stop: ndStop,
                    resultShutterSeconds: resultShutter
                )
            )
        } catch let error as ExposureCalculatorError {
            return .failure(error)
        } catch {
            return .failure(.overflow)
        }
    }
}
