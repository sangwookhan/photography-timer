// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Locks the vocabulary surface produced by
/// `ReciprocityDetailsVocabularyPresenter` so the Film Details badge,
/// status, and summary copy cannot drift independently of the rest
/// of the presentation chain.
///
/// Hits each presentation category through real launch-catalog
/// profiles so the test exercises the same code path the app does
/// — there is no fake profile shape in this file.
@MainActor
final class ReciprocityVocabularyPresenterTests: XCTestCase {

    private let presenter = ReciprocityDetailsVocabularyPresenter()

    // MARK: - badgeText

    // Same contract — badge wording reflects the presentation state.
    // Film stock + metered seconds are case data (not test-name
    // structure); each case names the state it exercises and the
    // failure message carries the stock and metered input.
    func testBadgeTextReflectsPresentationState() throws {
        struct Case { let scenario: String; let stock: String; let metered: Double; let expected: String }
        let cases: [Case] = [
            Case(scenario: "formula-derived inside source range", stock: "Provia 100F", metered: 240, expected: "Formula-derived"),
            Case(scenario: "synthesized no-correction band", stock: "HP5 Plus", metered: 0.5, expected: "No correction"),
            Case(scenario: "converted formula beyond source range", stock: "Provia 100F", metered: 1_800, expected: "Beyond source range"),
            Case(scenario: "limited guidance past threshold", stock: "Portra 400", metered: 30, expected: "No quantified prediction"),
        ]
        for c in cases {
            let bindingState = try makeBindingState(stock: c.stock, meteredSeconds: c.metered)
            XCTAssertEqual(presenter.badgeText(for: bindingState), c.expected,
                           "\(c.scenario) [\(c.stock) @ \(c.metered)s]")
        }
    }

    // MARK: - statusText

    func testStatusTextEchoesBadgeForFormulaProfileEvenWhenGraphIsBeyondVisibleRange() throws {
        // Formula profiles must keep the calculation-anchored status
        // text. A viewport overflow does not silently relabel the
        // status — only non-formula (limited-guidance) profiles use
        // the visible-range overrides.
        let bindingState = try makeBindingState(stock: "Provia 100F", meteredSeconds: 240)
        let beyondVisibleGraph = makeStubGraph(isBeyond: true, isBelow: false)
        XCTAssertEqual(
            presenter.statusText(for: bindingState, graph: beyondVisibleGraph),
            "Formula-derived"
        )
    }

    // MARK: - summaryText

    // Same contract — summary wording reflects the presentation state.
    // Stock + metered seconds are case data; the scenario names the
    // state and the failure message carries the stock/metered input.
    func testSummaryTextReflectsPresentationState() throws {
        struct Case { let scenario: String; let stock: String; let metered: Double; let expected: String }
        let cases: [Case] = [
            Case(scenario: "formula-derived (converted profile)", stock: "Provia 100F", metered: 240, expected: "Formula-based correction on the active curve"),
            Case(scenario: "beyond source range (converted profile)", stock: "Provia 100F", metered: 1_800, expected: "Beyond source range"),
            Case(scenario: "limited guidance beyond no-correction range", stock: "Portra 400", metered: 30, expected: "Beyond published no-correction range"),
        ]
        for c in cases {
            let bindingState = try makeBindingState(stock: c.stock, meteredSeconds: c.metered)
            XCTAssertEqual(
                presenter.summaryText(
                    for: bindingState,
                    calculationResult: successCalc(at: c.metered),
                    formatDurationCoarse: { "\($0)s" }
                ),
                c.expected,
                "\(c.scenario) [\(c.stock) @ \(c.metered)s]"
            )
        }
    }

    // MARK: - summaryDetailText

