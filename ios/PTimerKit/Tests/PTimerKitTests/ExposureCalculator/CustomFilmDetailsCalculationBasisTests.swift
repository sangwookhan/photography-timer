// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-84 polish: covers the Calculation Basis section the
/// Details presenter inserts between the reciprocity graph and the
/// custom-profile metadata. Scoped to user-defined-authority
/// profiles — preset / unofficial profiles keep their existing
/// in-graph formula header and do not gain a duplicate basis
/// section.
@MainActor
final class CustomFilmDetailsCalculationBasisTests: XCTestCase {

    // MARK: - Section presence + ordering

    func test_customFormulaProfile_addsCalculationBasisSection_aheadOfCustomProfileSection() throws {
        let input = makeInput(for: makeCustomFilm(
            exponent: 1.30,
            baseTm: 1,
            baseTc: 1,
            offset: 0
        ))
        let details = try XCTUnwrap(
            FilmModeDetailsPresenter().makeDetailsDisplayState(input: input)
        )
        let titles = details.sections.map(\.title)
        guard let basisIndex = titles.firstIndex(of: "Calculation basis"),
              let customIndex = titles.firstIndex(of: "Custom profile") else {
            return XCTFail("Both sections must be present: \(titles)")
        }
        XCTAssertLessThan(
            basisIndex,
            customIndex,
            "Calculation basis must render ahead of Custom profile metadata."
        )
    }

    func test_customFormulaProfile_calculationBasisSection_carriesFormulaExpressionRow() throws {
        let input = makeInput(for: makeCustomFilm(
            exponent: 1.0966,
            baseTm: 0.1,
            baseTc: 0.1,
            offset: 0
        ))
        let details = try XCTUnwrap(
            FilmModeDetailsPresenter().makeDetailsDisplayState(input: input)
        )
        let section = try XCTUnwrap(
            details.sections.first(where: { $0.title == "Calculation basis" })
        )
        XCTAssertEqual(section.rows.count, 1)
        let row = try XCTUnwrap(section.rows.first)
        XCTAssertEqual(row.style, .formulaExpression)
        XCTAssertEqual(row.value, "Tc = 0.1s × (Tm / 0.1s)^1.0966")
    }

    // MARK: - Graph header dedupe

    func test_customFormulaProfile_graphHeader_doesNotCarryFormulaText() throws {
        let input = makeInput(for: makeCustomFilm(
            exponent: 1.30,
            baseTm: 1,
            baseTc: 1,
            offset: 0
        ))
        let details = try XCTUnwrap(
            FilmModeDetailsPresenter().makeDetailsDisplayState(input: input)
        )
        XCTAssertNotNil(details.graph)
        XCTAssertNil(
            details.graph?.formulaDisplayText,
            "Custom-profile graph header must defer to the Calculation Basis section."
        )
    }

    // MARK: - Preset profile is unaffected

    func test_presetFormulaProfile_keepsGraphHeaderFormula_andHasNoBasisSection() throws {
        // HP5 Plus is a preset (official) formula profile — its
        // graph header still carries the formula text, and the
        // Details surface must not gain a duplicate Calculation
        // Basis section for it.
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" }
        )
        let input = makeInput(for: film, meteredSeconds: 30)
        let details = try XCTUnwrap(
            FilmModeDetailsPresenter().makeDetailsDisplayState(input: input)
        )
        XCTAssertNotNil(
            details.graph?.formulaDisplayText,
            "Preset profile must keep its in-graph formula header — the dedupe is scoped to the custom path."
        )
        XCTAssertFalse(
            details.sections.contains { $0.title == "Calculation basis" },
            "Preset profile must not gain the custom-path Calculation Basis section."
        )
    }

    // MARK: - Helpers

    private func makeCustomFilm(
        exponent: Double,
        baseTm: Double,
        baseTc: Double,
        offset: Double
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(
            formulaFamily: .modifiedSchwarzschild,
            coefficientSeconds: baseTc,
            referenceMeteredTimeSeconds: baseTm,
            exponent: exponent,
            offsetSeconds: offset,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "custom-profile",
            name: "Custom",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            userMetadata: UserEditableMetadata(customSourceType: .userDefined)
        )
        return FilmIdentity(
            id: "custom-film",
            kind: .custom,
            canonicalStockName: "Custom",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .userDefined)
        )
    }

    private func makeInput(
        for film: FilmIdentity,
        meteredSeconds: Double = 4
    ) -> FilmModeDetailsPresenterInput {
        let profile = film.profiles.first!
        let policyResult = ReciprocityCalculationPolicyEvaluator().evaluate(
            profile: profile,
            meteredExposureSeconds: meteredSeconds
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> = .success(
            ExposureCalculationResult(
                baseShutterSeconds: meteredSeconds,
                ndStep: NDStep(stops: 0),
                resultShutterSeconds: meteredSeconds
            )
        )
        return FilmModeDetailsPresenterInput(
            bindingState: bindingState,
            calculationResult: calculationResult,
            filmModeExposureResultState: nil,
            formatDuration: { "\($0)s" },
            formatDurationCoarse: { "\($0)s" },
            formatAxisDuration: { "\($0)s" }
        )
    }
}
