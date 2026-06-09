import XCTest
import PTimerKit
import PTimerCore

/// Fit-parameter contract for the converted guarded formula archetype.
/// Each member's published log-log fit (exponent, coefficient, optional
/// reference / threshold / source-range, and the formula note wording)
/// is preserved as explicit case data — the values stay film-specific,
/// the assertion intent is shared, and no film name appears in a
/// function name.
///
/// Companion to `GuardedFormulaRegionBasisContractTests` (region basis),
/// `GuardedFormulaEvidenceContractTests` (published rows), and
/// `GuardedFormulaPresentationContractTests` (details / graph surfaces).
final class GuardedFormulaFitContractTests: XCTestCase {

    /// Published fit for one converted guarded-formula film. Optional
    /// fields are asserted only when present, matching what each film's
    /// former per-film suite checked.
    private struct FitCase {
        let film: String
        let exponent: Double
        let exponentAccuracy: Double
        let coefficientSeconds: Double
        let coefficientAccuracy: Double
        let referenceMeteredTimeSeconds: Double?
        let noCorrectionThroughSeconds: Double?
        let sourceRangeThroughSeconds: Double?
        /// Lowercased substrings the formula's first note must contain.
        let noteKeywords: [String]
    }

    private let cases: [FitCase] = [
        FitCase(
            film: "Velvia 50",
            exponent: 1.1821, exponentAccuracy: 0.001,
            coefficientSeconds: 1, coefficientAccuracy: 0.001,
            referenceMeteredTimeSeconds: nil,
            noCorrectionThroughSeconds: nil,
            sourceRangeThroughSeconds: nil,
            noteKeywords: ["threshold-anchored", "log-log"]
        ),
        FitCase(
            film: "Velvia 100",
            exponent: 1.2667, exponentAccuracy: 0.001,
            coefficientSeconds: 60, coefficientAccuracy: 1e-6,
            referenceMeteredTimeSeconds: 60,
            noCorrectionThroughSeconds: nil,
            sourceRangeThroughSeconds: nil,
            noteKeywords: ["threshold-anchored", "log-log"]
        ),
        FitCase(
            film: "Provia 100F",
            exponent: 1.3676, exponentAccuracy: 1e-4,
            coefficientSeconds: 128, coefficientAccuracy: 1e-6,
            referenceMeteredTimeSeconds: 128,
            noCorrectionThroughSeconds: nil,
            sourceRangeThroughSeconds: nil,
            noteKeywords: []
        ),
        FitCase(
            film: "CMS 20 II",
            exponent: 1.150515, exponentAccuracy: 1e-3,
            coefficientSeconds: 1.4142136, coefficientAccuracy: 1e-3,
            referenceMeteredTimeSeconds: nil,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 10,
            noteKeywords: []
        ),
    ]

    func testFormulaParametersMatchPublishedFit() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let formulaRule = try XCTUnwrap(
                profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                    guard case let .formula(rule) = rule else { return nil }
                    return rule
                }.first,
                "\(c.film): must carry a formula rule."
            )
            let formula = formulaRule.formula

            XCTAssertEqual(formula.exponent, c.exponent, accuracy: c.exponentAccuracy, "\(c.film): exponent")
            XCTAssertEqual(formula.coefficientSeconds, c.coefficientSeconds, accuracy: c.coefficientAccuracy, "\(c.film): coefficient")
            if let reference = c.referenceMeteredTimeSeconds {
                XCTAssertEqual(formula.referenceMeteredTimeSeconds, reference, accuracy: 1e-6, "\(c.film): reference metered time")
            }
            if let noCorrection = c.noCorrectionThroughSeconds {
                XCTAssertEqual(formula.noCorrectionThroughSeconds, noCorrection, accuracy: 1e-6, "\(c.film): no-correction-through")
            }
            if let sourceRange = c.sourceRangeThroughSeconds {
                let actual = try XCTUnwrap(formula.sourceRangeThroughSeconds, "\(c.film): must declare a source range.")
                XCTAssertEqual(actual, sourceRange, accuracy: 1e-6, "\(c.film): source-range-through")
            }
            if !c.noteKeywords.isEmpty {
                let note = try XCTUnwrap(formulaRule.notes.first, "\(c.film): must carry a formula note.").lowercased()
                for keyword in c.noteKeywords {
                    XCTAssertTrue(note.contains(keyword), "\(c.film): formula note must contain '\(keyword)'; got: \(note)")
                }
            }
        }
    }
}
