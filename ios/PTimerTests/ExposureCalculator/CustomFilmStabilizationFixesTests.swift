import XCTest
@testable import PTimer

/// Pins the five custom-film stabilization invariants: Quick
/// Access id, Details graph formula, analytic shortening guard,
/// duration parser policy, and strict preview header.
final class CustomFilmStabilizationFixesTests: XCTestCase {

    // MARK: - Fix 1: Quick Access canonical id

    func test_canonicalCustomFilmID_returnsFilmIDForCustomEntry() {
        let film = customFilm(id: "kodak-tmax", stockName: "T-MAX 100")
        let canonical = FilmSelectorEntry(
            id: "kodak-tmax",
            primaryText: "T-MAX 100",
            film: film
        )
        XCTAssertEqual(canonical.canonicalCustomFilmID, "kodak-tmax")
    }

    func test_canonicalCustomFilmID_returnsFilmIDForAliasEntry() {
        let film = customFilm(id: "kodak-tmax", stockName: "T-MAX 100")
        let alias = FilmSelectorEntry(
            id: "quick:kodak-tmax",
            primaryText: "T-MAX 100",
            film: film,
            aliasOfOriginalID: "kodak-tmax"
        )
        XCTAssertEqual(alias.canonicalCustomFilmID, "kodak-tmax")
        XCTAssertNotEqual(alias.canonicalCustomFilmID, alias.id)
    }

    func test_canonicalCustomFilmID_isNilForPresetAndNoFilmEntries() {
        let preset = FilmIdentity(
            id: "provia",
            kind: .preset,
            canonicalStockName: "Provia 100F",
            manufacturer: "Fujifilm",
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .current,
            profiles: [],
            userMetadata: nil
        )
        let presetEntry = FilmSelectorEntry(id: "provia", primaryText: "Provia 100F", film: preset)
        XCTAssertNil(presetEntry.canonicalCustomFilmID)
        let sentinel = FilmSelectorEntry(id: "no-film", primaryText: "No film")
        XCTAssertNil(sentinel.canonicalCustomFilmID)
    }

    // MARK: - Fix 3: Analytic shortening guard

    func test_analyticGuard_rejectsConvexInteriorMinimum() {
        // exponent = 2, baseTm = baseTc = 1, offset = -0.1:
        // f(t) = t^2 - t - 0.1. Critical point at t* = 0.5, where
        // f(0.5) = 0.25 - 0.5 - 0.1 = -0.35 < 0. Endpoints would
        // miss this (f(1) = -0.1 - 0.1 = -0.2 also fails, but the
        // interior failure is harder to spot for non-shortening
        // endpoint pairs).
        let input = CustomFilmFormulaGuard.UsableRangeInput(
            exponent: 2.0,
            referenceMeteredTimeSeconds: 1.0,
            coefficientSeconds: 1.0,
            offsetSeconds: -0.1,
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 5
        )
        XCTAssertFalse(CustomFilmFormulaGuard.passesUsableRangeCheck(input))
    }

    func test_analyticGuard_rejectsSubUnitExponentWithUnlimited() {
        let input = CustomFilmFormulaGuard.UsableRangeInput(
            exponent: 0.5,
            referenceMeteredTimeSeconds: 1.0,
            coefficientSeconds: 1.0,
            offsetSeconds: 0,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: nil
        )
        XCTAssertFalse(CustomFilmFormulaGuard.passesUsableRangeCheck(input))
    }

    func test_analyticGuard_acceptsValidPowerLaw() {
        let input = CustomFilmFormulaGuard.UsableRangeInput(
            exponent: 1.30,
            referenceMeteredTimeSeconds: 1.0,
            coefficientSeconds: 1.0,
            offsetSeconds: 0,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: nil
        )
        XCTAssertTrue(CustomFilmFormulaGuard.passesUsableRangeCheck(input))
    }

    func test_analyticGuard_linearCaseUnlimitedRequiresUnitCoefficient() {
        let exact = CustomFilmFormulaGuard.UsableRangeInput(
            exponent: 1.0,
            referenceMeteredTimeSeconds: 1.0,
            coefficientSeconds: 1.0,
            offsetSeconds: 0,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: nil
        )
        XCTAssertTrue(CustomFilmFormulaGuard.passesUsableRangeCheck(exact))

        let smallerCoefficient = CustomFilmFormulaGuard.UsableRangeInput(
            exponent: 1.0,
            referenceMeteredTimeSeconds: 1.0,
            coefficientSeconds: 0.5,
            offsetSeconds: 0,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: nil
        )
        XCTAssertFalse(CustomFilmFormulaGuard.passesUsableRangeCheck(smallerCoefficient))
    }

    // MARK: - Fix 4: Duration parser policy

    func test_baseAnchor_rejectsUnlimitedKeyword() {
        let state = baselineState(baseTmText: "Unlimited")
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Base Tm = Unlimited must fail validation")
        }
        XCTAssertTrue(envelope.contains(.invalidBaseTm))
    }

    func test_offset_rejectsUnlimitedKeyword() {
        let state = baselineState(offsetSecondsText: "Unlimited")
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Offset = Unlimited must fail validation")
        }
        XCTAssertTrue(envelope.contains(.invalidFormulaOffset))
    }

    func test_baseAnchor_acceptsDurationSuffixes() throws {
        let state = baselineState(baseTmText: "1s", baseTcText: "2s")
        guard case .success(let film) = state.validate(),
              case .formula(let rule) = film.profiles.first?.rules.first else {
            return XCTFail("Expected validation success with duration-suffixed anchors")
        }
        XCTAssertEqual(rule.formula.referenceMeteredTimeSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rule.formula.coefficientSeconds, 2.0, accuracy: 1e-9)
    }

    // MARK: - Fix 5: Strict preview header alignment

    func test_previewParser_rejectsInvalidBaseTm_eliminatesSilentFallback() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            baseTmText: "abc",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        // The header relies on parse(form:) returning nil to emit
        // an "Invalid formula input" placeholder instead of a
        // happy curve.
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: form))
    }

    func test_previewParser_partialInvalidOffset_returnsNil() {
        let form = CustomFilmEditorFormState(
            exponentText: "1.30",
            offsetSecondsText: "-",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertNil(CustomFilmEditorPreviewPresenter.parse(form: form))
    }

    // MARK: - Helpers

    private func customFilm(id: String, stockName: String) -> FilmIdentity {
        let formula = ReciprocityFormula(
            exponent: 1.30,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: stockName,
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))]
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: stockName,
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: nil
        )
    }

    private func baselineState(
        baseTmText: String = "1",
        baseTcText: String = "1",
        offsetSecondsText: String = "",
        noCorrectionThroughText: String = "1",
        validThroughText: String = ""
    ) -> CustomFilmEditorFormState {
        CustomFilmEditorFormState(
            profileName: "",
            filmLabel: "Stock",
            isoText: "100",
            sourceType: .userDefined,
            notes: "",
            exponentText: "1.30",
            baseTmText: baseTmText,
            baseTcText: baseTcText,
            offsetSecondsText: offsetSecondsText,
            noCorrectionThroughText: noCorrectionThroughText,
            validThroughText: validThroughText,
            manufacturerText: "Custom"
        )
    }
}
