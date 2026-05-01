import Foundation
import Observation

/// `CalculatorModel` carries the *calculation* responsibility extracted
/// from the legacy `ExposureCalculatorViewModel` monolith as the first
/// step of B1 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`).
///
/// PR1 of 6 — skeleton extraction. The model owns:
/// - the `ExposureCalculator` instance (pure ND exposure math)
/// - the calculation inputs (`baseShutterSeconds`, `ndStop`)
/// - the computed `calculationResult` derived from those inputs
///
/// The legacy `ExposureCalculatorViewModel` retains its public
/// `ObservableObject` surface for views and tests; internally it
/// delegates calc work here. PR5/PR6 will flip the direction so views
/// observe `CalculatorModel` directly.
@MainActor
@Observable
final class CalculatorModel {
    /// Full-stop shutter ladder used by the digital shutter wheel and
    /// the snap-to-full-stop logic. Hoisted from
    /// `ExposureCalculatorViewModel` in B1 PR6 so the calc surface no
    /// longer depends on the legacy facade.
    nonisolated static let shutterSpeeds = ExposureCalculator.fullStopShutterSpeeds

    /// The pure calculation engine. Shared with the legacy ViewModel so
    /// that any direct call site (`calculator.formatShutter`, etc.)
    /// continues to work unchanged during the migration.
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
    /// value the overlay is cleared instead — matches the legacy
    /// ViewModel behavior where the wheel gesture's idle state has
    /// the preview equal to the committed value.
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

    /// Computes the calculation result from the current inputs. Mirrors
    /// the legacy ViewModel's `calculationResult` computed property
    /// exactly: same `Result` shape, same error mapping, same payload.
    var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculate(baseShutterSeconds: baseShutterSeconds, ndStop: ndStop)
    }

    /// Computes a calculation result for an arbitrary input pair. Used
    /// when the legacy ViewModel needs to evaluate `effectiveBaseShutter`
    /// / `effectiveNDStop` (the live preview overlay) without mutating
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
