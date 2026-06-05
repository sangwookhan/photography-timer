import XCTest
@testable import PTimer

/// Direct unit tests for `ReciprocityModel`. These cover the
/// reciprocity facade in isolation; `ExposureCalculatorViewModelTests`
/// covers the same behavior end-to-end through the view-model facade.
final class ReciprocityModelTests: XCTestCase {

    // MARK: - evaluate

    @MainActor
    func testEvaluateProducesNoCorrectionResultForThresholdInput() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        let result = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 0.5
        )

        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testEvaluateProducesFormulaDerivedResultForFormulaRangeInput() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        let result = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 100
        )

        XCTAssertEqual(result.metadata.basis, .formulaDerived)
        XCTAssertNotNil(result.correctedExposureSeconds)
    }

    // MARK: - makeDetailsDisplayState

    @MainActor
    func testMakeDetailsDisplayStateProducesNonNilForQuantifiedFormulaScenario() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()
        let film = FilmIdentity(
            id: "hp5-test",
            kind: .preset,
            canonicalStockName: "HP5 Plus",
            manufacturer: "Ilford Photo",
            brandLabel: "HP5 Plus",
            aliases: [],
            iso: 400,
            productionStatus: .current,
            profiles: [profile],
            userMetadata: nil
        )
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> =
            .success(
                ExposureCalculationResult(
                    baseShutterSeconds: 10,
                    stop: 0,
                    resultShutterSeconds: 10
                )
            )

        let displayState = model.makeDetailsDisplayState(
            input: FilmModeDetailsPresenterInput(
                bindingState: bindingState,
                calculationResult: calculationResult,
                filmModeExposureResultState: nil,
                formatDuration: { "\($0)s" },
                formatDurationCoarse: { "\($0)s" },
                formatAxisDuration: { "\($0)s" }
            )
        )

        XCTAssertNotNil(displayState)
        XCTAssertEqual(displayState?.title, "Reciprocity Details")
    }

    // MARK: - reciprocityStateDisplayState

    @MainActor
    func testReciprocityStateDisplayStateForFormulaDerivedScenario() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()
        let film = FilmIdentity(
            id: "hp5-test",
            kind: .preset,
            canonicalStockName: "HP5 Plus",
            manufacturer: "Ilford Photo",
            brandLabel: "HP5 Plus",
            aliases: [],
            iso: 400,
            productionStatus: .current,
            profiles: [profile],
            userMetadata: nil
        )
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        let displayState = model.reciprocityStateDisplayState(for: bindingState)

        XCTAssertEqual(displayState.tone, .measured)
        XCTAssertTrue(displayState.showsInfoAffordance)
    }

    // MARK: - delegation parity

    @MainActor
    func testEvaluateMatchesDirectEvaluatorForKnownScenario() {
        let model = ReciprocityModel()
        let directEvaluator = ReciprocityCalculationPolicyEvaluator()
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()

        let viaModel = model.evaluate(profile: profile, meteredExposureSeconds: 5)
        let viaDirect = directEvaluator.evaluate(profile: profile, meteredExposureSeconds: 5)

        // ReciprocityModel is a thin facade — both paths must agree.
        XCTAssertEqual(viaModel.metadata.basis, viaDirect.metadata.basis)
        XCTAssertEqual(
            viaModel.correctedExposureSeconds,
            viaDirect.correctedExposureSeconds
        )
    }

    // MARK: - duration formatting

    @MainActor
    func testFormatReciprocityDurationCoversSubsecondToMultiDayBands() {
        let model = ReciprocityModel()

        XCTAssertEqual(model.formatReciprocityDuration(0), "0s")
        XCTAssertEqual(model.formatReciprocityDuration(0.327), "0.327s")
        XCTAssertEqual(model.formatReciprocityDuration(2.13), "2.1s")
        XCTAssertEqual(model.formatReciprocityDuration(45), "45s")
        XCTAssertEqual(model.formatReciprocityDuration(125), "02:05")
        XCTAssertEqual(model.formatReciprocityDuration(3_725), "01:02:05")
        XCTAssertEqual(
            model.formatReciprocityDuration(90_000),
            "1d 01:00:00"
        )
        // Negative input clamps to 0 (the helper's contract).
        XCTAssertEqual(model.formatReciprocityDuration(-5), "0s")
    }

    @MainActor
    func testFormatReciprocityDurationCoarseCoarsensLargeValuesIntoMonthsAndYears() {
        let model = ReciprocityModel()

        // Below one day, falls through to formatReciprocityDuration.
        XCTAssertEqual(model.formatReciprocityDurationCoarse(45), "45s")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(3_725), "01:02:05")

        // 1 d–29 d → raw "Nd"
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400), "1d")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 29), "29d")

        // 30 d–364 d → "≈Nmo" or "≈Nmo Nd"
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 30), "≈1mo")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 65), "≈2mo 5d")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 278), "≈9mo 8d")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 360), "≈12mo")

        // 365 d+ → "≈Ny" with no raw-day tail
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 365), "≈1y")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 1_500), "≈4y")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 24_855), "≈68y")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 372_827), "≈1021y")
        XCTAssertEqual(model.formatReciprocityDurationCoarse(86_400 * 11_252_025), "≈30827y")
    }

    @MainActor
    func testFormatReciprocitySecondsComparisonReturnsNilBelowOneMinuteAndAboveOneDay() {
        let model = ReciprocityModel()

        // Below one minute the primary already reads as concise
        // seconds, so no secondary line is produced.
        XCTAssertNil(model.formatReciprocitySecondsComparison(0, approximate: false))
        XCTAssertNil(model.formatReciprocitySecondsComparison(3.3, approximate: false))
        XCTAssertNil(model.formatReciprocitySecondsComparison(27, approximate: false))
        // 59.6 s rounds to 60 s, where the clock primary first reads
        // "01:00"; the secondary appears at the same threshold.
        XCTAssertEqual(model.formatReciprocitySecondsComparison(59.6, approximate: false), "60s")
        // One day and above leaves clock notation for the coarse
        // Nd/≈Nmo/≈Ny buckets, where raw seconds are not useful.
        XCTAssertNil(model.formatReciprocitySecondsComparison(86_400, approximate: false))
        XCTAssertNil(model.formatReciprocitySecondsComparison(86_400, approximate: true))
        XCTAssertNil(model.formatReciprocitySecondsComparison(86_400 * 30, approximate: true))
    }

    @MainActor
    func testFormatReciprocitySecondsComparisonReturnsWholeSecondsInClockBand() {
        let model = ReciprocityModel()

        XCTAssertEqual(model.formatReciprocitySecondsComparison(60, approximate: false), "60s")
        // Minutes band (e.g. primary "24:40").
        XCTAssertEqual(model.formatReciprocitySecondsComparison(1_480, approximate: false), "1480s")
        // Hours band (e.g. primary "02:29:43").
        XCTAssertEqual(model.formatReciprocitySecondsComparison(8_983, approximate: false), "8983s")
        // Just below one day still reads as HH:MM:SS.
        XCTAssertEqual(model.formatReciprocitySecondsComparison(86_399, approximate: false), "86399s")
    }

    @MainActor
    func testFormatReciprocitySecondsComparisonCarriesApproximationMarker() {
        let model = ReciprocityModel()

        // An approximate primary (e.g. an outside-guidance "≈01:47:03")
        // marks its seconds value approximate too.
        XCTAssertEqual(model.formatReciprocitySecondsComparison(6_423, approximate: true), "≈6423s")
    }

    @MainActor
    func testFormatReciprocityAxisDurationUsesShortSuffixesAboveTwoMinutes() {
        let model = ReciprocityModel()

        XCTAssertEqual(model.formatReciprocityAxisDuration(0.5), "0.5s")
        XCTAssertEqual(model.formatReciprocityAxisDuration(45), "45s")
        // Below 120s remains seconds; at 120s switches to minutes.
        XCTAssertEqual(model.formatReciprocityAxisDuration(119), "119s")
        XCTAssertEqual(model.formatReciprocityAxisDuration(120), "2m")
        XCTAssertEqual(model.formatReciprocityAxisDuration(3_600), "1h")
        XCTAssertEqual(model.formatReciprocityAxisDuration(86_400), "1d")
    }

    // MARK: - Corrected-exposure display state

    @MainActor
    func testCorrectedExposureDisplayStateForNilBindingFallsToNoFilmSelected() {
        let model = ReciprocityModel()

        let state = model.correctedExposureDisplayState(for: nil)

        XCTAssertEqual(state.kind, .noFilmSelected)
        XCTAssertNil(state.correctedExposureSeconds)
        XCTAssertEqual(state.primaryText, "No film selected")
        XCTAssertFalse(state.usesNumericExposure)
    }

    @MainActor
    func testCorrectedExposureDisplayStateForQuantifiedFormulaBecomesNumeric() {
        let model = ReciprocityModel()
        let bindingState = makeFormulaBindingState(model: model, meteredExposureSeconds: 10)

        let state = model.correctedExposureDisplayState(for: bindingState)

        XCTAssertEqual(state.kind, .quantified)
        XCTAssertNotNil(state.correctedExposureSeconds)
        XCTAssertTrue(state.usesNumericExposure)
        XCTAssertFalse(state.primaryText.isEmpty)
    }

    @MainActor
    func testCorrectedExposureDisplayStateOmitsSecondsComparisonBelowOneMinute() throws {
        let model = ReciprocityModel()
        let bindingState = makeFormulaBindingState(model: model, meteredExposureSeconds: 10)

        let state = model.correctedExposureDisplayState(for: bindingState)

        let corrected = try XCTUnwrap(state.correctedExposureSeconds)
        XCTAssertLessThan(corrected, 60, "Scenario precondition: corrected value below one minute")
        // Below one minute the primary already reads as concise
        // seconds, so the Main card carries no secondary line.
        XCTAssertEqual(state.secondaryText, "")
    }

    @MainActor
    func testCorrectedExposureDisplayStateAddsSecondsComparisonInClockBand() throws {
        let model = ReciprocityModel()
        let bindingState = makeFormulaBindingState(model: model, meteredExposureSeconds: 30)

        let state = model.correctedExposureDisplayState(for: bindingState)

        let corrected = try XCTUnwrap(state.correctedExposureSeconds)
        XCTAssertGreaterThanOrEqual(corrected, 60, "Scenario precondition: corrected value in the clock band")
        XCTAssertLessThan(corrected, 86_400)
        XCTAssertTrue(state.usesNumericExposure)
        // PTIMER-172: clock-band primary carries a matching whole-seconds
        // secondary; the approximation marker tracks the primary.
        let rounded = Int(corrected.rounded())
        let expectedSecondary = state.primaryText.hasPrefix("≈") ? "≈\(rounded)s" : "\(rounded)s"
        XCTAssertEqual(state.secondaryText, expectedSecondary)
    }

    // MARK: - Corrected-exposure action state

    @MainActor
    func testCorrectedExposureActionStateForNilBindingDisablesTimer() {
        let model = ReciprocityModel()

        let action = model.correctedExposureActionState(for: nil)

        XCTAssertFalse(action.canStartTimer)
        XCTAssertNil(action.targetSeconds)
        XCTAssertEqual(
            action.accessibilityHint,
            "Timer unavailable because no film-specific corrected exposure is available"
        )
    }

    @MainActor
    func testCorrectedExposureActionStateForQuantifiedFormulaEnablesTimer() {
        let model = ReciprocityModel()
        let bindingState = makeFormulaBindingState(model: model, meteredExposureSeconds: 10)

        let action = model.correctedExposureActionState(for: bindingState)

        XCTAssertTrue(action.canStartTimer)
        XCTAssertEqual(action.targetSeconds ?? 0, pow(10.0, 1.31), accuracy: 0.001)
    }

    @MainActor
    private func makeFormulaBindingState(
        model: ReciprocityModel,
        meteredExposureSeconds: Double
    ) -> FilmModeReciprocityBindingState {
        let profile = ReciprocityPolicyScenarioFactory.hp5FormulaProfile()
        let film = FilmIdentity(
            id: "hp5-test",
            kind: .preset,
            canonicalStockName: "HP5 Plus",
            manufacturer: "Ilford Photo",
            brandLabel: "HP5 Plus",
            aliases: [],
            iso: 400,
            productionStatus: .current,
            profiles: [profile],
            userMetadata: nil
        )
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }
}
