// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

final class FilmModeFormulaExtrapolationTests: XCTestCase {
    @MainActor
    func testTableProfileBelowOneSecondStaysTableDerivedNotUnsupported() throws {
        // PTIMER-168: at 0.5 s Tri-X 400 is now table-derived (the
        // no-correction band ends at 0.1 s), not no-correction. The
        // result is still quantified and not unsupported.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Table-derived")
        XCTAssertNotEqual(resultState.reciprocityState.badgeText, "Unsupported")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 0.812, accuracy: 0.01)
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 0.812, accuracy: 0.01)
    }

    @MainActor
    func testTableProfileAtOneSecondReturnsCorrectedExposureFromTablePrediction() throws {
        // PTIMER-168: Tri-X 400 evaluates through the official Kodak
        // table; the 1 sec published row (corrected 2 sec) is a table
        // anchor reproduced exactly, surfaced as a Table-derived badge.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Table-derived")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 2, accuracy: 1e-4)
        XCTAssertEqual(resultState.correctedExposure.primaryText, "2s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 2, accuracy: 1e-4)
    }

    @MainActor
    func testCorrectedExposureNumericDisplayUsesRestoredTimeFormatting() throws {
        // CHS 100 II's 2024 published rows top out at 15 sec, so 8 sec
        // is firmly inside its source table range. A source-backed
        // profile inside its source range does not prefix the numeric
        // corrected exposure with "≈" — that marker is reserved for
        // outside-guidance numeric continuations.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "CHS 100 II" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let correctedExposureSeconds = try XCTUnwrap(resultState.correctedExposure.correctedExposureSeconds)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 8, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(
            resultState.correctedExposure.primaryText,
            viewModel.formatReciprocityDuration(correctedExposureSeconds),
            "Numeric corrected exposure must round-trip through the same fine formatter the view-model exposes."
        )
    }

    @MainActor
    func testReciprocityDisplayFormattingUsesReadableUserFacingPrecision() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        viewModel.scaleMode = .fullStop

        XCTAssertEqual(viewModel.formatReciprocityDuration(0.033), "0.033s")
        XCTAssertEqual(viewModel.formatReciprocityDuration(0.25), "0.25s")
        XCTAssertEqual(viewModel.formatReciprocityDuration(5.41), "5.4s")
        XCTAssertEqual(viewModel.formatReciprocityDuration(10.541), "11s")
        XCTAssertEqual(viewModel.formatReciprocityDuration(64), "01:04")
        XCTAssertEqual(viewModel.formatReciprocityDuration(3_600), "01:00:00")
        XCTAssertEqual(viewModel.formatReciprocityDuration(522_484.861), "6d 01:08:05")
        XCTAssertEqual(viewModel.formatReciprocityAxisDuration(0.125), "0.1s")
        XCTAssertEqual(viewModel.formatReciprocityAxisDuration(32), "32s")
        XCTAssertEqual(viewModel.formatReciprocityAxisDuration(600), "10m")
        XCTAssertEqual(viewModel.formatReciprocityAxisDuration(21_600), "6h")
        XCTAssertEqual(viewModel.formatReciprocityAxisDuration(950_400), "11d")
    }

    @MainActor
    func testTopLevelCorrectedExposureCoarsensVeryLongDurationsIntoYears() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 28
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let corrected = resultState.correctedExposure

        XCTAssertEqual(corrected.kind, .quantified)
        XCTAssertNotNil(corrected.correctedExposureSeconds)
        // primaryText now uses month/year coarsening so the user
        // never reads a five-digit raw-day string. The 13,599-day
        // intermediate value coarsens to roughly 37 years.
        XCTAssertEqual(corrected.primaryText, "≈37y")
        // exact seconds remain available for timer use
        XCTAssertEqual(corrected.usesNumericExposure, true)
    }

    @MainActor
    func testReciprocityDisplayStateUsesReadableAdjustedAndCorrectedValues() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 5
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(resultState.correctedExposure.primaryText, "15s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.title, "Adjusted Shutter")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "4s")
        // Both values stay below one minute, so no seconds comparison
        // line is shown on the Detail card (PTIMER-172).
        XCTAssertNil(details.currentResult.adjustedShutter.detailText)
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "15s")
        XCTAssertNil(details.currentResult.correctedExposure.detailText)
    }

    /// PTIMER-172: the shared result-row duration policy pairs a clock
    /// primary with a whole-seconds secondary so a long exposure can be
    /// compared against manufacturer source rows; shorter values stay
    /// seconds-only. Used by both No Film and Film result rows.
    @MainActor
    func testResultDurationDisplayPairsClockPrimaryWithSecondsComparison() {
        let viewModel = makeFilmModeViewModel()

        // Minutes band: "01:40" + "100s".
        let minutesBand = viewModel.resultDurationDisplay(100)
        XCTAssertEqual(minutesBand.primary, "01:40")
        XCTAssertEqual(minutesBand.secondary, "100s")

        // Hours band: "02:29:43" + "8983s".
        let hoursBand = viewModel.resultDurationDisplay(8_983)
        XCTAssertEqual(hoursBand.primary, "02:29:43")
        XCTAssertEqual(hoursBand.secondary, "8983s")

        // Below one minute keeps the concise seconds-only primary.
        let shortValue = viewModel.resultDurationDisplay(27)
        XCTAssertEqual(shortValue.primary, "27s")
        XCTAssertEqual(shortValue.secondary, "")
    }

    @MainActor
    func testNoCorrectionDetailsUseSharedComparisonLayoutAndPlotIdentityCurrentPoint() throws {
        // PTIMER-168: Tri-X 400's no-correction band ends at 0.1 s; use
        // a sub-0.1 s base (snaps to 1/15 ≈ 0.067 s on the full-stop
        // scale) so the result is genuinely no-correction.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 0.05
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(details.summary.badgeText, "No correction")
        XCTAssertEqual(details.summary.summaryText, "No correction at 0.067s")
        // No-correction now shares the comparison layout with every
        // other case; the legacy `compactValue` variant is gone.
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "0.067s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "0.067s")
        XCTAssertEqual(details.currentResult.statusText, "No correction")
        // No-correction current point sits on the identity line with
        // the `.noCorrection` marker so it does not read as a formula
        // prediction.
        let currentPoint = try XCTUnwrap(details.graph?.currentPoint)
        XCTAssertEqual(currentPoint.style, .noCorrection)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 0.0667, accuracy: 1e-3)
        XCTAssertEqual(currentPoint.point.correctedExposureSeconds, 0.0667, accuracy: 1e-3)
    }

    @MainActor
    func testTableProfileSmallerSupportedExposureDoesNotRegressToUnsupported() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 30
        viewModel.ndStop = 4
        let largerQuantifiedResult = try XCTUnwrap(viewModel.filmModeExposureResultState)

        viewModel.baseShutter = 15
        viewModel.ndStop = 4
        let smallerQuantifiedResult = try XCTUnwrap(viewModel.filmModeExposureResultState)

        XCTAssertEqual(largerQuantifiedResult.correctedExposure.kind, .quantified)
        XCTAssertEqual(smallerQuantifiedResult.adjustedShutterSeconds, 256, accuracy: 0.0001)
        XCTAssertEqual(smallerQuantifiedResult.correctedExposure.kind, .quantified)
        XCTAssertNotNil(smallerQuantifiedResult.correctedExposure.correctedExposureSeconds)
    }

    @MainActor
    func testTableProfileBeyondSourceRangeKeepsTablePredictionAsQuantifiedResult() throws {
        // PTIMER-168: past the published table the Tri-X profile keeps a
        // log-log extrapolated value, surfaced as Beyond source range.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 15
        viewModel.ndStop = 6

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 1024, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Beyond source range")
        XCTAssertEqual(resultState.reciprocityState.tone, .unsupported)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertNotNil(resultState.correctedExposure.correctedExposureSeconds)
        // PTIMER-172: the ≈ 33,583 s (≈ 09:19:43) corrected exposure
        // sits in the clock band, so the Main card pairs the clock
        // primary with the matching whole-seconds value; the
        // outside-guidance marker carries onto the seconds value.
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "≈33583s")
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(bindingState.presentation.category, .unsupported)
        XCTAssertTrue(bindingState.profile.usesTableInterpolation)
    }

    @MainActor
    func testTableProfileVeryLongExposureStaysBeyondSourceRangeWithFormulaContinuation() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 15
        viewModel.ndStop = 10

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 16384, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Beyond source range")
        XCTAssertEqual(resultState.reciprocityState.tone, .unsupported)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertNotNil(resultState.correctedExposure.correctedExposureSeconds)
        // PTIMER-172: this corrected exposure exceeds one day, so the
        // primary coarsens to a "≈Nmo"/"≈Ny" bucket and no whole-seconds
        // comparison line is shown (a raw seconds count is not a useful
        // source-table comparison at that scale).
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .unsupportedOutOfPolicyRange)
    }

    @MainActor
    func testBarePowerLawProfileLongAdjustedExposureRemainsFormulaDerivedInsteadOfUnsupported() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 18

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 8_192, accuracy: 0.0001)
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .formulaDerived)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Formula-derived")
        XCTAssertEqual(resultState.reciprocityState.tone, .measured)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertNotNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeLimitedGuidanceResultKeepsCorrectedExposureRowStateWithoutNumericValue() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 15, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "No quantified prediction")
        XCTAssertEqual(resultState.reciprocityState.tone, .limitedGuidance)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 15, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposure.kind, .limitedGuidance)
        XCTAssertNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertNil(resultState.correctedExposureAction.targetSeconds)
        XCTAssertFalse(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(
            resultState.correctedExposureAction.accessibilityHint,
            "Timer unavailable because this corrected result is non-quantified"
        )
        XCTAssertEqual(resultState.correctedExposure.primaryText, "No corrected value")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "No official quantified prediction is available for this metered exposure.")
        XCTAssertFalse(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .limitedGuidanceNoQuantifiedPrediction)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeBeyondConvertedFormulaSourceRangeKeepsCorrectedExposureRowQuantifiedFromFormula() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        // 8 s × 4 ND stops = 128 s adjusted shutter — well above
        // Velvia 50's 32 s source-backed boundary (64 s is preserved
        // as a published "Not recommended" warning marker, never as
        // the source-range boundary). The result lands in the
        // beyond-source-range classification with a numeric formula
        // prediction (PTIMER-160).
        viewModel.baseShutter = 8
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        let expectedCorrected = pow(128.0, 1.1821)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 128, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Beyond source range")
        XCTAssertEqual(resultState.reciprocityState.tone, .unsupported)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 128, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(
            resultState.correctedExposure.correctedExposureSeconds ?? 0,
            expectedCorrected,
            accuracy: 1.0
        )
        XCTAssertEqual(
            resultState.correctedExposureAction.targetSeconds ?? 0,
            expectedCorrected,
            accuracy: 1.0
        )
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertTrue(resultState.correctedExposureAction.isOutsideManufacturerGuidance)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(
            resultState.correctedExposureAction.accessibilityHint,
            "Starts a timer using a formula prediction beyond the manufacturer source range"
        )
        XCTAssertTrue(
            resultState.correctedExposure.primaryText.hasPrefix("≈"),
            "Outside-guidance numeric values must be marked approximate; got: \(resultState.correctedExposure.primaryText)"
        )
        // PTIMER-172: the ≈ 310 s (≈ 05:10) corrected exposure is in
        // the clock band, so the Main card carries the matching
        // whole-seconds value, marked approximate like the primary.
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "≈310s")
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.presentation.category, .unsupported)
        XCTAssertTrue(bindingState.profile.isConvertedFormulaProfile)
        XCTAssertNotNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
    }
}
