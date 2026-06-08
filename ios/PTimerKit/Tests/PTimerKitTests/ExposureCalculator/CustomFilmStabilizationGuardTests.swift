import XCTest
import PTimerKit
import PTimerCore

/// Tc >= Tm across the usable range, not just at the
/// no-correction boundary. Covers validation, persistence
/// sanitation, and preview-row classification so an invalid
/// custom formula never sneaks into the calculator or timer
/// surfaces.
@MainActor
final class CustomFilmStabilizationGuardTests: XCTestCase {

    // MARK: - Usable-range guard

    func test_validate_unlimitedValidThrough_withSubUnitExponent_rejected() {
        // baseTm/baseTc=1, exp=0.5, offset=0, Unlimited:
        // Tc(1)=1 passes boundary, but Tc(4)=2 < 4 → reject.
        let state = makeValidState(
            exponentText: "0.5",
            validThroughText: ""
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Expected validation failure for sub-unit exponent with Unlimited")
        }
        XCTAssertTrue(envelope.contains(.formulaShortensExposure))
    }

    func test_validate_finiteValidThrough_subUnitExponent_rejectedAtUpper() {
        let state = makeValidState(
            exponentText: "0.5",
            noCorrectionThroughText: "1",
            validThroughText: "100"
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Sub-unit exponent shortens at the upper bound")
        }
        XCTAssertTrue(envelope.contains(.formulaShortensExposure))
    }

    func test_validate_exponentOne_unlimited_baseTcLessThanBaseTm_rejected() {
        // Tc = (0.5 / 1)·Tm + 0 = 0.5·Tm < Tm for all Tm.
        let state = makeValidState(
            exponentText: "1.0",
            baseTmText: "1",
            baseTcText: "0.5",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .failure(let envelope) = state.validate() else {
            return XCTFail("Tc = 0.5·Tm should be rejected")
        }
        XCTAssertTrue(envelope.contains(.formulaShortensExposure))
    }

    func test_validate_exponentAboveOne_unitAnchors_passes() {
        let state = makeValidState(
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .success = state.validate() else {
            return XCTFail("Standard power-law profile should pass")
        }
    }

    // MARK: - Sanitation aligned with validation

    func test_sanitation_dropsProfileWithSubUnitExponent_unlimited() throws {
        let film = try makeCustomFilm(
            id: "shortens",
            stockName: "Shortens",
            exponent: 0.5,
            anchors: AnchorPair(baseTm: 1, baseTc: 1),
            validThrough: nil // Unlimited
        )
        let library = CustomFilmLibrary(initial: [film])
        XCTAssertTrue(library.customFilms.isEmpty, "Sanitation must drop the shortening formula")
    }

    func test_sanitation_keepsValidAnchoredFormula() throws {
        let film = try makeCustomFilm(
            id: "tmax",
            stockName: "T-MAX 100",
            exponent: 1.0966,
            anchors: AnchorPair(baseTm: 0.1, baseTc: 0.1),
            validThrough: nil
        )
        let library = CustomFilmLibrary(initial: [film])
        XCTAssertEqual(library.customFilms.map(\.id), ["tmax"])
    }

    // MARK: - Preview row classification

    func test_previewRow_marksShorteningSampleAsInvalid() {
        // exp = 0.5 → Tc(8) ≈ 2.83 < 8. The Unlimited form will
        // fail validation, but the parser only checks per-field
        // shape, so the row presenter must still flag the
        // sample as `.invalidFormulaResult` instead of
        // `.formulaApplied`.
        let form = CustomFilmEditorFormState(
            exponentText: "0.5",
            baseTmText: "1",
            baseTcText: "1",
            noCorrectionThroughText: "1",
            validThroughText: "100"
        )
        let rows = CustomFilmEditorPreviewPresenter.rows(form: form, samples: [8])
        guard let eight = rows.first(where: { $0.meteredSeconds == 8 }) else {
            return XCTFail("Expected an 8s sample row")
        }
        XCTAssertEqual(eight.status, .invalidFormulaResult)
        XCTAssertNotNil(eight.correctedSeconds, "The presenter still reports the computed Tc so the UI can show what would have happened")
    }

    // MARK: - Helpers

    private func makeValidState(
        exponentText: String = "1.30",
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
            exponentText: exponentText,
            baseTmText: baseTmText,
            baseTcText: baseTcText,
            offsetSecondsText: offsetSecondsText,
            noCorrectionThroughText: noCorrectionThroughText,
            validThroughText: validThroughText,
            manufacturerText: "Custom"
        )
    }

    private struct AnchorPair { let baseTm: Double; let baseTc: Double }

    private func makeCustomFilm(
        id: String,
        stockName: String,
        exponent: Double,
        anchors: AnchorPair,
        validThrough: Double?
    ) throws -> FilmIdentity {
        let baseTm = anchors.baseTm
        let baseTc = anchors.baseTc
        // Anchors land directly on the formula. No separate
        // threshold rule and no metadata anchor side-channel.
        let formula = ReciprocityFormula(
            coefficientSeconds: baseTc,
            referenceMeteredTimeSeconds: baseTm,
            exponent: exponent,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: validThrough
        )
        let formulaRule = FormulaReciprocityRule(formula: formula)
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: stockName,
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(formulaRule)],
            notes: [],
            userMetadata: UserEditableMetadata(customSourceType: .userDefined),
            sourceEvidence: []
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
            userMetadata: UserEditableMetadata(customSourceType: .userDefined)
        )
    }
}
