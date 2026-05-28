import XCTest
@testable import PTimer

/// PTIMER-84 follow-up: covers
/// `CustomFilmEditorPreviewPresenter.diagnose(form:)`, the
/// recovery-oriented diagnostic surface the preview card uses to
/// swap row-level "Invalid formula result" repetition for a single
/// reason-aware message.
final class CustomFilmEditorPreviewDiagnoseTests: XCTestCase {

    func test_diagnose_validForm_returnsNil() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.diagnose(form: form))
    }

    // MARK: - Empty / neutral state

    func test_diagnose_emptyExponent_isNeutralReason() {
        // Brand-new editor form: exponent blank, everything else
        // at documented defaults. Diagnose must return a neutral
        // `.emptyExponent` so the view can render a placeholder
        // message instead of red error styling.
        let form = CustomFilmEditorFormState()
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.diagnose(form: form),
            .emptyExponent
        )
    }

    // MARK: - Per-field invalid reasons

    func test_diagnose_invalidExponent_returnsExponentReason() {
        let form = CustomFilmEditorFormState(exponentText: "abc")
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.diagnose(form: form),
            .invalidExponent
        )
    }

    func test_diagnose_invalidBaseTm_returnsBaseTmReason() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "abc"
        )
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.diagnose(form: form),
            .invalidBaseTm
        )
    }

    func test_diagnose_invalidBaseTc_returnsBaseTcReason() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTcText: "abc"
        )
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.diagnose(form: form),
            .invalidBaseTc
        )
    }

    func test_diagnose_invalidOffset_returnsOffsetReason() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            offsetSecondsText: "-"
        )
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.diagnose(form: form),
            .invalidOffset
        )
    }

    func test_diagnose_invalidSourceRangeBelowNoCorrection_returnsSourceRangeReason() {
        // Source range = 0.5s is below the no-correction threshold
        // of 1s, which the validator rejects.
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "0.5"
        )
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.diagnose(form: form),
            .invalidSourceRange
        )
    }

    // MARK: - Display message wording

    func test_displayMessage_usesSymbolAnchoredVocabulary() {
        // Anchor reasons use the same symbol-anchored vocabulary
        // (`Tm₀`, `Tc₀`) the editor rows use, so the preview's
        // recovery panel reads consistently with the row labels
        // the photographer just left.
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.InvalidReason
                .invalidBaseTm.displayMessage,
            "Tm₀ must be > 0."
        )
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.InvalidReason
                .invalidBaseTc.displayMessage,
            "Tc₀ must be > 0."
        )
    }
}
