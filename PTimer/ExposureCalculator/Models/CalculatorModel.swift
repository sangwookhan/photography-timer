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

    /// Working base shutter in seconds. Mirrors the legacy ViewModel's
    /// `baseShutter` (or `liveBaseShutter` preview when active).
    var baseShutterSeconds: Double

    /// Working ND stop. Mirrors the legacy ViewModel's `ndStop` (or
    /// `liveNDStop` preview when active).
    var ndStop: Int

    init(
        calculator: ExposureCalculator,
        baseShutterSeconds: Double = 1.0 / 30.0,
        ndStop: Int = 0
    ) {
        self.calculator = calculator
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStop = ndStop
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
