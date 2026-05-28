import XCTest
@testable import PTimer

/// PTIMER-84 polish: covers the inline Live Check block the editor
/// renders directly under the formula inputs. The block is a pure
/// reuse of `CustomFilmEditorPreviewPresenter.rows(form:samples:)`
/// fed with the compact `liveCheckSampleSeconds` ladder; these
/// tests pin the sample shape and the status flags the editor view
/// reads to color and decorate each row.
final class CustomFilmEditorLiveCheckTests: XCTestCase {

    // MARK: - Sample shape

    func test_liveCheckSamples_areExactlyOneSecondTenSecondsOneMinute() {
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds,
            [1, 10, 60]
        )
    }

    // MARK: - Basic formula

    func test_basicFormula_producesExpectedThreeRowSnapshot() {
        // Basic: Tc = Tm^1.30 with no-correction at 1s.
        let form = CustomFilmEditorFormState(
            formulaInputMode: .basic,
            exponentText: "1.30",
            noCorrectionThroughText: "1"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        XCTAssertEqual(rows.count, 3)

        // 1s sits on the no-correction boundary → status flips to
        // `.noCorrection` and corrected == metered.
        XCTAssertEqual(rows[0].meteredSeconds, 1)
        XCTAssertEqual(rows[0].status, .noCorrection)
        XCTAssertEqual(rows[0].correctedSeconds, 1)

        // 10s and 1m apply the formula.
        XCTAssertEqual(rows[1].meteredSeconds, 10)
        XCTAssertEqual(rows[1].status, .formulaApplied)
        XCTAssertEqual(rows[1].correctedSeconds ?? -1, pow(10.0, 1.30), accuracy: 0.05)

        XCTAssertEqual(rows[2].meteredSeconds, 60)
        XCTAssertEqual(rows[2].status, .formulaApplied)
        XCTAssertEqual(rows[2].correctedSeconds ?? -1, pow(60.0, 1.30), accuracy: 0.5)
    }

    // MARK: - Scaled formula

    func test_scaledFormula_appliesAnchorPairToEverySample() {
        // T-MAX 100 style: Tc = 0.1 × (Tm / 0.1)^1.0966 — non-trivial
        // anchor and exponent so the live check must reuse the same
        // policy as the full preview path.
        let form = CustomFilmEditorFormState(
            formulaInputMode: .scaled,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            noCorrectionThroughText: "1"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        XCTAssertEqual(rows.count, 3)
        // 10s: 0.1 × (10/0.1)^1.0966 ≈ 0.1 × 100^1.0966
        let tenSeconds = rows.first(where: { $0.meteredSeconds == 10 })?.correctedSeconds
        XCTAssertNotNil(tenSeconds)
        XCTAssertEqual(
            tenSeconds ?? -1,
            0.1 * pow(10.0 / 0.1, 1.0966),
            accuracy: 0.05
        )
    }

    // MARK: - Advanced formula

    func test_advancedFormula_appliesOffsetAfterCurve() {
        let form = CustomFilmEditorFormState(
            formulaInputMode: .advanced,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "1s",
            noCorrectionThroughText: "1"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        let tenSeconds = rows.first(where: { $0.meteredSeconds == 10 })?.correctedSeconds
        XCTAssertNotNil(tenSeconds)
        XCTAssertEqual(
            tenSeconds ?? -1,
            pow(10.0, 1.30) + 1.0,
            accuracy: 0.05
        )
    }

    // MARK: - No-correction respected

    func test_liveCheck_respectsNoCorrectionThroughThreshold() {
        // Photographer extends the no-correction boundary to 30s.
        // The first two samples (1s and 10s) must read as
        // `.noCorrection`; only the 60s sample applies the formula.
        let form = CustomFilmEditorFormState(
            formulaInputMode: .basic,
            exponentText: "1.30",
            noCorrectionThroughText: "30"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        XCTAssertEqual(rows[0].status, .noCorrection)
        XCTAssertEqual(rows[1].status, .noCorrection)
        XCTAssertEqual(rows[2].status, .formulaApplied)
    }

    // MARK: - Beyond source range marked

    func test_liveCheck_marksSampleBeyondSourceRange() {
        // Source range = 30s, so the 60s sample sits past the
        // confidence boundary. The status must flip to
        // `.beyondSourceRange`, which the editor view renders as a
        // subtle "· beyond" trailing marker.
        let form = CustomFilmEditorFormState(
            formulaInputMode: .basic,
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "30"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        XCTAssertEqual(rows[0].status, .noCorrection)
        XCTAssertEqual(rows[1].status, .formulaApplied)
        XCTAssertEqual(rows[2].status, .beyondSourceRange)
        // Beyond-source-range still carries a corrected value; the
        // editor only suppresses invalid rows from the live check.
        XCTAssertNotNil(rows[2].correctedSeconds)
    }

    // MARK: - Invalid form hides the block

    func test_liveCheck_hidesEveryRow_whenFormulaIsInvalid() {
        // Garbage exponent — parser returns nil and every row
        // collapses to `.invalidFormulaResult` with `correctedSeconds
        // == nil`, which the view filters out so the Live Check
        // block disappears entirely.
        let form = CustomFilmEditorFormState(exponentText: "abc")
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        XCTAssertTrue(rows.allSatisfy { $0.status == .invalidFormulaResult })
        XCTAssertTrue(rows.allSatisfy { $0.correctedSeconds == nil })
    }
}
