// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

final class ConvertedFormulaDetailsPresentationTests: XCTestCase {
    // MARK: - UI surfacing

    @MainActor
    func testDetailsSplitsSourceReferenceAndGuidanceBoundarySections() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Provia 100F must surface a Source reference section for the 128 s no-correction band and the 240 s reference row."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        XCTAssertTrue(
            sourceBlock.contains("2.5G"),
            "Source reference block must surface the 2.5G manufacturer color guidance."
        )
        XCTAssertTrue(
            sourceBlock.contains("No correction range"),
            "Source reference block must label the 128 s threshold band as a No correction range, per the design."
        )
        XCTAssertFalse(
            sourceBlock.contains("Not recommended"),
            "The Source reference section must not contain the 480 s not-recommended boundary row."
        )

        let guidanceBoundarySection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" }),
            "Provia 100F must surface a Guidance boundary section for the 480 s not-recommended row."
        )
        let boundaryBlock = try XCTUnwrap(guidanceBoundarySection.rows.first?.value)
        XCTAssertTrue(
            boundaryBlock.contains("Not recommended"),
            "Guidance boundary block must surface the 480 s not-recommended boundary."
        )
        XCTAssertFalse(
            boundaryBlock.contains("2.5G"),
            "Guidance boundary section must not pull the 240 s source-reference row into it."
        )

        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Formula profiles with source evidence must not surface the legacy Reference section."
        )

        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Profile" }),
            "Profile metadata block is removed; the calculation method is implied by the visible curve."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Formula" }),
            "Formula metadata block is removed; the formula expression now lives next to the graph."
        )
        let formula = try XCTUnwrap(
            displayState.graph?.formulaDisplayText,
            "Formula expression must be exposed on the graph state."
        )
        XCTAssertTrue(formula.contains("1.3676"))
    }

    @MainActor
    func testGraphCarries240SecondSourceReferenceMarker() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)

        let marker = try XCTUnwrap(
            graph.sourceReferenceMarkers.first {
                abs($0.point.meteredExposureSeconds - 240) < 1e-6
            },
            "Provia 100F graph state must include the 240 s manufacturer source reference marker."
        )

        // Source-evidence carries a +1/3 stop adjustment at 240 s:
        // 240 × 2^(1/3) ≈ 302.4 s.
        XCTAssertEqual(marker.point.correctedExposureSeconds, 302.4, accuracy: 1.0)
        XCTAssertEqual(
            marker.label,
            "240s",
            "Source reference markers carry an adjacent label so the user reads the published metered value directly off the graph."
        )
    }

    @MainActor
    func testGraphCarriesNotRecommendedBoundaryAt480Seconds() throws {
        for metered in [60.0, 240.0, 600.0] {
            let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.notRecommendedBoundarySeconds ?? 0,
                480,
                accuracy: 1e-6,
                "Metered \(metered) s: graph must expose Provia 100F's 480 s not-recommended boundary."
            )
        }
    }

    @MainActor
    func testGraphSourceReferenceMarkersExclude480SecondBoundary() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)

        for marker in graph.sourceReferenceMarkers {
            XCTAssertNotEqual(
                marker.point.meteredExposureSeconds,
                480,
                accuracy: 1e-6,
                "480 s must remain a Guidance boundary, never a source-reference fitting point."
            )
        }
    }

    @MainActor
    func testGraphCurrentResultMarkerPersistsAlongsideReferenceElements() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)

        let currentPoint = try XCTUnwrap(
            graph.currentPoint,
            "Current result marker must remain present when source-reference markers and boundary are also shown."
        )
        XCTAssertEqual(currentPoint.style, .formulaDerived)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 240, accuracy: 1e-6)
    }

    @MainActor
    func testInSourceRangeGraphHasNoDuplicateDescriptionLines() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(
            graph.descriptionLines.isEmpty,
            "Source-range cases must not repeat marker/region meanings via description lines; got: \(graph.descriptionLines)"
        )
    }

    @MainActor
    func testBeyondSourceRangeProducesSingleSourceRangeNote() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 600)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.descriptionLines.count, 1)
        let line = try XCTUnwrap(graph.descriptionLines.first)
        XCTAssertTrue(line.lowercased().contains("source range"), "Got: \(line)")
    }

    @MainActor
    func testBeyondVisibleRangeProducesSingleVisibleRangeNote() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 500_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.descriptionLines.count, 1)
        let line = try XCTUnwrap(graph.descriptionLines.first)
        XCTAssertTrue(line.lowercased().contains("beyond the visible"), "Got: \(line)")
    }

    // MARK: - Layout

    @MainActor
    func testDetailsSectionOrderIsSourceReferenceGuidanceBoundarySources() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let titles = displayState.sections.map(\.title)
        XCTAssertEqual(
            titles,
            ["Reciprocity model", "Source reference", "Guidance boundary", "Sources"],
            "Provia 100F leads with the active-model metadata (PTIMER-159), keeps its source-only evidence sections, and ends with Sources. The app-derived comparison is gated to explicitly app-derived models, so it does not appear here."
        )
    }

    @MainActor
    func testCurrentResultStatusTextIsShortAndStateAware() throws {
        let supported = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        XCTAssertEqual(supported.currentResult.statusText, "Formula-derived")

        let beyondSource = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 600)
        XCTAssertEqual(beyondSource.currentResult.statusText, "Beyond source range")
        XCTAssertEqual(beyondSource.currentResult.statusTone, .unsupported)

        let noCorrection = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 60)
        XCTAssertEqual(noCorrection.currentResult.statusText, "No correction")

        // Visible-range membership is a graph affordance (orange
        // triangle + graph note); the status text stays anchored
        // to the calculation basis on converted formula profiles.
        let beyondVisible = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 500_000)
        XCTAssertEqual(
            beyondVisible.currentResult.statusText,
            "Beyond source range",
            "Provia 100F (converted) keeps the source-range status even when current is past T3."
        )

        let belowVisible = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        XCTAssertEqual(
            belowVisible.currentResult.statusText,
            "No correction",
            "Sub-second Provia 100F sits in the no-correction threshold; status text follows the basis, not the visible-range flag."
        )
    }

    // MARK: - Unified Current Result layout

    @MainActor
    func testNoCorrectionUsesComparisonLayoutLikeEveryOtherCase() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 60)
        XCTAssertEqual(
            displayState.currentResult.layout,
            .comparison,
            "No-correction must use the same comparison layout as every other case so the screen shape is consistent."
        )
        XCTAssertNotEqual(
            displayState.currentResult.correctedExposure.detailText,
            "Adjusted shutter equals corrected exposure.",
            "Legacy no-correction-specific note must not appear."
        )
        XCTAssertEqual(displayState.currentResult.statusText, "No correction")
    }

    @MainActor
    func testAllCasesShareSameLayoutAndProduceStatusText() throws {
        let cases: [(meter: Double, expectedStatus: String)] = [
            (60, "No correction"),
            (240, "Formula-derived"),
            (600, "Beyond source range"),
        ]
        for (meter, expected) in cases {
            let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: meter)
            XCTAssertEqual(
                displayState.currentResult.layout,
                .comparison,
                "Metered \(meter) s must use the comparison layout."
            )
            XCTAssertEqual(
                displayState.currentResult.statusText,
                expected,
                "Metered \(meter) s status text must equal \(expected)."
            )
        }
    }

    // MARK: - ≈ duplication regression

    @MainActor
    func testBeyondVisibleNumericResultDoesNotDoubleApproximateMarker() throws {
        let film = try subjectFilm()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 1_000_000)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let correctedDisplay = model.correctedExposureDisplayState(for: bindingState)
        XCTAssertTrue(correctedDisplay.primaryText.hasPrefix("≈"))
        XCTAssertFalse(
            correctedDisplay.primaryText.hasPrefix("≈≈"),
            "Approximate marker doubled to \"≈≈\" — got: \(correctedDisplay.primaryText)"
        )
    }

    // MARK: - Status / graph state cross-checks for visible-range cases

    @MainActor
    func testBeyondVisibleStatusStaysOnBasisWhileGraphFlagsTrip() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 1_000_000)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.isBeyondVisibleRange)
        XCTAssertEqual(displayState.currentResult.statusText, "Beyond source range")
        XCTAssertEqual(displayState.summary.badgeText, "Beyond source range")
    }

    @MainActor
    func testSubSecondInputStatusReadsAsNoCorrection() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 1.0 / 30.0)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertFalse(
            graph.isBelowVisibleRange,
            "Stable viewport: sub-1 s inputs sit inside the visible plot."
        )
        XCTAssertEqual(displayState.currentResult.statusText, "No correction")
    }

    // MARK: - Main badge / Detail status alignment

    @MainActor
    func testMainBadgeAndDetailStatusUseTheSameWording() throws {
        let cases: [(meter: Double, expected: String)] = [
            (60, "No correction"),
            (240, "Formula-derived"),
            (600, "Beyond source range"),
        ]
        for (meter, expected) in cases {
            let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: meter)
            XCTAssertEqual(
                displayState.summary.badgeText,
                expected,
                "Main badge text for metered \(meter) s must read \(expected)."
            )
            XCTAssertEqual(
                displayState.currentResult.statusText,
                expected,
                "Detail status text for metered \(meter) s must read \(expected)."
            )
        }
    }

    // MARK: - Simplified Sources

    @MainActor
    func testSourcesAreAnUnlabeledListWithoutReferenceCitationLabels() throws {
        let displayState = try makeFormulaDetailsDisplayState(meteredExposureSeconds: 240)
        let sources = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Sources" }))
        XCTAssertEqual(sources.rows.map(\.title), ["", ""])
        XCTAssertFalse(sources.rows.contains { $0.title == "Reference" })
        XCTAssertFalse(sources.rows.contains { $0.title == "Citation" })

        let texts = sources.rows.map(\.value)
        XCTAssertTrue(
            texts.contains(where: { $0.contains("FUJICHROME PROVIA 100F") }),
            "Sources list must include the manufacturer reference text."
        )
        XCTAssertTrue(
            texts.contains(where: { $0.contains("Provia 100F support page") }),
            "Sources list must include the citation text."
        )
    }
}
