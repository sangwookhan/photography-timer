import XCTest
import PTimerKit
import PTimerCore

/// Shared behavior contract for the **source-less bare power-law
/// reciprocity archetype** — the ILFORD / HARMAN family. Every film in
/// this archetype ships a single power-law formula `Tc = Tm^p`
/// (coefficient 1, reference 1) with an inclusive 1 s no-correction
/// threshold, **no published source evidence**, and **no bounded source
/// range**. They differ only by the published exponent, so the archetype
/// invariants live here as a film-case table instead of one suite per
/// film.
///
/// Film identity is case data, never part of a test-function name; the
/// film and the exponent appear in every failure message. There is no
/// per-film source data to keep elsewhere — these profiles are
/// source-less by construction, which is itself one of the contracts
/// below.
final class BarePowerLawReciprocityContractTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// One ILFORD / HARMAN bare power-law film. `exponent` is the only
    /// per-film parameter; everything else (coefficient 1, reference 1,
    /// 1 s threshold, no source range, no source evidence) is the
    /// archetype constant verified by `testProfileIsSourceLessBarePowerLaw`.
    private struct IlfordFilmCase {
        let film: String
        let exponent: Double
    }

    private let cases: [IlfordFilmCase] = [
        IlfordFilmCase(film: "HP5 Plus", exponent: 1.31),
        IlfordFilmCase(film: "Pan F Plus", exponent: 1.33),
        IlfordFilmCase(film: "FP4 Plus", exponent: 1.26),
        IlfordFilmCase(film: "Delta 100", exponent: 1.26),
        IlfordFilmCase(film: "Delta 400", exponent: 1.41),
        IlfordFilmCase(film: "Delta 3200", exponent: 1.33),
        IlfordFilmCase(film: "Kentmere 100", exponent: 1.26),
        IlfordFilmCase(film: "Kentmere 200", exponent: 1.26),
        IlfordFilmCase(film: "Kentmere 400", exponent: 1.3),
        IlfordFilmCase(film: "Ortho Plus", exponent: 1.25),
        IlfordFilmCase(film: "SFX 200", exponent: 1.43),
        IlfordFilmCase(film: "XP2 Super", exponent: 1.31),
    ]

    private func formulaRule(in profile: ReciprocityProfile) throws -> FormulaReciprocityRule {
        try XCTUnwrap(
            profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first
        )
    }

    // MARK: - Formula shape

    /// Each profile is a single bare power-law formula — coefficient 1,
    /// reference 1, 1 s inclusive threshold, no source range, no source
    /// evidence — carrying the published exponent.
    func testProfileIsSourceLessBarePowerLaw() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let formula = try formulaRule(in: profile).formula

            XCTAssertEqual(formula.exponent, c.exponent, accuracy: 1e-6, "\(c.film): published exponent")
            XCTAssertEqual(formula.coefficientSeconds, 1, accuracy: 1e-9, "\(c.film): bare power-law coefficient must be 1")
            XCTAssertEqual(formula.referenceMeteredTimeSeconds, 1, accuracy: 1e-9, "\(c.film): bare power-law reference must be 1")
            XCTAssertEqual(formula.noCorrectionThroughSeconds, 1, accuracy: 1e-9, "\(c.film): inclusive 1 s no-correction threshold")
            XCTAssertNil(formula.sourceRangeThroughSeconds, "\(c.film): bare power-law profiles have no bounded source range")
            XCTAssertTrue(profile.sourceEvidence.isEmpty, "\(c.film): source-less profiles carry no source evidence")
        }
    }

    // MARK: - No-correction threshold (inclusive at 1 s)

    /// At and below the 1 s inclusive threshold the basis is official
    /// no-correction with corrected == metered.
    func testAtAndBelowThresholdReturnsOfficialNoCorrection() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            for metered in [0.5, 1.0] {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .officialThresholdNoCorrection,
                    "\(c.film) @ \(metered)s: at/below the 1 s threshold must read as official no-correction."
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(metered)s: no-correction must report corrected.")
                XCTAssertEqual(corrected, metered, accuracy: 1e-6, "\(c.film) @ \(metered)s: corrected must equal metered in the no-correction band.")
            }
        }
    }

    // MARK: - Formula range is formula-derived with the bare power value

    /// Above the threshold the basis is formula-derived and the
    /// corrected exposure is the bare power-law value `Tm^exponent`.
    func testAboveThresholdIsFormulaDerivedBarePowerValue() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            for metered in [2.0, 8.0, 30.0] {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .formulaDerived,
                    "\(c.film) @ \(metered)s: above the threshold must be formula-derived."
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(metered)s: formula must report corrected.")
                XCTAssertEqual(
                    corrected,
                    pow(metered, c.exponent),
                    accuracy: 1e-4,
                    "\(c.film) @ \(metered)s: corrected must equal the bare power-law value Tm^\(c.exponent)."
                )
            }
        }
    }

    // MARK: - Unbounded: no source range means no beyond-source classification

    /// With no bounded source range, even very long inputs stay
    /// formula-derived (quantified) — they never flip to the
    /// beyond-source classification reserved for profiles with a
    /// published upper bound.
    func testLongExposureStaysFormulaDerivedWithoutBeyondSourceClassification() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let metered = 600.0
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "\(c.film) @ \(metered)s: source-less profiles must stay formula-derived, never beyond-source."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(metered)s: must keep a numeric value.")
            XCTAssertEqual(corrected, pow(metered, c.exponent), accuracy: max(0.5, pow(metered, c.exponent) * 1e-4), "\(c.film) @ \(metered)s: long-exposure value must stay on the bare power-law curve.")
        }
    }

    // MARK: - Presentation: source-less surfaces

    /// Source-less profiles must not activate any source-reference
    /// presentation: no Source reference / Guidance boundary section, no
    /// graph source markers, no not-recommended boundary, no
    /// beyond-source region — while still surfacing the formula
    /// expression and the formula-derived summary wording.
    @MainActor
    func testSourceLessProfileSuppressesSourceReferenceArtifacts() throws {
        for c in cases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: 8)

            XCTAssertEqual(
                displayState.summary.summaryText,
                "Formula-based correction on the active curve",
                "\(c.film): source-less formula profiles keep the formula-derived summary wording."
            )

            let graph = try XCTUnwrap(displayState.graph, "\(c.film): must surface a graph.")
            XCTAssertTrue(graph.sourceReferenceMarkers.isEmpty, "\(c.film): source-less graph must invent no source markers.")
            XCTAssertNil(graph.notRecommendedBoundarySeconds, "\(c.film): no published not-recommended boundary.")
            XCTAssertNil(graph.beyondSourceRangeStartSeconds, "\(c.film): no source range, so no beyond-source region.")
            XCTAssertNotNil(graph.formulaDisplayText, "\(c.film): the formula expression must still surface near the graph.")
            XCTAssertTrue(graph.descriptionLines.isEmpty, "\(c.film): source-less profiles stay on the state-aware caption without description lines.")

            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Source reference" }),
                "\(c.film): must not surface a Source reference section."
            )
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
                "\(c.film): must not surface a Guidance boundary section."
            )
        }
    }
}
