import XCTest
import PTimerKit

/// PTIMER-84 polish: covers
/// `CustomFilmEditorFormState.saveDisabledReason(isEditing:)`. The
/// summary is now narrowed to **cross-field structural issues**
/// — currently only the `formulaShortensExposure` invariant. All
/// per-field reasons surface through
/// `inlineValidationReason(for:isEditing:)` next to the matching
/// compact summary row instead.
final class CustomFilmEditorSaveDisabledReasonTests: XCTestCase {

    // MARK: - Valid form → no reason

    func test_validForm_returnsNilReason() {
        let form = makeFullyValidForm()
        XCTAssertNil(form.saveDisabledReason(isEditing: false))
        XCTAssertNil(form.saveDisabledReason(isEditing: true))
    }

    // MARK: - Untouched empty new form → suppressed

    func test_untouchedNewForm_returnsNil_evenThoughExponentIsMissing() {
        // Fresh editor open: every field at its initial blank state.
        // Save is disabled (exponent is required + label is missing),
        // but the editor must stay quiet until the photographer
        // engages with the form.
        let form = CustomFilmEditorFormState()
        XCTAssertTrue(form.isUntouchedNewForm())
        XCTAssertNil(form.saveDisabledReason(isEditing: false))
    }

    // MARK: - Per-field reasons surface inline, not in the summary

    func test_perFieldErrors_returnNil_soInlineHintsLead() {
        // These cases previously surfaced through the summary;
        // the polish pass moves them to per-row inline hints (see
        // `CustomFilmEditorInlineValidationTests`), so the
        // cross-field summary must stay quiet for them.
        var form = makeFullyValidForm()
        form.exponentText = ""
        XCTAssertNil(form.saveDisabledReason(isEditing: false))

        form = makeFullyValidForm()
        form.exponentText = "abc"
        XCTAssertNil(form.saveDisabledReason(isEditing: false))

        form = makeFullyValidForm()
        form.baseTmText = "abc"
        XCTAssertNil(form.saveDisabledReason(isEditing: false))

        form = makeFullyValidForm()
        form.baseTcText = "abc"
        XCTAssertNil(form.saveDisabledReason(isEditing: false))

        form = makeFullyValidForm()
        form.noCorrectionThroughText = "1"
        form.validThroughText = "0.5"
        XCTAssertNil(form.saveDisabledReason(isEditing: false))
    }

    // MARK: - Cross-field formula shortening → surfaced

    func test_formulaShortensExposure_surfacesFormulaConstraintReason() {
        // Anchor pair that would yield a corrected exposure
        // shorter than the metered input — the stabilization
        // guard raises `.formulaShortensExposure`. The recovery
        // message reads as a compact formula constraint
        // (`Tc₀ must be ≥ Tm₀`) plus the offending values
        // (`Current: 1s < 2s`) so the photographer can match it
        // against the formula tokens above without re-parsing a
        // long sentence.
        var form = makeFullyValidForm()
        form.formulaInputMode = .scaled
        form.baseTmText = "2"
        form.baseTcText = "1"
        let reason = form.saveDisabledReason(isEditing: false)
        XCTAssertNotNil(reason)
        let lines = (reason ?? "").components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "Tc₀ must be ≥ Tm₀")
        XCTAssertEqual(lines[1], "Current: 1s < 2s")
    }

    func test_formulaShortensExposure_doesNotEmitOldSentenceWording() {
        // Regression guard: the previous "Corrected exposure must
        // not be shorter than metered exposure." wording is hard
        // to scan and must never resurface in the editor.
        var form = makeFullyValidForm()
        form.baseTmText = "2"
        form.baseTcText = "1"
        let reason = form.saveDisabledReason(isEditing: false) ?? ""
        XCTAssertFalse(reason.contains("Corrected exposure"))
        XCTAssertFalse(reason.contains("shorter than"))
    }

    // MARK: - Identity-only failures stay quiet in the summary

    func test_identityOnlyErrors_returnNil_soInlineHintsLead() {
        // Formula side is fully valid; the only remaining error
        // is an identity issue (missing label). The summary
        // surface must defer to the per-row Label hint instead of
        // paraphrasing it inside the Formula card.
        var form = makeFullyValidForm()
        form.filmLabel = ""
        XCTAssertNil(form.saveDisabledReason(isEditing: false))

        form = makeFullyValidForm()
        form.isoText = ""
        XCTAssertNil(form.saveDisabledReason(isEditing: false))
    }

    // MARK: - Helpers

    /// Returns a form that passes `validate()` cleanly. Per-test
    /// mutations then introduce a single targeted issue so each
    /// assertion isolates one reason.
    private func makeFullyValidForm() -> CustomFilmEditorFormState {
        return CustomFilmEditorFormState(
            filmLabel: "Custom",
            isoText: "100",
            formulaInputMode: .basic,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
    }
}
