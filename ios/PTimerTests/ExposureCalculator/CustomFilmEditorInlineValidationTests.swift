import XCTest
import PTimerKit
@testable import PTimer

/// PTIMER-84 polish: covers
/// `CustomFilmEditorFormState.inlineValidationReason(for:isEditing:)`,
/// the row-keyed validation surface the compact editor renders
/// directly under each tap-to-edit summary row. The function
/// returns short, action-oriented copy so the layout never gains
/// a separate red row that would push other rows down/up.
final class CustomFilmEditorInlineValidationTests: XCTestCase {

    // MARK: - Untouched empty new form

    func test_untouchedNewForm_returnsNil_forEveryField() {
        // Every field at its initial blank state: the inline
        // hints must stay suppressed across the whole form so the
        // editor opens quiet.
        let form = CustomFilmEditorFormState()
        XCTAssertTrue(form.isUntouchedNewForm())
        for field in CustomFilmEditorField.allCases {
            XCTAssertNil(
                form.inlineValidationReason(for: field, isEditing: false),
                "Field \(field) must stay quiet on the untouched new-form state."
            )
        }
    }

    func test_editingFlow_doesNotSuppressEvenIfFieldsLookUntouched() {
        // Edit flow always pre-fills the fields; the defensive
        // `isUntouchedNewForm()` heuristic only short-circuits
        // the New flow. Even an artificially-blank form must
        // still report missing-label / missing-exponent reasons
        // when isEditing == true.
        let form = CustomFilmEditorFormState()
        XCTAssertEqual(
            form.inlineValidationReason(for: .label, isEditing: true),
            "Required"
        )
        XCTAssertEqual(
            form.inlineValidationReason(for: .exponent, isEditing: true),
            "p is required"
        )
    }

    // MARK: - Label

    func test_missingLabel_returnsRequired() {
        var form = makeFullyValidForm()
        form.filmLabel = ""
        XCTAssertEqual(
            form.inlineValidationReason(for: .label, isEditing: false),
            "Required"
        )
        // Other fields stay quiet for this isolated case.
        XCTAssertNil(form.inlineValidationReason(for: .iso, isEditing: false))
        XCTAssertNil(form.inlineValidationReason(for: .exponent, isEditing: false))
    }

    // MARK: - ISO

    func test_invalidISO_returnsBoundedRangeHint() {
        var form = makeFullyValidForm()
        form.isoText = "abc"
        let reason = form.inlineValidationReason(for: .iso, isEditing: false)
        XCTAssertEqual(reason, "Enter 1–100000")
    }

    // MARK: - Exponent

    func test_missingExponent_returnsRequired() {
        var form = makeFullyValidForm()
        form.exponentText = ""
        XCTAssertEqual(
            form.inlineValidationReason(for: .exponent, isEditing: false),
            "p is required"
        )
    }

    func test_invalidExponent_returnsCompactConstraintHint() {
        var form = makeFullyValidForm()
        form.exponentText = "abc"
        XCTAssertEqual(
            form.inlineValidationReason(for: .exponent, isEditing: false),
            "p must be > 0"
        )
    }

    // MARK: - Anchors

    func test_invalidReferenceTm_returnsCompactConstraintHint() {
        var form = makeFullyValidForm()
        form.baseTmText = "abc"
        XCTAssertEqual(
            form.inlineValidationReason(for: .referenceTm, isEditing: false),
            "Tm₀ must be > 0"
        )
    }

    func test_invalidCorrectedAtReference_returnsCompactConstraintHint() {
        var form = makeFullyValidForm()
        form.baseTcText = "abc"
        XCTAssertEqual(
            form.inlineValidationReason(for: .correctedAtReference, isEditing: false),
            "Tc₀ must be > 0"
        )
    }

    // MARK: - Offset

    func test_invalidOffset_returnsFiniteDurationHint() {
        var form = makeFullyValidForm()
        form.offsetSecondsText = "-"
        XCTAssertEqual(
            form.inlineValidationReason(for: .offset, isEditing: false),
            "b must be a finite duration"
        )
    }

    // MARK: - No-correction / source range

    func test_invalidNoCorrectionThrough_returnsCompactConstraintHint() {
        var form = makeFullyValidForm()
        form.noCorrectionThroughText = "Unlimited"
        XCTAssertEqual(
            form.inlineValidationReason(
                for: .noCorrectionThrough,
                isEditing: false
            ),
            "Must be ≥ 0"
        )
    }

    func test_invalidSourceRangeBelowNoCorrection_returnsCompactConstraintHint() {
        var form = makeFullyValidForm()
        form.noCorrectionThroughText = "1"
        form.validThroughText = "0.5"
        XCTAssertEqual(
            form.inlineValidationReason(
                for: .sourceRangeThrough,
                isEditing: false
            ),
            "Must be > No correction"
        )
    }

    // MARK: - Valid form returns nil per field

    func test_validForm_returnsNilForEveryField() {
        let form = makeFullyValidForm()
        for field in CustomFilmEditorField.allCases {
            XCTAssertNil(
                form.inlineValidationReason(for: field, isEditing: false),
                "Field \(field) must stay quiet on a fully valid form."
            )
        }
    }

    // MARK: - Helpers

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
