import XCTest
import PTimerCore
@testable import PTimer

/// Covers the Basic / Scaled / Advanced editor input modes added
/// in the PTIMER-84 UX pass. Mode is a pure UI affordance over the
/// existing shared formula model; these tests pin the mapping +
/// reset rules and the round-trip through `from(film:)`.
final class CustomFilmEditorInputModeTests: XCTestCase {

    // MARK: - Mode inference on Edit prefill

    func test_inputMode_inferredAsBasic_forExponentOnlyProfile() {
        let film = makeCustomFilm(
            exponent: 1.30,
            baseTm: 1,
            baseTc: 1,
            offset: 0
        )
        let state = CustomFilmEditorFormState.from(film: film)
        XCTAssertEqual(state?.formulaInputMode, .basic)
    }

    func test_inputMode_inferredAsScaled_forAnchoredProfile() {
        // T-MAX 100 style anchored formula: Tc = 0.1 × (Tm/0.1)^1.0966
        let film = makeCustomFilm(
            exponent: 1.0966,
            baseTm: 0.1,
            baseTc: 0.1,
            offset: 0
        )
        let state = CustomFilmEditorFormState.from(film: film)
        XCTAssertEqual(state?.formulaInputMode, .scaled)
    }

    func test_inputMode_inferredAsAdvanced_whenOffsetNonZero() {
        let film = makeCustomFilm(
            exponent: 1.30,
            baseTm: 1,
            baseTc: 1,
            offset: 0.5
        )
        let state = CustomFilmEditorFormState.from(film: film)
        XCTAssertEqual(state?.formulaInputMode, .advanced)
    }

    // MARK: - Mode switching reset rules

    func test_switchingToBasic_resetsHiddenAdvancedFields() {
        let state = CustomFilmEditorFormState(
            formulaInputMode: .advanced,
            exponentText: "1.30",
            baseTmText: "0.1",
            baseTcText: "0.1",
            offsetSecondsText: "0.5"
        )
        let next = state.switching(to: .basic)
        XCTAssertEqual(next.formulaInputMode, .basic)
        XCTAssertEqual(next.baseTmText, "1")
        XCTAssertEqual(next.baseTcText, "1")
        XCTAssertEqual(next.offsetSecondsText, "")
        // Exponent must survive — it is the only field visible
        // across all three modes.
        XCTAssertEqual(next.exponentText, "1.30")
    }

    func test_switchingToScaled_resetsOnlyOffset() {
        let state = CustomFilmEditorFormState(
            formulaInputMode: .advanced,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            offsetSecondsText: "0.5"
        )
        let next = state.switching(to: .scaled)
        XCTAssertEqual(next.formulaInputMode, .scaled)
        // Anchors are preserved when going from Advanced -> Scaled
        XCTAssertEqual(next.baseTmText, "0.1")
        XCTAssertEqual(next.baseTcText, "0.1")
        XCTAssertEqual(next.offsetSecondsText, "")
    }

    func test_switchingToAdvanced_preservesEverything() {
        let state = CustomFilmEditorFormState(
            formulaInputMode: .scaled,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            offsetSecondsText: ""
        )
        let next = state.switching(to: .advanced)
        XCTAssertEqual(next.formulaInputMode, .advanced)
        XCTAssertEqual(next.baseTmText, "0.1")
        XCTAssertEqual(next.baseTcText, "0.1")
        XCTAssertEqual(next.offsetSecondsText, "")
    }

    // MARK: - T-MAX style Scaled formula round-trip

    func test_scaledMode_canRepresentTMaxFormula() throws {
        // T-MAX 100 published formula: Tc = 0.1 × (Tm/0.1)^1.0966
        let state = CustomFilmEditorFormState(
            filmLabel: "T-MAX 100",
            isoText: "100",
            formulaInputMode: .scaled,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1"
        )
        guard case .success(let film) = state.validate() else {
            return XCTFail("Validation should succeed for T-MAX style formula")
        }
        guard case .formula(let rule) = film.profiles.first?.rules.first else {
            return XCTFail("Expected formula rule")
        }
        XCTAssertEqual(rule.formula.coefficientSeconds, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.referenceMeteredTimeSeconds, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.exponent, 1.0966, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.offsetSeconds, 0, accuracy: 1e-9)
    }

    // MARK: - Helpers

    private func makeCustomFilm(
        exponent: Double,
        baseTm: Double,
        baseTc: Double,
        offset: Double
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(
            coefficientSeconds: baseTc,
            referenceMeteredTimeSeconds: baseTm,
            exponent: exponent,
            offsetSeconds: offset,
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
            userMetadata: UserEditableMetadata(customSourceType: .userDefined),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: "test-film",
            kind: .custom,
            canonicalStockName: "Test Film",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .userDefined)
        )
    }
}