    func testUnofficialProfileSummaryDetailLeadsWithProfileNoteCaveat() throws {
        // Uses the Portra 400 unofficial practical formula profile —
        // the canonical unofficial-authority profile that is wired in
        // separately from the launch catalog. Its first profile note
        // is the authority caveat that vocabulary must surface in the
        // summary detail line.
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalogV2.films.first { $0.id == "kodak-portra-400" },
            "Portra 400 must remain in the launch catalog."
        )
        let profile = try XCTUnwrap(
            UnofficialPracticalProfiles.profile(forFilmID: film.id),
            "Portra 400 must continue to expose an unofficial practical profile."
        )
        XCTAssertEqual(profile.source.authority, .unofficial)
        XCTAssertFalse(profile.notes.isEmpty, "Unofficial profile must carry at least one note.")

        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 5)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        let detailText = presenter.summaryDetailText(for: bindingState)
        XCTAssertEqual(
            detailText,
            profile.notes.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Unofficial-authority caveat must lead the summary detail line."
        )
    }

    func testFormulaSupportedSummaryDetailIsNil() throws {
        // Inside the supported curve, the summary detail field is
        // intentionally empty — the badge + summary already name the
        // state.
        let bindingState = try makeBindingState(stock: "HP5 Plus", meteredSeconds: 30)
        XCTAssertNil(presenter.summaryDetailText(for: bindingState))
    }

    func testOfficialTableBeyondSourceSummaryDetailKeepsPublishedOfficialCopy() throws {
        let bindingState = try makeBindingState(
            stock: "Fomapan 100 Classic",
            meteredSeconds: 120
        )
        let detailText = try XCTUnwrap(presenter.summaryDetailText(for: bindingState))

        XCTAssertEqual(
            detailText,
            "Current input is beyond the published source table. The corrected value is extrapolated past the official anchors."
        )
    }

    func testUnofficialTableBeyondSourceSummaryDetailDoesNotSayOfficial() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalogV2.films.first { $0.id == "foma-fomapan-100" }
        )
        let tableRule = TableInterpolationReciprocityRule(
            anchors: [
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
                TableAnchor(meteredSeconds: 10, correctedSeconds: 80),
                TableAnchor(meteredSeconds: 100, correctedSeconds: 1600),
            ],
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100
        )
        let profile = ReciprocityProfile(
            id: "community-table",
            name: "Community table",
            source: ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .medium,
                publisher: "Community"
            ),
            rules: [.tableInterpolation(tableRule)]
        )
        let policyResult = ReciprocityModel().evaluate(
            profile: profile,
            meteredExposureSeconds: 120
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let detailText = try XCTUnwrap(presenter.summaryDetailText(for: bindingState))

        XCTAssertTrue(detailText.contains("community table anchor"), detailText)
        XCTAssertFalse(detailText.localizedCaseInsensitiveContains("official"), detailText)
        XCTAssertFalse(detailText.localizedCaseInsensitiveContains("published"), detailText)
    }

    // MARK: - reciprocityStateDisplayState

    func testReciprocityStateDisplayStateAgreesWithBadgeAndTone() throws {
        let bindingState = try makeBindingState(stock: "Portra 400", meteredSeconds: 5)
        let displayState = presenter.reciprocityStateDisplayState(for: bindingState)
        XCTAssertEqual(displayState.badgeText, presenter.badgeText(for: bindingState))
        XCTAssertEqual(
            displayState.tone,
            presenter.tone(for: bindingState)
        )
        XCTAssertTrue(displayState.showsInfoAffordance)
    }

    // MARK: - userDefined wording / tone overrides

    func testUserDefinedFormulaBadgeReadsCustomFormula() {
        let bindingState = makeUserDefinedBindingState(meteredSeconds: 30)
        XCTAssertEqual(presenter.badgeText(for: bindingState), "Custom formula")
    }

    func testUserDefinedFormulaInRange_useMeasuredTone_notCaution() {
        // A custom user-defined formula in its normal calculation
        // range must not paint the badge orange — caution tone
        // belongs to actual confidence/status states like Beyond
        // source range. PTIMER-84 explicitly softens the tone for
        // this case to `.measured` (blue) so the photographer does
        // not read every custom profile as a warning.
        let bindingState = makeUserDefinedBindingState(meteredSeconds: 30)
        XCTAssertEqual(bindingState.presentation.category, .formulaDerived)
        XCTAssertEqual(presenter.tone(for: bindingState), .measured)
    }

    private func makeUserDefinedBindingState(meteredSeconds: Double) -> FilmModeReciprocityBindingState {
        let formula = ReciprocityFormula(
            exponent: 1.30,
            noCorrectionThroughSeconds: 1
        )
        let profile = ReciprocityProfile(
            id: "user-defined",
            name: "Custom profile",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))]
        )
        let film = FilmIdentity(
            id: "user-film",
            kind: .custom,
            canonicalStockName: "Test Custom",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: nil
        )
        let model = ReciprocityModel()
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredSeconds
        )
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    // MARK: - Tone reflects calculation state, not source authority

    /// PTIMER-164: the badge tone reflects the *calculation state*
    /// (no-correction / in-range / beyond-source), never the source
    /// authority. Across the three Fomapan 100 models (official FOMA
    /// table, Ohzart community, app-derived formula) plus an unofficial
    /// Portra profile — provenance is case data, not a per-film test — a
    /// successful or derived result never reads as caution.
    func testToneReflectsCalculationStateNotSourceAuthority() throws {
        struct ToneCase {
            let provenance: String
            let filmStock: String
            let makeProfile: () throws -> ReciprocityProfile
            let metered: Double
            let expectedCategory: ReciprocityConfidenceCategory?
            let expectedBadge: String
            let expectedTone: FilmModeReciprocityStateTone?
        }
        let officialFoma: () throws -> ReciprocityProfile = {
            try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first { $0.id == "foma-fomapan-100" }?.profiles.first)
        }
        let ohzart: () throws -> ReciprocityProfile = {
            try XCTUnwrap(AlternateReciprocityModels.alternates(forFilmID: "foma-fomapan-100").first { $0.id == "foma-fomapan-100-ohzart-community-table" })
        }
        let appFormula: () throws -> ReciprocityProfile = { AlternateReciprocityModels.fomapan100AppDerivedFormula }
        let portraUnofficial: () throws -> ReciprocityProfile = { UnofficialPracticalProfiles.kodakPortra400UnofficialPractical }

        let cases: [ToneCase] = [
            ToneCase(provenance: "official FOMA table — no correction", filmStock: "Fomapan 100 Classic", makeProfile: officialFoma, metered: 0.4, expectedCategory: .noCorrection, expectedBadge: "No correction", expectedTone: .trusted),
            ToneCase(provenance: "official FOMA table — in range", filmStock: "Fomapan 100 Classic", makeProfile: officialFoma, metered: 10, expectedCategory: nil, expectedBadge: "Table-derived", expectedTone: .measured),
            ToneCase(provenance: "Ohzart community — no correction", filmStock: "Fomapan 100 Classic", makeProfile: ohzart, metered: 0.4, expectedCategory: .noCorrection, expectedBadge: "No correction", expectedTone: .trusted),
            ToneCase(provenance: "Ohzart community — in range", filmStock: "Fomapan 100 Classic", makeProfile: ohzart, metered: 8, expectedCategory: .formulaDerived, expectedBadge: "Table-derived", expectedTone: .measured),
            ToneCase(provenance: "Ohzart community — beyond source", filmStock: "Fomapan 100 Classic", makeProfile: ohzart, metered: 120, expectedCategory: .unsupported, expectedBadge: "Beyond source range", expectedTone: .unsupported),
            ToneCase(provenance: "app-derived formula — in range", filmStock: "Fomapan 100 Classic", makeProfile: appFormula, metered: 10, expectedCategory: nil, expectedBadge: "Formula-derived", expectedTone: nil),
            ToneCase(provenance: "unofficial Portra — no correction", filmStock: "Portra 400", makeProfile: portraUnofficial, metered: 0.5, expectedCategory: .noCorrection, expectedBadge: "No correction", expectedTone: .trusted),
        ]
        for c in cases {
            let binding = try makeBindingState(filmStock: c.filmStock, profile: c.makeProfile(), meteredSeconds: c.metered)
            if let category = c.expectedCategory {
                XCTAssertEqual(binding.presentation.category, category, "\(c.provenance): category")
            }
            XCTAssertEqual(presenter.badgeText(for: binding), c.expectedBadge, "\(c.provenance): badge")
            if let tone = c.expectedTone {
                XCTAssertEqual(presenter.tone(for: binding), tone, "\(c.provenance): tone must reflect the calculation state, not authority")
            }
            XCTAssertNotEqual(presenter.tone(for: binding), .caution, "\(c.provenance): a successful/derived state must never read as caution")
        }
    }

    // MARK: - Helpers

    private func makeBindingState(
        filmStock: String,
        profile: ReciprocityProfile,
        meteredSeconds: Double
    ) throws -> FilmModeReciprocityBindingState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalogV2.films.first { $0.canonicalStockName == filmStock },
            "\(filmStock) must remain in the launch catalog."
        )
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: meteredSeconds)
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    private func makeBindingState(
        stock: String,
        meteredSeconds: Double
    ) throws -> FilmModeReciprocityBindingState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalogV2.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog."
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredSeconds
        )
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    private func successCalc(
        at seconds: Double
    ) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        .success(
            ExposureCalculationResult(
                baseShutterSeconds: seconds,
                stop: 0,
                resultShutterSeconds: seconds
            )
        )
    }

    private func makeStubGraph(
        isBeyond: Bool,
        isBelow: Bool
    ) -> FilmModeDetailsGraphDisplayState {
        FilmModeDetailsGraphDisplayState(
            kind: .formula,
            title: "Reciprocity Graph",
            sourcePoints: [],
            currentPoint: nil,
            currentMeteredExposureSeconds: nil,
            usesCurrentInputGuideOnly: false,
            caption: "",
            unsupportedExplanation: nil,
            xAxisLabel: "",
            yAxisLabel: "",
            xAxisTicks: [],
            yAxisTicks: [],
            supportedRangeUpperBoundSeconds: nil,
            unsupportedRegionStartSeconds: nil,
            isBeyondVisibleRange: isBeyond,
            isBelowVisibleRange: isBelow,
            xRange: 1...10,
            yRange: 1...10
        )
    }
}
