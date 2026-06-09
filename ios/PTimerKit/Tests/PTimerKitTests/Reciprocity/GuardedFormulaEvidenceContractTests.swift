import XCTest
import PTimerKit
import PTimerCore

/// Source-evidence contract for the converted guarded formula archetype.
/// Every member preserves its manufacturer-published rows as display-only
/// `sourceEvidence` (never as calculation anchors). The exact rows — and
/// each row's color filter, stop delta, corrected time, not-recommended
/// marker, range note, or source-evidence-only flag — are preserved here
/// as explicit per-film case data; only the assertion shape is shared, so
/// no film name appears in a function name.
final class GuardedFormulaEvidenceContractTests: XCTestCase {

    /// Expectations for one published source-evidence row.
    private struct EvidenceRow {
        let metered: Double
        var filterName: String?
        var exactStopDelta: Double?
        var requiresStopDelta = false
        var correctedSeconds: Double?
        var notRecommended = false
        var rangeNoteContains: String?
        var sourceEvidenceOnly = false
        var forbidsQuantifiedExposure = false
    }

    private struct SourceEvidenceCase {
        let film: String
        /// Expected exact-second rows. Compared in encounter order when
        /// `meteredsAreOrdered`, else sorted. `nil` skips the list check
        /// (e.g. Provia, which only pinned two specific rows).
        let expectedMetereds: [Double]?
        let meteredsAreOrdered: Bool
        let rows: [EvidenceRow]
    }

    private let cases: [SourceEvidenceCase] = [
        SourceEvidenceCase(
            film: "Velvia 50",
            expectedMetereds: [4, 8, 16, 32, 64],
            meteredsAreOrdered: true,
            rows: [
                EvidenceRow(metered: 4, filterName: "5M", requiresStopDelta: true),
                EvidenceRow(metered: 8, filterName: "7.5M", requiresStopDelta: true),
                EvidenceRow(metered: 16, filterName: "10M", requiresStopDelta: true),
                EvidenceRow(metered: 32, filterName: "12.5M", requiresStopDelta: true),
                EvidenceRow(metered: 64, notRecommended: true),
            ]
        ),
        SourceEvidenceCase(
            film: "Velvia 100",
            expectedMetereds: [120, 240],
            meteredsAreOrdered: true,
            rows: [
                EvidenceRow(metered: 120, filterName: "2.5M"),
                EvidenceRow(metered: 240, filterName: "2.5M"),
            ]
        ),
        SourceEvidenceCase(
            film: "Provia 100F",
            expectedMetereds: nil,
            meteredsAreOrdered: false,
            rows: [
                EvidenceRow(metered: 240, filterName: "2.5G", exactStopDelta: 1.0 / 3.0),
                EvidenceRow(metered: 480, notRecommended: true),
            ]
        ),
        SourceEvidenceCase(
            film: "CMS 20 II",
            expectedMetereds: [0.001, 1, 10, 100],
            meteredsAreOrdered: true,
            rows: [
                EvidenceRow(metered: 0.001, exactStopDelta: 0.5, sourceEvidenceOnly: true),
                EvidenceRow(metered: 100, notRecommended: true),
            ]
        ),
    ]

    private func exactRows(in profile: ReciprocityProfile) -> [(Double, ReciprocitySourceEvidenceRow)] {
        profile.sourceEvidence.compactMap { row in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
    }

    func testSourceEvidencePreservesPublishedRows() throws {
        for c in cases {
            let profile = try FormulaProfileTestSupport.profile(for: c.film)
            let exact = exactRows(in: profile)

            if let expected = c.expectedMetereds {
                let metereds = exact.map { $0.0 }
                let actual = c.meteredsAreOrdered ? metereds : metereds.sorted()
                let wanted = c.meteredsAreOrdered ? expected : expected.sorted()
                XCTAssertEqual(actual, wanted, "\(c.film): published source-evidence rows must be preserved.")
            }

            for expectedRow in c.rows {
                let row = try XCTUnwrap(
                    exact.first(where: { abs($0.0 - expectedRow.metered) < 1e-6 })?.1,
                    "\(c.film): must preserve the \(expectedRow.metered)s published row as source evidence."
                )
                assertColorFilter(expectedRow, row, film: c.film)
                assertStopDelta(expectedRow, row, film: c.film)
                assertCorrectedTime(expectedRow, row, film: c.film)
                assertMarkers(expectedRow, row, film: c.film)
            }
        }
    }

    private func colorFilter(in row: ReciprocitySourceEvidenceRow) -> String? {
        row.adjustments.compactMap { adjustment -> String? in
            guard case let .colorFilter(recommendation) = adjustment else { return nil }
            return recommendation.filterName
        }.first
    }

    private func hasExposureAdjustment(in row: ReciprocitySourceEvidenceRow) -> Bool {
        row.adjustments.contains { if case .exposure = $0 { return true }; return false }
    }

    private func assertColorFilter(_ expected: EvidenceRow, _ row: ReciprocitySourceEvidenceRow, film: String) {
        guard let filter = expected.filterName else { return }
        XCTAssertEqual(colorFilter(in: row), filter, "\(film) @ \(expected.metered)s: published color filter")
    }

    private func assertStopDelta(_ expected: EvidenceRow, _ row: ReciprocitySourceEvidenceRow, film: String) {
        let actual = row.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
            return value.stopDelta
        }.first
        if let stopDelta = expected.exactStopDelta {
            XCTAssertEqual(actual ?? .nan, stopDelta, accuracy: 1e-4, "\(film) @ \(expected.metered)s: published stop delta")
        }
        if expected.requiresStopDelta {
            XCTAssertNotNil(actual, "\(film) @ \(expected.metered)s: must keep a stop-delta adjustment.")
        }
    }

    private func assertCorrectedTime(_ expected: EvidenceRow, _ row: ReciprocitySourceEvidenceRow, film: String) {
        guard let corrected = expected.correctedSeconds else { return }
        let actual = row.adjustments.compactMap { adjustment -> Double? in
            guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
            return mapping.correctedSeconds
        }.first
        XCTAssertEqual(actual ?? .nan, corrected, accuracy: 1e-6, "\(film) @ \(expected.metered)s: published corrected time")
    }

    private func assertMarkers(_ expected: EvidenceRow, _ row: ReciprocitySourceEvidenceRow, film: String) {
        if expected.notRecommended {
            let severity = row.adjustments.compactMap { adjustment -> ReciprocityWarningSeverity? in
                guard case let .warning(warning) = adjustment else { return nil }
                return warning.severity
            }.first
            XCTAssertEqual(severity, .notRecommended, "\(film) @ \(expected.metered)s: not-recommended warning")
        }
        if let marker = expected.rangeNoteContains {
            let has = row.adjustments.contains { adjustment in
                if case let .note(note) = adjustment { return note.text.contains(marker) }
                return false
            }
            XCTAssertTrue(has, "\(film) @ \(expected.metered)s: must keep the published '\(marker)' range note.")
        }
        if expected.sourceEvidenceOnly {
            XCTAssertTrue(row.isSourceEvidenceOnly, "\(film) @ \(expected.metered)s: must be flagged source-evidence-only.")
        }
        if expected.forbidsQuantifiedExposure {
            XCTAssertFalse(hasExposureAdjustment(in: row), "\(film) @ \(expected.metered)s: range-valued row must not carry a quantified exposure adjustment.")
        }
    }
}
