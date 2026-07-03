// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Shared behavior contract for the **table-log-log reciprocity
/// archetype**. Films whose mid-region behavior is official-table
/// log-log interpolation (no-correction below threshold, table-derived
/// inside the source range, beyond-source above it) satisfy the same
/// structural / basis / wording contract — they differ only by Film
/// Case data, so those invariants are exercised here as a case table
/// instead of being copy-pasted per film.
///
/// Per-film *source data* (published anchors, exact corrected times,
/// source-evidence rows with multipliers, graph markers, provenance,
/// and the Details/graph presentation) is preserved as explicit case
/// data in `TableProfileSourceDataContractTests`; only the archetype-
/// shared rule-kind / model-basis / summary / graph-wording invariants
/// move here. Genuinely film-specific behavior that is not shared (e.g.
/// Tri-X 400's sub-1 s interpolation and alternate models, T-MAX 100's
/// short-exposure exclusion) stays in that film's own suite with the
/// film as a constant.
@MainActor
final class TableLogLogReciprocityContractTests: XCTestCase {

    /// One official-table-log-log film. `film` drives both the profile
    /// lookup and the display-state builder; `beyondSourceSample` is a
    /// metered value above the 100 s source range used to exercise the
    /// beyond-source region. Per-film anchor/source values are NOT here —
    /// they remain explicit in each film's own suite.
    private struct FilmCase {
        let film: String
        let beyondSourceSample: Double
    }

    private let cases: [FilmCase] = [
        FilmCase(film: "T-MAX 100", beyondSourceSample: 300),
        FilmCase(film: "T-MAX 400", beyondSourceSample: 400),
        FilmCase(film: "Tri-X 400", beyondSourceSample: 300),
        FilmCase(film: "Fomapan 200 Creative", beyondSourceSample: 300),
        FilmCase(film: "Fomapan 400 Action", beyondSourceSample: 300),
        FilmCase(film: "Fomapan 100 Classic", beyondSourceSample: 300),
        FilmCase(film: "CHS 100 II", beyondSourceSample: 30),
        FilmCase(film: "RPX 100", beyondSourceSample: 90),
        FilmCase(film: "RPX 400", beyondSourceSample: 60),
        FilmCase(film: "RPX 25", beyondSourceSample: 90),
        FilmCase(film: "ORTHO 25 plus", beyondSourceSample: 90),
        FilmCase(film: "Pancro 400", beyondSourceSample: 90),
    ]

    // MARK: - Rule structure

    /// The default profile carries a `.tableInterpolation` rule and no
    /// `.formula` rule (post table-migration).
    func testDefaultProfileCarriesTableRuleAndNoFormulaRule() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let hasTable = profile.rules.contains {
                if case .tableInterpolation = $0 { return true } else { return false }
            }
            let hasFormula = profile.rules.contains {
                if case .formula = $0 { return true } else { return false }
            }
            XCTAssertTrue(hasTable, "\(c.film): must carry a .tableInterpolation rule after migration.")
            XCTAssertFalse(hasFormula, "\(c.film): must not carry a .formula rule after migration to table.")
        }
    }

    // MARK: - Model basis

    /// Model basis is a manufacturer table shape + log-log
    /// interpolation. Tri-X 400's default set is graph-extended, so
    /// its source reads manufacturerGraphTable (PTIMER-168 follow-up).
    func testDefaultProfileModelBasisIsManufacturerTableLogLog() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let basis = try XCTUnwrap(profile.modelBasis, "\(c.film): profile must carry a modelBasis.")
            let expectedSource: ReciprocitySourceModel =
                c.film == "Tri-X 400" ? .manufacturerGraphTable : .manufacturerTable
            XCTAssertEqual(basis.sourceModel, expectedSource, "\(c.film): sourceModel")
            XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation, "\(c.film): calculationModel")
        }
    }

    // MARK: - Wording

    /// Inside the source range the summary describes log-log table
    /// interpolation.
    func testSummaryInsideSourceRangeDescribesLogLogInterpolation() throws {
        for c in cases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: c.film,
                meteredExposureSeconds: 10
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Log-log interpolation of the official table",
                "\(c.film) @ 10s: summary inside the source range must describe table log-log interpolation."
            )
        }
    }

    /// Above the source range the summary reads "Beyond source range".
    func testSummaryBeyondSourceRangeReadsBeyondSourceRange() throws {
        for c in cases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: c.film,
                meteredExposureSeconds: c.beyondSourceSample
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Beyond source range",
                "\(c.film) @ \(c.beyondSourceSample)s: summary above the source range must read 'Beyond source range'."
            )
        }
    }

    /// Above the source range the graph explanation surfaces
    /// source-table wording.
    func testGraphExplanationBeyondSourceRangeSurfacesSourceTableWording() throws {
        for c in cases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: c.film,
                meteredExposureSeconds: c.beyondSourceSample
            )
            let graph = try XCTUnwrap(displayState.graph, "\(c.film): display state must carry a graph.")
            let explanation = try XCTUnwrap(graph.unsupportedExplanation, "\(c.film): graph must carry an unsupported explanation past the source range.")
            XCTAssertTrue(
                explanation.lowercased().contains("source table"),
                "\(c.film) @ \(c.beyondSourceSample)s: graph explanation must surface source-table wording; got: \(explanation)"
            )
        }
    }
}
