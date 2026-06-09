import XCTest
import PTimerKit
import PTimerCore

/// Covers the manufacturer field, optional valid-through
/// (Unlimited), reference URL round-trip, and the
/// `from(film:)` extraction that prefills the editor on Edit.
/// The view itself is not tested here — only the form state
/// behaviour the SwiftUI surface binds to.
final class CustomFilmEditorUIPassTests: XCTestCase {

    func test_validate_composesCanonicalStockNameFromManufacturerAndLabel() throws {
        let state = CustomFilmEditorFormState(
            profileName: "Personal NB1",
            filmLabel: "NB1",
            isoText: "200",
            sourceType: .personalTest,
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "",
            manufacturerText: "Kodak"
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(film.canonicalStockName, "Kodak NB1")
        // The top-level manufacturer stays nil so the
        // picker keeps custom rows in the dedicated "Custom films"
        // section instead of merging them with preset
        // manufacturer groups.
        XCTAssertNil(film.manufacturer)
        XCTAssertEqual(film.userMetadata?.customManufacturer, "Kodak")
    }

    func test_validate_withoutManufacturer_usesLabelAsCanonicalName() throws {
        let state = CustomFilmEditorFormState(
            profileName: "GP3",
            filmLabel: "GP3",
            isoText: "100",
            sourceType: .userDefined,
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(film.canonicalStockName, "GP3")
        XCTAssertNil(film.userMetadata?.customManufacturer)
    }

    func test_validate_storesReferenceURL() throws {
        let state = CustomFilmEditorFormState(
            profileName: "URL-backed",
            filmLabel: "Stock",
            isoText: "100",
            sourceType: .communityReference,
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: "",
            manufacturerText: "Foma",
            referenceURLText: "https://example.com/article"
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(
            film.profiles.first?.userMetadata?.referenceURL,
            "https://example.com/article"
        )
        XCTAssertEqual(film.userMetadata?.referenceURL, "https://example.com/article")
    }

    func test_unlimitedValidThrough_savesFormulaWithoutMaximumSeconds() throws {
        let state = CustomFilmEditorFormState(
            profileName: "NoLimit",
            filmLabel: "NoLimit",
            isoText: "100",
            sourceType: .userDefined,
            exponentText: "1.30",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Expected success")
        }
        guard case .formula(let rule) = film.profiles.first?.rules.last else {
            return XCTFail("Expected trailing formula rule")
        }
        XCTAssertEqual(rule.formula.noCorrectionThroughSeconds, 1.0, accuracy: 0.0001)
        XCTAssertNil(rule.formula.sourceRangeThroughSeconds)
    }

    func test_fromFilm_splitsCanonicalStockNameOnManufacturerPrefix() throws {
        let formula = ReciprocityFormula(
            exponent: 1.30,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "p",
            name: "p-name",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(
                customSourceType: .personalTest,
                customManufacturer: "Kodak",
                referenceURL: "https://example.com"
            ),
            sourceEvidence: []
        )
        let film = FilmIdentity(
            id: "f",
            kind: .custom,
            canonicalStockName: "Kodak NB1",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 200,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customManufacturer: "Kodak")
        )

        let state = try XCTUnwrap(CustomFilmEditorFormState.from(film: film))
        XCTAssertEqual(state.manufacturerText, "Kodak")
        XCTAssertEqual(state.filmLabel, "NB1")
        XCTAssertEqual(state.referenceURLText, "https://example.com")
        // Unlimited valid-through round-trips as an empty text
        // field — the editor's placeholder reads "Unlimited".
        XCTAssertEqual(state.validThroughText, "")
    }
}
