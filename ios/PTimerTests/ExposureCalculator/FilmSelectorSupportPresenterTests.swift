import XCTest
@testable import PTimer
import PTimerKit

/// Focused tests for `FilmSelectorSupportPresenter` — the pure value
/// transform that classifies a film / profile-override pair into a
/// selector-facing support state. Covers the four meaningful
/// states (`officialQuantifiedPrediction`,
/// `officialLimitedGuidance`, `noQuantifiedPrediction`,
/// `unofficialPractical`) using representative launch-catalog films
/// plus a synthesized profile so the rare "no quantified prediction
/// at all" state is exercised independent of catalog data.
final class FilmSelectorSupportPresenterTests: XCTestCase {
    private let catalog = LaunchPresetFilmCatalog.films

    // MARK: - No film sentinel and unclassifiable sources

    func testNoFilmMapsToNone() {
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: nil),
            .none,
            "The No film sentinel row must not carry an indicator."
        )
    }

    func testUserDefinedAuthorityMapsToCustomFormulaPrediction() {
        let userDefinedProfile = ReciprocityProfile(
            id: "user-defined-profile",
            name: "User defined",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                publisher: ""
            ),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.3,
                            noCorrectionThroughSeconds: 1
                        )
                    )
                ),
            ]
        )
        let film = syntheticFilm(profiles: [userDefinedProfile])

        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .userDefinedFormulaPrediction,
            "User-defined authority renders a visible 'Custom' badge."
        )
    }

    // MARK: - Official quantified prediction (formula-backed)

    func testProvia100FOfficialFormulaIsQuantifiedPrediction() throws {
        let film = try film(named: "Provia 100F")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialQuantifiedPrediction
        )
    }

    func testTriX400OfficialFormulaIsQuantifiedPrediction() throws {
        let film = try film(named: "Tri-X 400")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialQuantifiedPrediction
        )
    }

    func testFomapan100ClassicOfficialFormulaIsQuantifiedPrediction() throws {
        let film = try film(named: "Fomapan 100 Classic")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialQuantifiedPrediction
        )
    }

    func testHP5PlusOfficialFormulaIsQuantifiedPrediction() throws {
        let film = try film(named: "HP5 Plus")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialQuantifiedPrediction
        )
    }

    // MARK: - Official limited guidance

    func testPortra400OfficialIsLimitedGuidance() throws {
        let film = try film(named: "Portra 400")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialLimitedGuidance
        )
    }

    func testEktar100OfficialIsLimitedGuidance() throws {
        let film = try film(named: "Ektar 100")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialLimitedGuidance
        )
    }

    func testEktachromeE100OfficialIsLimitedGuidance() throws {
        let film = try film(named: "Ektachrome E100")
        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .officialLimitedGuidance
        )
    }

    // MARK: - No quantified prediction

    func testProfileWithOnlyThresholdMapsToNoQuantifiedPrediction() {
        let thresholdOnlyProfile = ReciprocityProfile(
            id: "threshold-only-profile",
            name: "Threshold-only official",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                publisher: "Test"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(
                            minimumSeconds: 0,
                            maximumSeconds: 1
                        )
                    )
                ),
            ]
        )
        let film = syntheticFilm(profiles: [thresholdOnlyProfile])

        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .noQuantifiedPrediction,
            "Official authority with neither formula nor limited-guidance rules maps to the disabled / prohibited indicator state."
        )
    }

    func testProfileWithNoRulesMapsToNoQuantifiedPrediction() {
        let emptyRulesProfile = ReciprocityProfile(
            id: "empty-rules-profile",
            name: "Empty official",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                publisher: "Test"
            ),
            rules: []
        )
        let film = syntheticFilm(profiles: [emptyRulesProfile])

        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(for: film),
            .noQuantifiedPrediction
        )
    }

    // MARK: - Unofficial practical

    func testPortra400UnofficialPracticalIsUnofficial() throws {
        let film = try film(named: "Portra 400")
        let unofficial = try XCTUnwrap(UnofficialPracticalProfiles.profile(forFilmID: film.id))

        XCTAssertEqual(
            FilmSelectorSupportPresenter.makeSupportState(
                for: film,
                profileOverride: unofficial
            ),
            .unofficialPractical
        )
    }

    func testUnofficialOverrideIsNotConflatedWithOfficialPrediction() throws {
        let film = try film(named: "Portra 400")
        let unofficial = try XCTUnwrap(UnofficialPracticalProfiles.profile(forFilmID: film.id))

        let officialState = FilmSelectorSupportPresenter.makeSupportState(for: film)
        let unofficialState = FilmSelectorSupportPresenter.makeSupportState(
            for: film,
            profileOverride: unofficial
        )

        XCTAssertEqual(officialState, .officialLimitedGuidance)
        XCTAssertEqual(unofficialState, .unofficialPractical)
        XCTAssertNotEqual(officialState, unofficialState)
        XCTAssertNotEqual(
            unofficialState,
            .officialQuantifiedPrediction,
            "The unofficial practical profile must never be classified as official quantified prediction."
        )
    }

    // MARK: - Distinct semantics and accessibility

    func testOfficialAndLimitedAndUnsupportedAndUnofficialMapToDistinctStates() {
        let states: Set<FilmSelectorSupportDisplayState> = [
            .officialQuantifiedPrediction,
            .officialLimitedGuidance,
            .noQuantifiedPrediction,
            .unofficialPractical,
        ]
        XCTAssertEqual(states.count, 4, "All four selector support states must be distinct values.")
    }

    func testEachOfficialStateHasItsOwnIcon() {
        let officialStates: [FilmSelectorSupportDisplayState] = [
            .officialQuantifiedPrediction,
            .officialLimitedGuidance,
            .noQuantifiedPrediction,
        ]
        let icons = officialStates.compactMap(\.iconSystemName)
        XCTAssertEqual(icons.count, officialStates.count, "Every official support state must publish an icon.")
        XCTAssertEqual(
            Set(icons).count,
            icons.count,
            "Official support states must use distinct SF Symbols so the row reads independent of color."
        )
    }

    func testUnofficialUsesVisibleTextBadgeNotIconOnly() {
        let state: FilmSelectorSupportDisplayState = .unofficialPractical
        XCTAssertNil(
            state.iconSystemName,
            "Unofficial must not collapse into icon-only — the row needs a visible 'Unofficial' badge."
        )
        XCTAssertEqual(state.unofficialBadgeText, "Unofficial")
    }

    func testUnofficialBadgeIsNeitherStarMarkerNorColorOnly() {
        let badge = FilmSelectorSupportDisplayState.unofficialPractical.unofficialBadgeText
        XCTAssertNotNil(badge)
        XCTAssertNotEqual(badge, "*", "The unofficial badge must not collapse to a '*' marker alone.")
        XCTAssertTrue(
            badge?.contains("Unofficial") ?? false,
            "The unofficial badge text must spell out 'Unofficial' so the meaning is readable without color."
        )
    }

    func testEachStateExposesDistinctAccessibilityLabel() {
        let states: [FilmSelectorSupportDisplayState] = [
            .officialQuantifiedPrediction,
            .officialLimitedGuidance,
            .noQuantifiedPrediction,
            .unofficialPractical,
        ]
        let labels = states.compactMap(\.accessibilityLabel)
        XCTAssertEqual(labels.count, states.count, "Every meaningful state must publish an accessibility label.")
        XCTAssertEqual(
            Set(labels).count,
            labels.count,
            "Accessibility labels must be distinct so VoiceOver users can tell the four support states apart."
        )

        XCTAssertEqual(
            FilmSelectorSupportDisplayState.officialQuantifiedPrediction.accessibilityLabel,
            "Official quantified prediction available"
        )
        XCTAssertEqual(
            FilmSelectorSupportDisplayState.officialLimitedGuidance.accessibilityLabel,
            "Official limited guidance only"
        )
        XCTAssertEqual(
            FilmSelectorSupportDisplayState.noQuantifiedPrediction.accessibilityLabel,
            "No quantified prediction available"
        )
        XCTAssertEqual(
            FilmSelectorSupportDisplayState.unofficialPractical.accessibilityLabel,
            "Unofficial practical estimate"
        )
    }

    func testNoneStateHasNoIndicatorOrLabel() {
        let state: FilmSelectorSupportDisplayState = .none
        XCTAssertNil(state.iconSystemName)
        XCTAssertNil(state.unofficialBadgeText)
        XCTAssertNil(state.accessibilityLabel)
    }

    // MARK: - Helpers

    private func film(named name: String) throws -> FilmIdentity {
        guard let film = catalog.first(where: { $0.canonicalStockName == name }) else {
            throw XCTSkip("Film '\(name)' is not present in the launch catalog; skipping.")
        }
        return film
    }

    private func syntheticFilm(profiles: [ReciprocityProfile]) -> FilmIdentity {
        FilmIdentity(
            id: "synthetic-film",
            kind: .preset,
            canonicalStockName: "Synthetic 100",
            manufacturer: "Synthetic",
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .current,
            profiles: profiles,
            userMetadata: nil
        )
    }
}
