import XCTest
@testable import PTimer

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

    func testFormulaDerivedBadgeReadsFormulaDerived() throws {
        // Provia 100F (converted formula) at 240 s — inside the
        // supported source range; presentation is `.formulaDerived`.
        let bindingState = try makeBindingState(stock: "Provia 100F", meteredSeconds: 240)
        XCTAssertEqual(presenter.badgeText(for: bindingState), "Formula-derived")
    }

    func testNoCorrectionBadgeReadsNoCorrection() throws {
        // HP5 Plus at 0.5 s sits inside the formula-only profile's
        // synthesized no-correction band — presentation is
        // `.noCorrection`.
        let bindingState = try makeBindingState(stock: "HP5 Plus", meteredSeconds: 0.5)
        XCTAssertEqual(presenter.badgeText(for: bindingState), "No correction")
    }

    func testConvertedFormulaUnsupportedBadgeReadsBeyondSourceRange() throws {
        // Provia 100F past the manufacturer-supported boundary (480 s).
        // Converted formula profiles label this state as
        // "Beyond source range" rather than "Outside guidance".
        let bindingState = try makeBindingState(stock: "Provia 100F", meteredSeconds: 1_800)
        XCTAssertEqual(presenter.badgeText(for: bindingState), "Beyond source range")
    }

    func testLimitedGuidanceBadgeReadsNoQuantifiedPrediction() throws {
        // Portra 400 published preset has no formula and lands on
        // `.limitedGuidance` past its threshold.
        let bindingState = try makeBindingState(stock: "Portra 400", meteredSeconds: 5)
        XCTAssertEqual(presenter.badgeText(for: bindingState), "No quantified prediction")
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

    func testFormulaSupportedSummaryReadsFormulaDerivedForConvertedProfile() throws {
        let bindingState = try makeBindingState(stock: "Provia 100F", meteredSeconds: 240)
        XCTAssertEqual(
            presenter.summaryText(
                for: bindingState,
                calculationResult: successCalc(at: 240),
                formatDurationCoarse: { "\($0)s" }
            ),
            "Formula-based correction on the active curve"
        )
    }

    func testUnsupportedSummaryReadsBeyondSourceRangeForConvertedProfile() throws {
        let bindingState = try makeBindingState(stock: "Provia 100F", meteredSeconds: 1_800)
        XCTAssertEqual(
            presenter.summaryText(
                for: bindingState,
                calculationResult: successCalc(at: 1_800),
                formatDurationCoarse: { "\($0)s" }
            ),
            "Beyond source range"
        )
    }

    func testLimitedGuidanceSummaryReadsBeyondPublishedNoCorrectionRange() throws {
        let bindingState = try makeBindingState(stock: "Portra 400", meteredSeconds: 5)
        XCTAssertEqual(
            presenter.summaryText(
                for: bindingState,
                calculationResult: successCalc(at: 5),
                formatDurationCoarse: { "\($0)s" }
            ),
            "Beyond published no-correction range"
        )
    }

    // MARK: - summaryDetailText

    func testUnofficialProfileSummaryDetailLeadsWithProfileNoteCaveat() throws {
        // Uses the Portra 400 unofficial practical formula profile —
        // the canonical unofficial-authority profile that is wired in
        // separately from the launch catalog. Its first profile note
        // is the authority caveat that vocabulary must surface in the
        // summary detail line.
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.id == "kodak-portra-400" },
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

    // MARK: - reciprocityStateDisplayState

    func testReciprocityStateDisplayStateAgreesWithBadgeAndTone() throws {
        let bindingState = try makeBindingState(stock: "Portra 400", meteredSeconds: 5)
        let displayState = presenter.reciprocityStateDisplayState(for: bindingState)
        XCTAssertEqual(displayState.badgeText, presenter.badgeText(for: bindingState))
        XCTAssertEqual(
            displayState.tone,
            presenter.tone(for: bindingState.presentation.badgeStyle)
        )
        XCTAssertTrue(displayState.showsInfoAffordance)
    }

    // MARK: - Helpers

    private func makeBindingState(
        stock: String,
        meteredSeconds: Double
    ) throws -> FilmModeReciprocityBindingState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
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
