import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

final class CustomFilmEditorFormStateTests: XCTestCase {

    // MARK: - Successful validation

    func test_validate_validInput_returnsCustomFilmIdentity() {
        let state = CustomFilmEditorFormState(
            profileName: "Personal Provia",
            filmLabel: "My Provia 100F",
            isoText: "100",
            sourceType: .personalTest,
            notes: "Bracketed at 1s, 4s, 30s",
            exponentText: "1.30",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: "240"
        )

        let counter = IDCounter()
        let result = state.validate(idGenerator: counter.next)

        switch result {
        case .failure(let errors):
            XCTFail("Expected success, got errors: \(errors)")
        case .success(let film):
            XCTAssertEqual(film.kind, .custom)
            XCTAssertEqual(film.canonicalStockName, "My Provia 100F")
            XCTAssertEqual(film.iso, 100)
            XCTAssertEqual(film.profiles.count, 1)
            let profile = film.profiles[0]
            // The editor auto-generates the profile name from
            // `Manufacturer + Label · ISO`. With no manufacturer
            // the composer emits `"<label> · ISO <iso>"`.
            XCTAssertEqual(profile.name, "My Provia 100F · ISO 100")
            XCTAssertEqual(profile.source.authority, .userDefined)
            XCTAssertEqual(profile.source.kind, .userDefined)
            XCTAssertEqual(profile.userMetadata?.customSourceType, .personalTest)
            XCTAssertEqual(profile.userMetadata?.notes, ["Bracketed at 1s, 4s, 30s"])

            // The shared formula carries the no-correction and
            // source-range boundaries directly on the formula, so
            // a custom profile saves with a single formula rule.
            XCTAssertEqual(profile.rules.count, 1)
            guard case .formula(let rule) = profile.rules.first else {
                return XCTFail("Expected formula rule, got \(profile.rules)")
            }
            XCTAssertEqual(rule.formula.formulaFamily, .modifiedSchwarzschild)
            XCTAssertEqual(rule.formula.exponent, 1.30, accuracy: 0.0001)
            XCTAssertEqual(rule.formula.coefficientSeconds, 1, accuracy: 1e-9)
            XCTAssertEqual(rule.formula.offsetSeconds, 0, accuracy: 1e-9)
            XCTAssertEqual(rule.formula.noCorrectionThroughSeconds, 1, accuracy: 0.0001)
            XCTAssertEqual(rule.formula.sourceRangeThroughSeconds ?? -1, 240.0, accuracy: 0.0001)
        }
    }

