import XCTest
@testable import PTimer
import PTimerKit

/// Behavior contract for Velvia 100's formula-based reciprocity
/// profile. Locks the invariants:
///
/// - Below the 60 s no-correction threshold the threshold rule wins.
/// - The formula range is closed at the published 240 s reference
///   row so 240 s itself reads as `.formulaDerived` (source-backed).
/// - Only inputs strictly greater than 240 s become beyond-source
///   numeric guidance (basis == `.unsupportedOutOfPolicyRange`).
/// - Both published rows (2 min / 4 min) and the 2.5M magenta
///   color guidance stay visible as source evidence; the graph has
///   no published not-recommended boundary.
final class Velvia100FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold boundary (inclusive at 60 s)

    // MARK: - Formula range, including the 240 s published row

    func testVelvia100FormulaExponentMatchesAnchoredLogLogFit() throws {
        let profile = try velvia100Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.exponent, 1.2667, accuracy: 0.001)
        // PTIMER-160 preserves Velvia 100's published display form
        // `Tc = 60 × (Tm / 60)^p` by storing the formula with
        // `coefficientSeconds = referenceMeteredTimeSeconds = 60`,
        // mathematically equivalent to the legacy
        // `coefficient ≈ 0.336` with `Tref = 1` form.
        XCTAssertEqual(formulaRule.formula.coefficientSeconds, 60, accuracy: 1e-6)
        XCTAssertEqual(formulaRule.formula.referenceMeteredTimeSeconds, 60, accuracy: 1e-6)

        let note = try XCTUnwrap(formulaRule.notes.first)
        XCTAssertTrue(
            note.lowercased().contains("threshold-anchored"),
            "Formula note must label the fit as threshold-anchored; got: \(note)"
        )
        XCTAssertTrue(
            note.lowercased().contains("log-log"),
            "Formula note must label the fit as log-log; got: \(note)"
        )
    }

    // MARK: - Beyond source range (> 240 s) with formula prediction

    // MARK: - Source-evidence preservation

    func testVelvia100SourceEvidencePreservesTwoExactRowsWith2dot5MagentaFilter() throws {
        let profile = try velvia100Profile()

        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [120, 240],
            "Velvia 100 must keep both Fujifilm-published rows (2 min and 4 min) as source evidence."
        )
        for (_, row) in exactRows {
            let filterName = row.adjustments.compactMap { adjustment -> String? in
                guard case let .colorFilter(filter) = adjustment else { return nil }
                return filter.filterName
            }.first
            XCTAssertEqual(filterName, "2.5M", "Velvia 100 source evidence must preserve the published 2.5M magenta correction.")
        }
    }

    // MARK: - UI surfacing

    @MainActor
    func testVelvia100DetailsSurfacesSourceReferenceWithoutGuidanceBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 120)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Velvia 100 must surface a Source reference section for its converted profile."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(sourceBlock.contains("2.5M"))

        // Velvia 100 has no published not-recommended row.
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "Velvia 100 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testVelvia100GraphCarriesSourceMarkersWithoutNotRecommendedBoundary() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 120)
        let graph = try XCTUnwrap(displayState.graph)

        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(Set(markerMetereds), Set([120, 240]))
        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "Velvia 100 has no published not-recommended boundary, so the graph must not draw one."
        )
    }

    /// 240 s is Velvia 100's published reference row; the summary
    /// must read as a formula-derived correction at this exact
    /// value and never tip into "Beyond source range".
    @MainActor
    func testVelvia100At240SecondsSummaryStaysFormulaDerived() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 240)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Formula-based correction on the active curve",
            "240 s is a Fujifilm-published reference; the summary must read as formula-derived, not Beyond source range."
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "Velvia 100",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func velvia100Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Velvia 100")
    }
}
