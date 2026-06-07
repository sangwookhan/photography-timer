import XCTest
import PTimerKit
@testable import PTimer

/// Covers the editor preview presenter's Tm→Tc evaluation and
/// curve generation. The presenter is a pure value transform so
/// tests bind directly to its output without exercising the
/// SwiftUI view.
final class CustomFilmEditorPreviewPresenterTests: XCTestCase {

    func test_rows_belowThreshold_marksNoCorrection() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "240"
        )
        let firstRow = CustomFilmEditorPreviewPresenter.rows(form: form).first
        XCTAssertEqual(firstRow?.meteredSeconds, 1.0)
        XCTAssertEqual(firstRow?.status, .noCorrection)
        XCTAssertEqual(firstRow?.correctedSeconds, 1.0)
    }

    func test_rows_insideFormulaRange_appliesFormula() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "120"
        )
        // Use explicit samples so this test does not depend on the
        // editor's default ladder.
        let rows = CustomFilmEditorPreviewPresenter.rows(form: form, samples: [1, 4, 30])
        // 4s sample sits well inside the formula range:
        // Tc = 4^1.3 ≈ 6.063.
        guard let fourSecondRow = rows.first(where: { $0.meteredSeconds == 4 }) else {
            return XCTFail("Expected 4s sample row")
        }
        XCTAssertEqual(fourSecondRow.status, .formulaApplied)
        XCTAssertEqual(fourSecondRow.correctedSeconds ?? -1, pow(4.0, 1.30), accuracy: 0.01)
        XCTAssertGreaterThan(fourSecondRow.stopDelta ?? 0, 0)
    }

    func test_rows_beyondSourceRange_keepsCalculatingWithReducedConfidence() {
        // Source/fitting confidence boundary semantics: a sample
        // past `sourceRangeThroughSeconds` still has a
        // formula-derived corrected value; only the status flips
        // to `.beyondSourceRange` so the preview table reads the
        // reduced confidence rather than missing data.
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: [1, 10, 120, 300]
        )
        let beyondSamples = rows.filter { $0.meteredSeconds == 120 || $0.meteredSeconds == 300 }
        XCTAssertEqual(beyondSamples.count, 2)
        for row in beyondSamples {
            XCTAssertEqual(row.status, .beyondSourceRange)
            // Formula = Tm^1.30 — 120s → ≈459s, 300s → ≈1402s.
            let expected = pow(row.meteredSeconds, 1.30)
            XCTAssertEqual(row.correctedSeconds ?? -1, expected, accuracy: 0.5)
            XCTAssertNotNil(row.stopDelta)
        }
    }

    func test_rows_invalidExponent_marksEveryRowInvalid() {
        let form = CustomFilmEditorFormState(
            exponentText: "not-a-number",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(form: form)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.status == .invalidFormulaResult })
        XCTAssertTrue(rows.allSatisfy { $0.correctedSeconds == nil })
    }

    func test_rows_defaultsMultiplierOneAndOffsetZero() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            // coefficient + offset blank.
            noCorrectionThroughText: "1",
            validThroughText: "240"
        )
        guard let row = CustomFilmEditorPreviewPresenter
            .rows(form: form, samples: [4])
            .first(where: { $0.meteredSeconds == 4 }) else {
            return XCTFail("Expected 4s row")
        }
        // Tc = 1·4^1.30 + 0 = 4^1.30
        XCTAssertEqual(row.correctedSeconds ?? -1, pow(4.0, 1.30), accuracy: 0.001)
    }

    // MARK: - Duration-string parser policy

    /// The preview parser routes every duration field through
    /// `CustomFilmDurationParser` so the editor's keyboard policy
    /// (`100`, `100s`, `5m`, `1h`) and the preview accept the same
    /// input shapes. `Unlimited` stays restricted to
    /// `validThrough`.

    func test_parse_anchorAccepts_durationStringWithSuffix() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "0.1s",
            baseTcText: "0.1s",
            offsetSecondsText: "1s",
            noCorrectionThroughText: "1",
            validThroughText: "5m"
        )
        let parsed = CustomFilmEditorPreviewPresenter.parse(form: form)
        XCTAssertEqual(parsed?.baseTm ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(parsed?.baseTc ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(parsed?.offsetSeconds ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(parsed?.validThrough ?? 0, 300.0, accuracy: 1e-9)
    }

    func test_parse_anchorRejectsUnlimited() {
        let baseTmForm = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "Unlimited",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: baseTmForm))

        let baseTcForm = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTcText: "Unlimited",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: baseTcForm))
    }

    func test_parse_offsetRejectsUnlimitedAndGarbage() {
        let unlimited = CustomFilmEditorFormState(
            exponentText: "1.30",
            offsetSecondsText: "Unlimited",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: unlimited))

        let dashOnly = CustomFilmEditorFormState(
            exponentText: "1.30",
            offsetSecondsText: "-",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: dashOnly))
    }

    func test_parse_anchorRejectsGarbage() {
        let baseTmForm = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "abc",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: baseTmForm))

        let baseTcForm = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTcText: "abc",
            noCorrectionThroughText: "1",
            validThroughText: "60"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: baseTcForm))
    }

    func test_parse_validThroughEmptyMeansUnlimited() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        let parsed = CustomFilmEditorPreviewPresenter.parse(form: form)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.validThrough)
    }
}
