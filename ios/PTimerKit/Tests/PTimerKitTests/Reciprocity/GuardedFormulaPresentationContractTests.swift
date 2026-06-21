// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Presentation contract for the converted guarded formula archetype:
/// the Details "Source reference" / "Guidance boundary" split, graph
/// source markers and boundaries, beyond-source wording, and the
/// play-button enablement for an unsupported-but-numeric result. The
/// shared assertion shape lives here; per-film tokens, markers, and
/// samples are case data, so no film name appears in a function name.
///
/// CMS 20 II's idiosyncratic graph behavior (no-correction band,
/// 1/1000 s marker exclusion, 100 s not-recommended boundary across
/// inputs, viewport stability) is film-specific and stays in its own
/// suite with the film as a constant.
@MainActor
final class GuardedFormulaPresentationContractTests: XCTestCase {

    // MARK: - Details: Source reference / Guidance boundary split

    private struct DetailsCase {
        let film: String
        let sample: Double
        let sourceReferenceContains: [String]
        let sourceReferenceExcludes: [String]
        let hasGuidanceBoundary: Bool
        let guidanceBoundaryContains: String?
    }

    private let detailsCases: [DetailsCase] = [
        DetailsCase(film: "Velvia 50", sample: 8,
                    sourceReferenceContains: ["5M", "7.5M", "10M", "12.5M"],
                    sourceReferenceExcludes: ["Not recommended"],
                    hasGuidanceBoundary: true, guidanceBoundaryContains: "Not recommended"),
        DetailsCase(film: "Velvia 100", sample: 120,
                    sourceReferenceContains: ["2.5M"],
                    sourceReferenceExcludes: [],
                    hasGuidanceBoundary: false, guidanceBoundaryContains: nil),
        DetailsCase(film: "RETRO 80S", sample: 4,
                    sourceReferenceContains: ["8.0s", "24s", "60s (1m)", "180s (3m)", "1 to 2", "3 to 4", "1.0s"],
                    sourceReferenceExcludes: [],
                    hasGuidanceBoundary: false, guidanceBoundaryContains: nil),
        DetailsCase(film: "SUPERPAN 200", sample: 4,
                    sourceReferenceContains: ["8.0s", "24s", "60s (1m)", "180s (3m)", "1 to 2", "3 to 4", "1.0s"],
                    sourceReferenceExcludes: [],
                    hasGuidanceBoundary: false, guidanceBoundaryContains: nil),
    ]

    func testDetailsSplitsSourceReferenceAndGuidanceBoundary() throws {
        for c in detailsCases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: c.sample)

