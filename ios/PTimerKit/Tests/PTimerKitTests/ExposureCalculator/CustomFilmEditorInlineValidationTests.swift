import XCTest
import PTimerKit

/// PTIMER-84 polish: covers
/// `CustomFilmEditorFormState.inlineValidationReason(for:isEditing:)`,
/// the row-keyed validation surface the compact editor renders
/// directly under each tap-to-edit summary row. The function
/// returns short, action-oriented copy so the layout never gains
/// a separate red row that would push other rows down/up.
final class CustomFilmEditorInlineValidationTests: XCTestCase {

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

    /// One invalid field at a time, against an otherwise valid form,
    /// produces that field's compact inline hint (each invalid input ->
    /// expected hint is a case row).
    func test_invalidField_returnsExpectedCompactInlineHint() {
        struct Case {
            let name: String
            let mutate: (inout CustomFilmEditorFormState) -> Void
            let field: CustomFilmEditorField
            let expected: String
        }
        let cases: [Case] = [
            Case(name: "missing label", mutate: { $0.filmLabel = "" }, field: .label, expected: "Required"),
            Case(name: "invalid ISO", mutate: { $0.isoText = "abc" }, field: .iso, expected: "Enter 1–100000"),
            Case(name: "missing exponent", mutate: { $0.exponentText = "" }, field: .exponent, expected: "p is required"),
            Case(name: "invalid exponent", mutate: { $0.exponentText = "abc" }, field: .exponent, expected: "p must be > 0"),
            Case(name: "invalid reference Tm", mutate: { $0.baseTmText = "abc" }, field: .referenceTm, expected: "Tm₀ must be > 0"),
            Case(name: "invalid corrected Tc", mutate: { $0.baseTcText = "abc" }, field: .correctedAtReference, expected: "Tc₀ must be > 0"),
            Case(name: "invalid offset", mutate: { $0.offsetSecondsText = "-" }, field: .offset, expected: "b must be a finite duration"),
            Case(name: "invalid no-correction", mutate: { $0.noCorrectionThroughText = "Unlimited" }, field: .noCorrectionThrough, expected: "Must be ≥ 0"),
            Case(name: "source range below no-correction", mutate: { $0.noCorrectionThroughText = "1"; $0.validThroughText = "0.5" }, field: .sourceRangeThrough, expected: "Must be > No correction"),
        ]
        for c in cases {
            var form = makeFullyValidForm()
            c.mutate(&form)
            XCTAssertEqual(
                form.inlineValidationReason(for: c.field, isEditing: false),
                c.expected,
                "[\(c.name)] field \(c.field)"
            )
        }
    }

    func test_validForm_returnsNilForEveryField() {
        let form = makeFullyValidForm()
        for field in CustomFilmEditorField.allCases {
            XCTAssertNil(
                form.inlineValidationReason(for: field, isEditing: false),
                "Field \(field) must stay quiet on a fully valid form."
            )
        }
    }

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