    func test_validate_acceptsOptionalCoefficientAndOffset() {
        let state = CustomFilmEditorFormState(
            profileName: "Tweaked",
            filmLabel: "Custom HP5",
            isoText: "400",
            sourceType: .userDefined,
            notes: "",
            exponentText: "1.31",
            baseTcText: "1.10",
            offsetSecondsText: "0.05",
            noCorrectionThroughText: "1",
            validThroughText: "300"
        )

        let result = state.validate()

        guard case .success(let film) = result,
              case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected formula success, got \(result)")
        }
        XCTAssertEqual(rule.formula.coefficientSeconds, 1.10, accuracy: 0.0001)
        XCTAssertEqual(rule.formula.offsetSeconds, 0.05, accuracy: 0.0001)
    }

    func test_validate_emptyNotes_storesNoNotesEntry() {
        let state = makeValidState(notes: "   ")
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected success — \(state)")
        }
        XCTAssertEqual(film.profiles.first?.userMetadata?.notes, [])
    }

    // MARK: - Range validation

    func test_validate_emptyValidThrough_isUnlimitedNotAnError() {
        // An empty / "Unlimited" entry is the default state —
        // validation must succeed and the saved formula's
        // `sourceRangeThroughSeconds` must be `nil`.
        let state = makeValidState(validThroughText: "")
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected validation success for unlimited valid-through")
        }
        guard case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected trailing formula rule")
        }
        XCTAssertNil(rule.formula.sourceRangeThroughSeconds)
    }

    func test_validate_unlimitedKeyword_isUnlimitedNotAnError() {
        let state = makeValidState(validThroughText: "Unlimited")
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected validation success for Unlimited keyword")
        }
        guard case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected trailing formula rule")
        }
        XCTAssertNil(rule.formula.sourceRangeThroughSeconds)
    }

    func test_validate_validThroughBelowNoCorrection_reportsError() {
        let state = makeValidState(noCorrectionThroughText: "5", validThroughText: "3")
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(envelope.contains(.invalidValidThrough))
    }

    func test_validate_negativeOffset_rejectsShortenedExposure() {
        // T_c(1) = 1·1^1.3 + (-2) = -1, far short of T_m = 1 →
        // formula shortens.
        let state = makeValidState(
            exponentText: "1.30",
            offsetSecondsText: "-2",
            noCorrectionThroughText: "1",
            validThroughText: "100"
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(envelope.contains(.formulaShortensExposure))
    }

    func test_validate_baseTcBelowBoundary_rejectsShortenedExposure() {
        // T_c(1) = 0.5·1^1.3 + 0 = 0.5 < 1 → shortens.
        let state = makeValidState(
            exponentText: "1.30",
            baseTcText: "0.5",
            noCorrectionThroughText: "1",
            validThroughText: "100"
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(envelope.contains(.formulaShortensExposure))
    }

    func test_validate_lowExponentBelowBoundary_rejectsShortenedExposure() {
        // T_c(2) = 1·2^0.5 + 0 ≈ 1.414 < 2 → shortens.
        let state = makeValidState(
            exponentText: "0.5",
            noCorrectionThroughText: "2",
            validThroughText: "100"
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(envelope.contains(.formulaShortensExposure))
    }

    // MARK: - Field-level rejection

    func test_validate_emptyProfileName_isNotAnErrorAnymore() {
        // The editor does not surface a profile-name field; the
        // auto-generated `Manufacturer + Label + ISO` string
        // covers it.
        let state = makeValidState(profileName: "   ")
        XCTAssertNotNil({ () -> FilmIdentity? in
            if case .success(let film) = state.validate() { return film }
            return nil
        }(), "Save must succeed even when profileName is empty")
    }

    func test_validate_missingFilmLabel_reportsMissingError() {
        let state = makeValidState(filmLabel: "")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.missingFilmLabel))
    }

    func test_validate_nonNumericISO_reportsInvalidISO() {
        let state = makeValidState(isoText: "fast")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidISO))
    }

    func test_validate_zeroISO_reportsInvalidISO() {
        let state = makeValidState(isoText: "0")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidISO))
    }

    func test_validate_negativeISO_reportsInvalidISO() {
        let state = makeValidState(isoText: "-100")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidISO))
    }

    func test_validate_emptyExponent_reportsMissingFormulaExponent() {
        let state = makeValidState(exponentText: "  ")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.missingFormulaExponent))
    }

    func test_validate_zeroExponent_reportsInvalidFormulaExponent() {
        let state = makeValidState(exponentText: "0")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidFormulaExponent))
    }

    func test_validate_negativeExponent_reportsInvalidFormulaExponent() {
        let state = makeValidState(exponentText: "-1.31")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidFormulaExponent))
    }

    func test_validate_nonNumericExponent_reportsInvalidFormulaExponent() {
        let state = makeValidState(exponentText: "approx")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidFormulaExponent))
    }

    func test_validate_nonNumericBaseTc_reportsInvalidBaseTc() {
        let state = makeValidState(baseTcText: "approx")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidBaseTc))
    }

    func test_validate_nonNumericBaseTm_reportsInvalidBaseTm() {
        let state = makeValidState(baseTmText: "approx")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidBaseTm))
    }

    func test_validate_zeroBaseTm_reportsInvalidBaseTm() {
        let state = makeValidState(baseTmText: "0")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidBaseTm))
    }

    func test_validate_zeroBaseTc_reportsInvalidBaseTc() {
        let state = makeValidState(baseTcText: "0")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidBaseTc))
    }

    func test_validate_nonNumericOffset_reportsInvalidFormulaOffset() {
        let state = makeValidState(offsetSecondsText: "approx")
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertTrue(errors.contains(.invalidFormulaOffset))
    }

    func test_validate_collectsAllErrorsAtOnce() {
        let state = CustomFilmEditorFormState(
            profileName: "",
            filmLabel: "",
            isoText: "bad",
            sourceType: .userDefined,
            notes: "",
            exponentText: "bad",
            baseTcText: "bad",
            offsetSecondsText: "bad",
            noCorrectionThroughText: "bad",
            validThroughText: "bad"
        )
        guard case .failure(let errors) = state.validate() else {
            return XCTFail("Expected validation failure")
        }
        // `missingProfileName` is retired because the editor
        // auto-generates the profile name from
        // `Manufacturer + Label + ISO`. Everything else still
        // surfaces independently.
        let expected: Set<CustomFilmEditorValidationError> = [
            .missingFilmLabel,
            .invalidISO,
            .invalidFormulaExponent,
            .invalidBaseTc,
            .invalidFormulaOffset,
            .invalidNoCorrectionThrough,
            .invalidValidThrough,
        ]
        XCTAssertEqual(errors.errors, expected)
    }

    // MARK: - Helpers

    private func makeValidState(
        profileName: String = "Personal Provia",
        filmLabel: String = "My Provia 100F",
        isoText: String = "100",
        sourceType: CustomProfileSourceType = .personalTest,
        notes: String = "",
        exponentText: String = "1.30",
        baseTmText: String = "1",
        baseTcText: String = "1",
        offsetSecondsText: String = "",
        noCorrectionThroughText: String = "1",
        validThroughText: String = "240"
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
            validThroughText: validThroughText
        )
    }

    /// Deterministic id generator that returns `id-0`, `id-1`, …
    /// so a test can verify the generator is consulted twice (once
    /// for film id, once for profile id) without depending on UUID
    /// randomness.
    private final class IDCounter {
        private var counter = 0
        func next() -> String {
            defer { counter += 1 }
            return "id-\(counter)"
        }
    }
}