            let sourceReference = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(c.film): must surface a Source reference section."
            )
            let sourceBlock = try XCTUnwrap(sourceReference.rows.first?.value, "\(c.film): Source reference must carry a block.")
            for token in c.sourceReferenceContains {
                XCTAssertTrue(sourceBlock.contains(token), "\(c.film): Source reference must contain '\(token)'. Got:\n\(sourceBlock)")
            }
            for token in c.sourceReferenceExcludes {
                XCTAssertFalse(sourceBlock.contains(token), "\(c.film): Source reference must not contain '\(token)'.")
            }

            let guidanceBoundary = displayState.sections.first(where: { $0.title == "Guidance boundary" })
            if c.hasGuidanceBoundary {
                let section = try XCTUnwrap(guidanceBoundary, "\(c.film): must surface a Guidance boundary section.")
                if let token = c.guidanceBoundaryContains {
                    let block = try XCTUnwrap(section.rows.first?.value)
                    XCTAssertTrue(block.contains(token), "\(c.film): Guidance boundary must contain '\(token)'.")
                }
            } else {
                XCTAssertNil(guidanceBoundary, "\(c.film): must not surface a Guidance boundary section.")
            }

            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Reference" }),
                "\(c.film): must not surface the legacy Reference section."
            )
        }
    }

    // MARK: - Graph: source markers and boundaries

    private struct GraphCase {
        let film: String
        let sample: Double
        let markerMetereds: Set<Double>
        let notRecommendedBoundarySeconds: Double?
        let beyondSourceStartSeconds: Double?
    }

    private let graphCases: [GraphCase] = [
        GraphCase(film: "Velvia 50", sample: 8, markerMetereds: [4, 8, 16, 32], notRecommendedBoundarySeconds: 64, beyondSourceStartSeconds: nil),
        GraphCase(film: "Velvia 100", sample: 120, markerMetereds: [120, 240], notRecommendedBoundarySeconds: nil, beyondSourceStartSeconds: nil),
        GraphCase(film: "RETRO 80S", sample: 4, markerMetereds: [4, 8, 15, 30], notRecommendedBoundarySeconds: nil, beyondSourceStartSeconds: 30),
        GraphCase(film: "SUPERPAN 200", sample: 4, markerMetereds: [4, 8, 15, 30], notRecommendedBoundarySeconds: nil, beyondSourceStartSeconds: 30),
    ]

    func testGraphCarriesSourceMarkersAndBoundaries() throws {
        for c in graphCases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: c.sample)
            let graph = try XCTUnwrap(displayState.graph, "\(c.film): must surface a graph.")

            let markers = Set(graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() })
            XCTAssertEqual(markers, c.markerMetereds, "\(c.film): graph source markers")

            if let boundary = c.notRecommendedBoundarySeconds {
                XCTAssertEqual(graph.notRecommendedBoundarySeconds ?? .nan, boundary, accuracy: 1e-6, "\(c.film): not-recommended boundary")
            } else {
                XCTAssertNil(graph.notRecommendedBoundarySeconds, "\(c.film): graph must draw no not-recommended boundary.")
            }

            if let start = c.beyondSourceStartSeconds {
                XCTAssertEqual(graph.beyondSourceRangeStartSeconds ?? .nan, start, accuracy: 1e-3, "\(c.film): beyond-source region start")
            }
        }
    }

    // MARK: - Published upper boundary stays formula-derived in the summary

    private struct BoundarySummaryCase {
        let film: String
        let boundarySample: Double
    }

    /// At the published upper reference row the summary must still read as
    /// a formula-derived correction, never tipping into "Beyond source
    /// range".
    private let boundarySummaryCases: [BoundarySummaryCase] = [
        BoundarySummaryCase(film: "Velvia 100", boundarySample: 240),
    ]

    func testPublishedUpperBoundarySummaryStaysFormulaDerived() throws {
        for c in boundarySummaryCases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: c.boundarySample)
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Formula-based correction on the active curve",
                "\(c.film) @ \(c.boundarySample)s: the published reference row must read as formula-derived, not Beyond source range."
            )
        }
    }

    // MARK: - Beyond-source wording (source-range, not "extrapolated")

    private struct WordingCase {
        let film: String
        let sample: Double
        let checksGraphExplanation: Bool
    }

    private let wordingCases: [WordingCase] = [
        WordingCase(film: "Velvia 50", sample: 100, checksGraphExplanation: false),
        WordingCase(film: "Provia 100F", sample: 600, checksGraphExplanation: true),
    ]

    func testBeyondSourceRangeWordingUsesSourceRangeNotExtrapolated() throws {
        for c in wordingCases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: c.sample)

            let detail = try XCTUnwrap(displayState.summary.detailText, "\(c.film): beyond-source must carry a detail.").lowercased()
            XCTAssertFalse(detail.contains("extrapolated"), "\(c.film): detail must avoid 'Extrapolated'; got: \(detail)")
            XCTAssertTrue(detail.contains("source range"), "\(c.film): detail must surface source-range wording; got: \(detail)")

            if c.checksGraphExplanation {
                let graph = try XCTUnwrap(displayState.graph, "\(c.film): must surface a graph.")
                let explanation = try XCTUnwrap(graph.unsupportedExplanation, "\(c.film): graph must carry an unsupported explanation.").lowercased()
                XCTAssertFalse(explanation.contains("extrapolated"), "\(c.film): graph explanation must avoid 'Extrapolated'; got: \(explanation)")
                XCTAssertTrue(explanation.contains("source range"), "\(c.film): graph explanation must surface source-range wording; got: \(explanation)")
            }
        }
    }

    // MARK: - Unsupported-but-numeric enables the play button

    private struct PlayButtonCase {
        let film: String
        let sample: Double
    }

    private let playButtonCases: [PlayButtonCase] = [
        PlayButtonCase(film: "Provia 100F", sample: 600),
    ]

    func testUnsupportedNumericResultEnablesCalculatedExposure() throws {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        for c in playButtonCases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: c.sample)

            XCTAssertTrue(result.hasCalculatedExposureTime, "\(c.film): unsupported-with-numeric must report hasCalculatedExposureTime so the play button enables.")
            let presentation = result.confidencePresentation
            XCTAssertEqual(presentation.category, .unsupported, "\(c.film): confidence category")
            XCTAssertTrue(presentation.returnsCalculatedExposureTime, "\(c.film): confidence presentation must surface the numeric value to the play button.")
            XCTAssertEqual(presentation.badgeStyle, .unsupported, "\(c.film): visual treatment stays in the unsupported badge style.")
        }
    }
}
