import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Unit-tests for the semantic ordering rule that drives the Film
/// Details Source reference block.
///
/// Sort priority is:
///   1. `sortValue` ascending (metered exposure start)
///   2. `kind` ascending (`pointAnchor` < `range` < `boundary` < `note`)
///   3. `catalogOffset` ascending (catalog declaration order)
final class SourceReferenceRowSortingTests: XCTestCase {

    // MARK: - SourceReferenceRowKind ordering

    func testRowKindRawValuesGivePointAnchorBeforeRangeBeforeBoundaryBeforeNote() {
        XCTAssertLessThan(SourceReferenceRowKind.pointAnchor, .range)
        XCTAssertLessThan(SourceReferenceRowKind.range, .boundary)
        XCTAssertLessThan(SourceReferenceRowKind.boundary, .note)
    }

    func testRowKindOrderingIsTransitiveAndStableAcrossAllPairs() {
        let ordered: [SourceReferenceRowKind] = [.pointAnchor, .range, .boundary, .note]
        for (i, lhs) in ordered.enumerated() {
            for (j, rhs) in ordered.enumerated() {
                if i < j {
                    XCTAssertLessThan(lhs, rhs, "\(lhs) must sort before \(rhs).")
                } else if i > j {
                    XCTAssertGreaterThan(lhs, rhs, "\(lhs) must sort after \(rhs).")
                } else {
                    XCTAssertEqual(lhs, rhs)
                }
            }
        }
    }

    // MARK: - SourceReferenceRowSortKey ordering

    func testKeysOrderBySortValueAscendingWhenKindsAndOffsetsAreEqual() {
        let unsorted = [
            SourceReferenceRowSortKey(sortValue: 10, kind: .pointAnchor, catalogOffset: 0),
            SourceReferenceRowSortKey(sortValue: 0.001, kind: .pointAnchor, catalogOffset: 1),
            SourceReferenceRowSortKey(sortValue: 1, kind: .pointAnchor, catalogOffset: 2),
        ]
        XCTAssertEqual(
            unsorted.sorted().map(\.sortValue),
            [0.001, 1, 10],
            "Keys with the same kind must sort by sortValue ascending."
        )
    }

    func testKeysWithSameSortValueOrderByKindPriority() {
        // CMS 20 II's 1/1000 s case: the published point anchor and
        // the no-correction band share `sortValue = 0.001`. The point
        // anchor must come first regardless of catalog order.
        let unsorted = [
            SourceReferenceRowSortKey(sortValue: 0.001, kind: .range, catalogOffset: 0),
            SourceReferenceRowSortKey(sortValue: 0.001, kind: .pointAnchor, catalogOffset: 1),
            SourceReferenceRowSortKey(sortValue: 0.001, kind: .note, catalogOffset: 2),
            SourceReferenceRowSortKey(sortValue: 0.001, kind: .boundary, catalogOffset: 3),
        ]
        XCTAssertEqual(
            unsorted.sorted().map(\.kind),
            [.pointAnchor, .range, .boundary, .note],
            "At a tie on sortValue, kind priority decides; got \(unsorted.sorted().map(\.kind))."
        )
    }

    func testKeysWithSameSortValueAndKindPreserveCatalogOrder() {
        let unsorted = [
            SourceReferenceRowSortKey(sortValue: 4, kind: .pointAnchor, catalogOffset: 2),
            SourceReferenceRowSortKey(sortValue: 4, kind: .pointAnchor, catalogOffset: 0),
            SourceReferenceRowSortKey(sortValue: 4, kind: .pointAnchor, catalogOffset: 5),
            SourceReferenceRowSortKey(sortValue: 4, kind: .pointAnchor, catalogOffset: 1),
        ]
        XCTAssertEqual(
            unsorted.sorted().map(\.catalogOffset),
            [0, 1, 2, 5],
            "At a tie on sortValue + kind, catalog declaration order wins."
        )
    }

    func testKeysSortAcrossAllThreeDimensions() {
        // Mixed input: every dimension matters somewhere in the
        // sorted output. Each key carries its expected final
        // position in `originalIndex`.
        let unsorted: [(key: SourceReferenceRowSortKey, expectedIndex: Int)] = [
            (.init(sortValue: 5, kind: .range, catalogOffset: 0), 4),
            (.init(sortValue: 1, kind: .range, catalogOffset: 1), 1),
            (.init(sortValue: 1, kind: .pointAnchor, catalogOffset: 2), 0),
            (.init(sortValue: 1, kind: .note, catalogOffset: 3), 2),
            (.init(sortValue: 5, kind: .pointAnchor, catalogOffset: 4), 3),
        ]
        let sortedKeys = unsorted.map(\.key).sorted()
        let originalCatalogOrder = unsorted.map(\.key.catalogOffset)
        let sortedCatalogOrder = sortedKeys.map(\.catalogOffset)
        XCTAssertEqual(
            sortedCatalogOrder,
            [2, 1, 3, 4, 0],
            "Mixed-dimension sort produced \(sortedCatalogOrder); original \(originalCatalogOrder)."
        )
    }

    // MARK: - Through-presenter integration check

    /// CMS 20 II is the only launch-catalog film whose threshold lower
    /// bound and an evidence row share a metered value. Run the rule
    /// end-to-end against the presenter so a future refactor of the
    /// sort plumbing cannot silently re-order the rendered block.
    @MainActor
    func testCms20IIThroughPresenterPlacesPointAnchorAboveRangeAtSameSortValue() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "CMS 20 II" }
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 5)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let displayState = try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(baseShutterSeconds: 5, stop: 0, resultShutterSeconds: 5)
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )

        let sourceReference = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" })?.rows.first?.value
        )
        let dataLines = sourceReference
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }

        XCTAssertGreaterThanOrEqual(
            dataLines.count,
            2,
            "Need at least two rows to verify the pointAnchor-before-range tiebreak."
        )
        // PTIMER-160 sorts the formula's no-correction band at
        // sortValue 0 (the band's effective start, since the formula
        // no longer carries an explicit lower bound), so the band row
        // leads and the 1/1000 s evidence-only point anchor follows.
        XCTAssertTrue(
            dataLines[0].contains("No correction"),
            "First rendered row must be the no-correction band; got: \(dataLines[0])"
        )
        XCTAssertTrue(
            dataLines[1].contains("*"),
            "Second rendered row must be the 1/1000 s point anchor (carries the * marker); got: \(dataLines[1])"
        )
    }

    /// Boundary rows (manufacturer not-recommended markers) must never
    /// be mixed into the Source reference section regardless of the
    /// sort rule. They render in the dedicated Guidance boundary
    /// section.
    @MainActor
    func testGuidanceBoundaryRowsStayOutOfSourceReferenceSection() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "CMS 20 II" }
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 5)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let displayState = try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(baseShutterSeconds: 5, stop: 0, resultShutterSeconds: 5)
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )

        let sourceReference = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" })?.rows.first?.value
        )
        XCTAssertFalse(
            sourceReference.contains("Not recommended"),
            "Source reference block must not contain the 100 s Not-recommended boundary row; got block:\n\(sourceReference)"
        )

        let guidanceBoundary = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" })?.rows.first?.value,
            "CMS 20 II must surface a Guidance boundary section that owns the Not-recommended row."
        )
        XCTAssertTrue(
            guidanceBoundary.contains("Not recommended"),
            "Guidance boundary block must carry the 100 s Not-recommended row; got: \(guidanceBoundary)"
        )
    }
}
