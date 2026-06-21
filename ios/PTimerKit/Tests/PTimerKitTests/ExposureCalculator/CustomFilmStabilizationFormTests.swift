// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Covers the form-validation + preview parsing + duration
/// parser invariants. All checks operate on the pure-value form
/// state and the strict preview parser; no SwiftUI view is
/// exercised.
final class CustomFilmStabilizationFormTests: XCTestCase {

    // MARK: - profileName is no longer required

    func test_validate_succeeds_withoutProfileName_whenManufacturerAndLabelPresent() throws {
        let state = CustomFilmEditorFormState(
            profileName: "",
            filmLabel: "T-MAX 100",
            isoText: "100",
            exponentText: "1.30",
            manufacturerText: "Kodak"
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Save should succeed without an explicit profile name")
        }
        XCTAssertEqual(film.profiles.first?.name, "Kodak T-MAX 100 · ISO 100")
        XCTAssertEqual(film.canonicalStockName, "Kodak T-MAX 100")
    }

    func test_validate_doesNotEmitMissingProfileNameAnymore() {
        let state = CustomFilmEditorFormState(
            profileName: "",
            filmLabel: "",
            isoText: "100",
            exponentText: "1.30"
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Empty label should still fail validation")
        }
        XCTAssertFalse(envelope.contains(.missingProfileName))
        XCTAssertTrue(envelope.contains(.missingFilmLabel))
    }

    // MARK: - composeDisplayName rules

    func test_composeDisplayName_appendsISOWhenISOProvided() {
        XCTAssertEqual(
            CustomFilmEditorFormState.composeDisplayName(
                manufacturer: "Kodak",
                label: "T-MAX 100",
                iso: 100
            ),
            "Kodak T-MAX 100 · ISO 100"
        )
        XCTAssertEqual(
            CustomFilmEditorFormState.composeDisplayName(
                manufacturer: "ADOX",
                label: "CMS 20 II",
                iso: 20
            ),
            "ADOX CMS 20 II · ISO 20"
        )
    }

    func test_composeDisplayName_handlesMissingSegments() {
        // Label only.
        XCTAssertEqual(
            CustomFilmEditorFormState.composeDisplayName(
                manufacturer: "",
                label: "NB1",
                iso: nil
            ),
            "NB1"
        )
        // Manufacturer + label, no ISO.
        XCTAssertEqual(
            CustomFilmEditorFormState.composeDisplayName(
                manufacturer: "Kodak",
                label: "NB1",
                iso: nil
            ),
            "Kodak NB1"
        )
    }

    // MARK: - Duration parser

    func test_durationParser_plainAndSuffixed() {
        XCTAssertEqual(CustomFilmDurationParser.parse("100"), .seconds(100))
        XCTAssertEqual(CustomFilmDurationParser.parse("100s"), .seconds(100))
        XCTAssertEqual(CustomFilmDurationParser.parse("5m"), .seconds(300))
        XCTAssertEqual(CustomFilmDurationParser.parse("1h"), .seconds(3600))
        XCTAssertEqual(CustomFilmDurationParser.parse("0.5m"), .seconds(30))
    }

    func test_durationParser_unlimitedKeyword() {
        XCTAssertEqual(CustomFilmDurationParser.parse("Unlimited"), .unlimited)
        XCTAssertEqual(CustomFilmDurationParser.parse("unlimited"), .unlimited)
    }

    func test_durationParser_emptyAndInvalid() {
        XCTAssertEqual(CustomFilmDurationParser.parse(""), .empty)
        XCTAssertEqual(CustomFilmDurationParser.parse("  "), .empty)
        XCTAssertNil(CustomFilmDurationParser.parse("abc"))
        XCTAssertNil(CustomFilmDurationParser.parse("100x"))
        XCTAssertNil(CustomFilmDurationParser.parse("xh"))
    }

    func test_validate_acceptsDurationSuffixesForValidThrough() throws {
        let state = makeValidState(validThroughText: "5m")
        guard case .success(let film) = state.validate(),
              case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected success with `5m` valid-through")
        }
        XCTAssertEqual(rule.formula.sourceRangeThroughSeconds ?? -1, 300.0, accuracy: 1e-9)
    }

    func test_validate_rejectsMalformedDurationString() {
        let state = makeValidState(validThroughText: "100x")
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Malformed duration should fail validation")
        }
        XCTAssertTrue(envelope.contains(.invalidValidThrough))
    }

    func test_validate_rejectsUnlimitedForNoCorrectionThrough() {
        let state = makeValidState(noCorrectionThroughText: "Unlimited")
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("'Unlimited' makes no sense for the no-correction threshold")
        }
        XCTAssertTrue(envelope.contains(.invalidNoCorrectionThrough))
    }

    // MARK: - Preview strict parsing

    func test_preview_emptyAnchors_useDefault() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "",
            baseTcText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard let parsed = CustomFilmEditorPreviewPresenter.parse(form: form) else {
            return XCTFail("Empty anchors should fall back to documented defaults")
        }
        XCTAssertEqual(parsed.baseTm, 1.0, accuracy: 1e-9)
        XCTAssertEqual(parsed.baseTc, 1.0, accuracy: 1e-9)
        XCTAssertEqual(parsed.offsetSeconds, 0.0, accuracy: 1e-9)
        XCTAssertNil(parsed.validThrough)
    }

    func test_preview_invalidBaseTm_yieldsNilParse() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "abc"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: form))
        let rows = CustomFilmEditorPreviewPresenter.rows(form: form)
        XCTAssertTrue(rows.allSatisfy { $0.status == .invalidFormulaResult })
    }

    func test_preview_invalidBaseTc_yieldsNilParse() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTcText: "abc"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: form))
    }

    func test_preview_invalidOffset_yieldsNilParse() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            offsetSecondsText: "abc"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: form))
    }

    func test_preview_invalidValidThrough_yieldsNilParse() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "bad"
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: form))
    }

    func test_preview_emptyValidThrough_treatedAsUnlimited() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard let parsed = CustomFilmEditorPreviewPresenter.parse(form: form) else {
            return XCTFail("Empty valid-through must parse as Unlimited")
        }
        XCTAssertNil(parsed.validThrough)
    }

    func test_preview_durationSuffixedValidThrough_parses() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "5m"
        )
        guard let parsed = CustomFilmEditorPreviewPresenter.parse(form: form) else {
            return XCTFail("`5m` valid-through should parse")
        }
        XCTAssertEqual(parsed.validThrough ?? -1, 300.0, accuracy: 1e-9)
    }

    // MARK: - Helpers

    private func makeValidState(
        profileName: String = "",
        filmLabel: String = "Stock",
        isoText: String = "100",
        sourceType: CustomProfileSourceType = .userDefined,
        notes: String = "",
        exponentText: String = "1.30",
        baseTmText: String = "1",
        baseTcText: String = "1",
        offsetSecondsText: String = "",
        noCorrectionThroughText: String = "1",
        validThroughText: String = "",
        manufacturerText: String = "Custom"
    ) -> CustomFilmEditorFormState {
        CustomFilmEditorFormState(
            profileName: profileName,
            filmLabel: filmLabel,
            isoText: isoText,
            sourceType: sourceType,
            notes: notes,
            exponentText: exponentText,
            baseTmText: baseTmText,
            baseTcText: baseTcText,
            offsetSecondsText: offsetSecondsText,
            noCorrectionThroughText: noCorrectionThroughText,
            validThroughText: validThroughText,
            manufacturerText: manufacturerText
        )
    }
}
