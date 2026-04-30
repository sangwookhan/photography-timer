import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelFilmModeTests: XCTestCase {
    @MainActor
    func testFilmRowDefaultsToNoFilmSelectorState() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertNil(viewModel.activeCalculatorContext.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
        XCTAssertFalse(viewModel.canShowFilmDetails)
    }

    @MainActor
    func testSelectingPresetFilmUpdatesActiveCalculatorContextAndDisplayState() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first)

        viewModel.selectPresetFilm(film)

        XCTAssertEqual(viewModel.activeCalculatorContext.selectedPresetFilm, film)
        XCTAssertTrue(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Tri-X 400")
        XCTAssertFalse(viewModel.filmSelectionDisplayState.primaryText.contains("ISO"))
        XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, "Official guidance")
    }

    @MainActor
    func testReplacingPresetFilmUpdatesActiveCalculatorContext() throws {
        let viewModel = makeViewModel()
        let firstFilm = try XCTUnwrap(viewModel.availablePresetFilms.first)
        let replacementFilm = try XCTUnwrap(viewModel.availablePresetFilms.dropFirst().first)

        viewModel.selectPresetFilm(firstFilm)
        viewModel.selectPresetFilm(replacementFilm)

        XCTAssertEqual(viewModel.activeCalculatorContext.selectedPresetFilm, replacementFilm)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Portra 400")
        XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, "Official guidance")
    }

    @MainActor
    func testFilmSelectorEntriesKeepISOAsSecondaryMetadata() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)
        XCTAssertEqual(viewModel.filmSelectorEntries.dropFirst().map(\.primaryText), [
            "Tri-X 400",
            "Portra 400",
            "Portra 400",
            "Velvia 50",
            "HP5 Plus"
        ])
        XCTAssertEqual(viewModel.filmSelectorEntries.dropFirst().map(\.secondaryText), [
            "ISO 400",
            "ISO 400",
            "Unofficial",
            "ISO 50",
            "ISO 400"
        ])
    }

    @MainActor
    func testChangingFromPresetFilmToNoFilmReturnsToDigitalWorkflow() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first)

        viewModel.selectPresetFilm(film)
        viewModel.clearSelectedPresetFilm()

        XCTAssertNil(viewModel.activeCalculatorContext.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertNil(viewModel.filmModeExposureResultState)
    }

    @MainActor
    func testSelectingPresetFilmActivatesFilmWorkflowAndReciprocityBinding() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1
        viewModel.ndStop = 0

        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)

        let film = try XCTUnwrap(viewModel.availablePresetFilms.last)
        viewModel.selectPresetFilm(film)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.film.id, film.id)
        XCTAssertEqual(bindingState.profile.source.kind, .manufacturerPublished)
        XCTAssertEqual(bindingState.profile.source.authority, .official)
        XCTAssertTrue(bindingState.policyResult.hasCalculatedExposureTime)
        XCTAssertTrue(bindingState.presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(viewModel.isFilmWorkflowActive)
    }

    @MainActor
    func testNoFilmBehavesAsDigitalWorkflow() throws {
        let viewModel = makeViewModel()

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertEqual(viewModel.calculationResult, .success(
            ExposureCalculationResult(
                baseShutterSeconds: 1.0 / 30.0,
                stop: 6,
                resultShutterSeconds: 2
            )
        ))
    }

    @MainActor
    func testFilmModeExposureResultStateShowsCorrectedExposureForQuantifiedPresetResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Exact")
        XCTAssertEqual(resultState.reciprocityState.tone, .trusted)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.adjustedShutterAction.accessibilityLabel, "Start timer from adjusted shutter")
        XCTAssertEqual(resultState.adjustedShutterAction.accessibilityHint, "Starts a timer using the ND-adjusted shutter value")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposureAction.targetSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityHint, "Starts a timer using the film-specific corrected exposure value")
        XCTAssertEqual(resultState.correctedExposure.primaryText, "1s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeDetailsEntryExistsViaReciprocityRowState() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canShowFilmDetails)
        XCTAssertTrue(viewModel.filmModeExposureResultState?.reciprocityState.showsInfoAffordance == true)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(details.title, "Reciprocity Details")
        XCTAssertEqual(details.summary.badgeText, "Estimated")
        XCTAssertEqual(details.summary.summaryText, "Estimated between 1s and 10s")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.title, "Adjusted Shutter")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "8s")
        XCTAssertNil(details.currentResult.adjustedShutter.detailText)
        XCTAssertEqual(details.currentResult.correctedExposure.title, "Corrected Exposure")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "34s")
        XCTAssertNil(details.currentResult.correctedExposure.detailText)
        XCTAssertTrue(details.currentResult.correctedExposure.emphasizesValue)
        XCTAssertEqual(details.sections.map(\.title), [
            "Profile",
            "Reference",
            "Sources"
        ])
        XCTAssertEqual(details.graph?.kind, .table)
        XCTAssertEqual(details.sections.first?.rows.map(\.title), ["Profile", "Authority"])
    }

    @MainActor
    func testFilmModeDetailsPrioritizeProfileAndReferenceBeforeSources() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let sourcesSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Sources" }))

        XCTAssertEqual(profileSection.rows.map(\.value), ["Reference table", "Official manufacturer guidance"])
        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.referenceBlock])
        XCTAssertEqual(referenceSection.rows.map(\.value), [
            """
            <= 1s    No correction
            1s       +0 stops
            10s      +2 stops         Dev -20%
            100s     +3 stops         Dev -30%
            """
        ])
        XCTAssertEqual(details.summary.summaryText, "Estimated between 1s and 10s")
        XCTAssertEqual(sourcesSection.rows.map(\.title), ["Reference", "Citation"])
        XCTAssertFalse(details.sections.flatMap(\.rows).map(\.title).contains("Basis"))
        XCTAssertFalse(details.sections.flatMap(\.rows).map(\.title).contains("Entry"))
        XCTAssertEqual(sourcesSection.rows.last?.destinationURL, nil)
        XCTAssertEqual(details.graph?.currentPoint?.style, .estimated)
        XCTAssertEqual(details.graph?.caption, "Adjusted shutter vs corrected exposure from reference anchors")
        XCTAssertEqual(details.graph?.title, "Reference Graph")
    }

    @MainActor
    func testFilmModeDetailsShowManufacturerNoDataForAdvisoryOnlyResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        XCTAssertEqual(details.sections.last?.title, "Sources")
        XCTAssertEqual(profileSection.rows.map(\.value), ["No quantified manufacturer data", "Official manufacturer guidance"])
        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.referenceBlock])
        XCTAssertEqual(referenceSection.rows.map(\.value), ["1/10000s-1s    No correction"])
        XCTAssertEqual(details.summary.badgeText, "No quantified correction")
        XCTAssertEqual(details.summary.summaryText, "Beyond published no-correction range")
        XCTAssertEqual(details.currentResult.layout, .compactPair)
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "15s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, resultState.correctedExposure.primaryText)
        XCTAssertEqual(details.currentResult.correctedExposure.detailText, resultState.correctedExposure.secondaryText)
        XCTAssertFalse(details.currentResult.correctedExposure.emphasizesValue)
    }

    @MainActor
    func testFilmModeDetailsIncludeThresholdInsideReferenceWhenOptionalValuesAreMissing() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            presetFilms: [minimalDetailsFilm()]
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let flattenedRows = details.sections.flatMap(\.rows)
        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.referenceBlock])
        XCTAssertEqual(referenceSection.rows.map(\.value), ["<= 1s    No correction"])
        XCTAssertFalse(flattenedRows.contains { $0.value.contains("See reciprocity guidance") })
        XCTAssertFalse(flattenedRows.map(\.title).contains("Basis"))
    }

    @MainActor
    func testFilmModeDetailsStateDoesNotRegressFilmModeTimerActions() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Exact")
        XCTAssertEqual(resultState.reciprocityState.tone, .trusted)
        XCTAssertEqual(details.sections.first?.title, "Profile")
        XCTAssertEqual(
            resultState.adjustedShutterAction.targetSeconds ?? 0,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            resultState.correctedExposureAction.targetSeconds ?? 0,
            1,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testFilmModeDetailsSourceRowsExposeLinkWhenUsableURLExists() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            presetFilms: [urlBackedDetailsFilm()]
        )

        viewModel.baseShutter = 2
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let sourcesSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Sources" }))

        XCTAssertEqual(
            sourcesSection.rows.first(where: { $0.title == "Citation" })?.destinationURL,
            URL(string: "https://example.com/reciprocity")
        )
    }

    @MainActor
    func testFilmModeDetailsShowFormulaInReferenceForFormulaProfile() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let formulaSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Formula" }))

        XCTAssertEqual(details.sections.map(\.title), ["Profile", "Formula", "Sources"])
        XCTAssertEqual(formulaSection.rows.map(\.title), [""])
        XCTAssertEqual(formulaSection.rows.map(\.style), [.formulaExpression])
        XCTAssertEqual(formulaSection.rows.map(\.value), ["Tc = Tm^1.31"])
        XCTAssertFalse(formulaSection.rows.contains { $0.value == "Tc = Tm^P" })
        let formulaProfileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        XCTAssertEqual(formulaProfileSection.rows.map(\.value), ["Formula-based guidance", "Official manufacturer guidance"])
        XCTAssertEqual(details.summary.badgeText, "Formula-based")
        XCTAssertEqual(details.summary.summaryText, "Formula-based correction on the active curve")
        XCTAssertEqual(details.graph?.kind, .formula)
        XCTAssertEqual(details.graph?.currentPoint?.style, .formulaDerived)
        XCTAssertEqual(details.graph?.caption, "Adjusted shutter vs corrected exposure on the active formula curve")
    }

    @MainActor
    func testFilmModeDetailsShowExponentFallbackWhenFormulaEquationIsUnavailable() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            presetFilms: [fallbackFormulaDetailsFilm()]
        )

        viewModel.baseShutter = 8
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let formulaSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Formula" }))

        XCTAssertEqual(formulaSection.rows.map(\.title), [""])
        XCTAssertEqual(formulaSection.rows.map(\.style), [.formulaExpression])
        XCTAssertEqual(formulaSection.rows.map(\.value), ["Tc = Tm^1.31"])
        XCTAssertEqual(details.graph?.kind, .formula)
        XCTAssertEqual(details.graph?.currentPoint?.style, .formulaDerived)
    }

    @MainActor
    func testFilmModeDetailsGraphShowsTableAnchorsAndCurrentPointForQuantifiedTableResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 5
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertEqual(graph.kind, .table)
        XCTAssertEqual(graph.sourcePoints.count, 3)
        XCTAssertEqual(graph.sourcePoints[0].meteredExposureSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(graph.sourcePoints[1].meteredExposureSeconds, 10, accuracy: 0.0001)
        XCTAssertEqual(graph.sourcePoints[2].meteredExposureSeconds, 100, accuracy: 0.0001)
        XCTAssertEqual(graph.currentPoint?.style, .estimated)
        XCTAssertEqual(graph.currentPoint?.point.meteredExposureSeconds ?? 0, 4, accuracy: 0.0001)
        XCTAssertEqual(graph.currentPoint?.point.correctedExposureSeconds ?? 0, 10.5410012802, accuracy: 0.0001)
        XCTAssertEqual(graph.caption, "Adjusted shutter vs corrected exposure from reference anchors")
        XCTAssertFalse(graph.usesCurrentInputGuideOnly)
        XCTAssertNil(graph.unsupportedRegionStartSeconds)
        XCTAssertEqual(graph.xAxisTicks.map(\.label), ["1s", "10s", "100s"])
    }

    @MainActor
    func testFilmModeDetailsGraphShowsExtrapolatedCurrentPointForExtendedTableResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 6
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertEqual(graph.kind, .table)
        XCTAssertEqual(graph.currentPoint?.style, .extrapolated)
        XCTAssertEqual(graph.currentPoint?.point.meteredExposureSeconds ?? 0, 1_024, accuracy: 0.0001)
        XCTAssertNotNil(graph.currentPoint?.point.correctedExposureSeconds)
        XCTAssertEqual(graph.supportedRangeUpperBoundSeconds ?? 0, 100, accuracy: 0.0001)
    }

    @MainActor
    func testFilmModeDetailsFormulaGraphUsesFormulaSpecificCurrentPointSemantics() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertEqual(graph.kind, .formula)
        XCTAssertEqual(graph.currentPoint?.style, .formulaDerived)
        XCTAssertEqual(graph.caption, "Adjusted shutter vs corrected exposure on the active formula curve")
        XCTAssertFalse(graph.usesCurrentInputGuideOnly)
    }

    @MainActor
    func testFilmModeDetailsGraphOmitsCurrentPlotForAdvisoryOnlyResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertNil(details.graph)
        XCTAssertEqual(details.sections.first(where: { $0.title == "Reference" })?.rows.first?.value, "1/10000s-1s    No correction")
    }

    @MainActor
    func testFilmModeDetailsGraphShowsReferenceRangeAndXOnlyMarkerForUnsupportedResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertEqual(details.summary.badgeText, "Unsupported")
        XCTAssertEqual(details.summary.summaryText, "Outside supported reciprocity range")
        XCTAssertEqual(details.summary.detailText, "Current input is outside the supported range and no quantified corrected point is available.")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "01:04")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, resultState.correctedExposure.primaryText)
        XCTAssertEqual(details.currentResult.correctedExposure.detailText, resultState.correctedExposure.secondaryText)
        XCTAssertFalse(details.currentResult.correctedExposure.emphasizesValue)
        XCTAssertTrue(graph.usesCurrentInputGuideOnly)
        XCTAssertNil(graph.currentPoint)
        XCTAssertEqual(graph.currentMeteredExposureSeconds ?? 0, 64, accuracy: 0.0001)
        XCTAssertNotNil(graph.supportedRangeUpperBoundSeconds)
        XCTAssertNotNil(graph.unsupportedRegionStartSeconds)
        XCTAssertEqual(graph.unsupportedExplanation, "Current input is outside the supported range. No quantified corrected point is available.")
    }

    @MainActor
    func testFilmModeDetailsSummaryPromotesCurrentStateAboveSections() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 6
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(details.summary.badgeText, "Extrapolated")
        XCTAssertEqual(details.summary.summaryText, "Extrapolated beyond 10s reference data")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "17:04")
        XCTAssertNotEqual(details.currentResult.correctedExposure.valueText, "No quantified correction")
        XCTAssertEqual(details.sections.map(\.title), ["Profile", "Reference", "Sources"])
    }

    @MainActor
    func testFilmModeDetailsGraphOmitsGraphWhenNoGraphableReferenceDataExists() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            presetFilms: [minimalDetailsFilm()]
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertNil(details.graph)
        XCTAssertEqual(details.sections.first(where: { $0.title == "Reference" })?.rows.first?.value, "<= 1s    No correction")
    }

    @MainActor
    func testFilmModeDetailsUnofficialPortra400ShowsUnofficialAuthorityAndFormula() throws {
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" },
            "Unofficial Portra 400 selector entry must exist."
        )

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let formulaSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Formula" }))

        XCTAssertEqual(profileSection.rows.map(\.title), ["Profile", "Authority"])
        XCTAssertEqual(profileSection.rows.map(\.value), ["Formula-based guidance", "Unofficial practical approximation"])
        XCTAssertEqual(formulaSection.rows.map(\.value), ["Tc = Tm^1.34"])
        XCTAssertEqual(details.summary.badgeText, "Formula-based")
        XCTAssertNil(details.sections.first(where: { $0.title == "Sources" }),
                     "Unofficial profile with no verified source metadata must not show Sources section.")
    }

    @MainActor
    func testFilmModeDetailsOfficialPortra400ShowsOfficialAuthorityInProfileSection() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let authorityRow = try XCTUnwrap(profileSection.rows.first(where: { $0.title == "Authority" }))

        XCTAssertEqual(authorityRow.value, "Official manufacturer guidance")
        XCTAssertFalse(profileSection.rows.map(\.value).contains("Unofficial practical approximation"))
    }

    @MainActor
    func testFilmSelectionDisplayStateOfficialPortra400ShowsOfficialGuidanceLabel() {
        let viewModel = makeViewModel()
        let film = viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" }!
        viewModel.selectPresetFilm(film)

        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Portra 400")
        XCTAssertEqual(
            viewModel.filmSelectionDisplayState.secondaryText,
            "Official guidance",
            "Official Portra 400 must show an explicit 'Official guidance' label on the main row."
        )
    }

    @MainActor
    func testFilmSelectionDisplayStateUnofficialPortra400ShowsUnofficialPracticalLabel() throws {
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )
        viewModel.selectEntry(unofficialEntry)

        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Portra 400")
        XCTAssertEqual(
            viewModel.filmSelectionDisplayState.secondaryText,
            "Unofficial practical",
            "Unofficial Portra 400 must show a clear profile qualifier on the main film row."
        )
    }

    @MainActor
    func testFilmSelectionDisplayStateOfficialAndUnofficialPortra400AreDistinguishable() throws {
        let viewModel = makeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.selectPresetFilm(officialFilm)
        let officialDisplay = viewModel.filmSelectionDisplayState

        viewModel.selectEntry(unofficialEntry)
        let unofficialDisplay = viewModel.filmSelectionDisplayState

        XCTAssertEqual(officialDisplay.primaryText, unofficialDisplay.primaryText,
                       "Primary film name should be identical for official and unofficial Portra 400.")
        XCTAssertNotEqual(
            officialDisplay.secondaryText,
            unofficialDisplay.secondaryText,
            "Official and unofficial Portra 400 must produce different secondary labels so the user can distinguish them."
        )
        XCTAssertEqual(officialDisplay.secondaryText, "Official guidance")
        XCTAssertEqual(unofficialDisplay.secondaryText, "Unofficial practical")
    }

    @MainActor
    func testFilmModeDetailsUnofficialPortra400HasFormulaAndProfileSectionsPresent() throws {
        // Verifies that both Profile and Formula sections exist in the sections array —
        // the view renders non-Sources sections before the graph, so this guarantees
        // Formula appears before Graph in the rendered UI.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let formulaSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Formula" }))
        XCTAssertNotNil(details.graph, "Formula profile must produce a graph.")
        XCTAssertEqual(formulaSection.rows.map(\.value), ["Tc = Tm^1.34"])
        XCTAssertEqual(
            profileSection.rows.first(where: { $0.title == "Authority" })?.value,
            "Unofficial practical approximation"
        )
        XCTAssertNil(details.sections.first(where: { $0.title == "Sources" }),
                     "Unofficial profile with no verified source must not show Sources section.")
    }

    @MainActor
    func testFormulaGraphSourcePointsCoverCanonicalRangeRegardlessOfCurrentInput() throws {
        // With a short current input, the graph should still plot source points up to
        // the canonical 120s upper bound so the graph feels stable, not auto-scaled.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 2      // short input — well below canonical 120s
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        // Source points must span beyond the current input toward the canonical bound
        let maxSourceMetered = graph.sourcePoints.map(\.meteredExposureSeconds).max() ?? 0
        XCTAssertGreaterThan(
            maxSourceMetered,
            30,
            "Formula graph source points must extend well beyond the current input to provide a stable reference range."
        )
    }

    @MainActor
    func testFilmRowOfficialGuidanceLabelAppliesToAllOfficialPresetFilms() {
        // Every preset film with authority=official must show "Official guidance" on the main row.
        // This ensures the label is consistent across all catalog films, not only Portra 400.
        let viewModel = makeViewModel()
        for film in viewModel.availablePresetFilms {
            viewModel.selectPresetFilm(film)
            XCTAssertEqual(
                viewModel.filmSelectionDisplayState.secondaryText,
                "Official guidance",
                "\(film.canonicalStockName) has authority=official and must show 'Official guidance'."
            )
        }
    }

    @MainActor
    func testFilmRowLabelClearedWhenNoFilmSelected() {
        let viewModel = makeViewModel()
        XCTAssertNil(
            viewModel.filmSelectionDisplayState.secondaryText,
            "No-film state must not show a profile qualifier."
        )
    }

    @MainActor
    func testFilmModeDetailsDisplayStateIsNonNilForOfficialAndUnofficialPortra400() throws {
        // Both official and unofficial Portra 400 must produce a non-nil details display state
        // so the sheet can open for either profile.
        let viewModel = makeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 15
        viewModel.ndStop = 0

        viewModel.selectPresetFilm(officialFilm)
        XCTAssertNotNil(
            viewModel.filmModeDetailsDisplayState,
            "Official Portra 400 must produce a film details display state."
        )

        viewModel.selectEntry(unofficialEntry)
        XCTAssertNotNil(
            viewModel.filmModeDetailsDisplayState,
            "Unofficial Portra 400 must produce a film details display state."
        )
    }

    @MainActor
    func testFilmModeDetailsSectionOrderIsConsistentAcrossOfficialAndUnofficialPortra400() throws {
        // For both profiles, all non-Sources sections must precede any Sources section.
        // The view renders: non-Sources → graph → Sources. This test ensures no section
        // ordering regression in the underlying display state.
        let viewModel = makeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 15
        viewModel.ndStop = 0

        for label in ["official", "unofficial"] {
            if label == "official" {
                viewModel.selectPresetFilm(officialFilm)
            } else {
                viewModel.selectEntry(unofficialEntry)
            }

            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
            let sourcesIndex = details.sections.firstIndex(where: { $0.title == "Sources" })
            let profileIndex = details.sections.firstIndex(where: { $0.title == "Profile" })

            // If a Sources section exists it must come after Profile
            if let si = sourcesIndex, let pi = profileIndex {
                XCTAssertGreaterThan(si, pi, "[\(label)] Sources must appear after Profile in sections array.")
            }
            // Profile must exist
            XCTAssertNotNil(profileIndex, "[\(label)] Profile section must be present in details sections.")
        }
    }

    @MainActor
    func testFilmModeReciprocityStateVisiblyDistinguishesExactEstimatedAndExtrapolated() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        let exactState = try XCTUnwrap(viewModel.filmModeExposureResultState)

        viewModel.baseShutter = 5
        viewModel.ndStop = 0
        let estimatedState = try XCTUnwrap(viewModel.filmModeExposureResultState)

        viewModel.baseShutter = 15
        viewModel.ndStop = 4
        let extrapolatedState = try XCTUnwrap(viewModel.filmModeExposureResultState)

        XCTAssertEqual(exactState.reciprocityState.badgeText, "Exact")
        XCTAssertEqual(exactState.reciprocityState.tone, .trusted)
        XCTAssertEqual(estimatedState.reciprocityState.badgeText, "Estimated")
        XCTAssertEqual(estimatedState.reciprocityState.tone, .measured)
        XCTAssertEqual(extrapolatedState.reciprocityState.badgeText, "Extrapolated")
        XCTAssertEqual(extrapolatedState.reciprocityState.tone, .caution)
    }

    @MainActor
    func testTriXBelowOneSecondDoesNotShowUnsupported() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "No correction")
        XCTAssertNotEqual(resultState.reciprocityState.badgeText, "Unsupported")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testTriXAtOneSecondReturnsCorrectedExposureEqualToAdjustedShutter() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Exact")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposure.primaryText, "1s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 1, accuracy: 0.0001)
    }

    @MainActor
    func testCorrectedExposureNumericDisplayUsesRestoredTimeFormatting() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 30
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let correctedExposureSeconds = try XCTUnwrap(resultState.correctedExposure.correctedExposureSeconds)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 512, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(
            resultState.correctedExposure.primaryText,
            viewModel.formatReciprocityDuration(correctedExposureSeconds)
        )
        XCTAssertEqual(resultState.correctedExposure.primaryText, "03:10:32")
    }

    @MainActor
    func testReciprocityDisplayFormattingUsesReadableUserFacingPrecision() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

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
    func testTopLevelCorrectedExposureUsesCoarseDayDisplayForVeryLongDurations() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 28
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let corrected = resultState.correctedExposure

        XCTAssertEqual(corrected.kind, .quantified)
        XCTAssertNotNil(corrected.correctedExposureSeconds)
        // primaryText must be coarse day-only (no hour/min/sec noise)
        XCTAssertEqual(corrected.primaryText, "13,599d")
        // exact seconds remain available for timer use
        XCTAssertEqual(corrected.usesNumericExposure, true)
    }

    @MainActor
    func testReciprocityDisplayStateUsesReadableAdjustedAndCorrectedValues() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 5
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(resultState.correctedExposure.primaryText, "11s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.title, "Adjusted Shutter")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "4s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "11s")
    }

    @MainActor
    func testNoCorrectionDetailsUseCompactSummaryAndDoNotPlotCurrentPoint() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(details.summary.badgeText, "No correction")
        XCTAssertEqual(details.summary.summaryText, "No correction at 0.5s")
        XCTAssertEqual(details.currentResult.layout, .compactValue)
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "0.5s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "0.5s")
        XCTAssertNil(details.graph?.currentPoint)
    }

    @MainActor
    func testTriXSmallerSupportedExposureDoesNotRegressToUnsupported() throws {
        let viewModel = makeViewModel()
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
    func testTriXExtendedPolicyRangeStillShowsExtrapolatedQuantifiedResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 15
        viewModel.ndStop = 6

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 1024, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Extrapolated")
        XCTAssertEqual(resultState.reciprocityState.tone, .caution)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertNotNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(
            resultState.reciprocityState.infoText,
            "Low-confidence result extrapolated from the original representative table rows."
        )
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(bindingState.policyResult.metadata.rangeStatus, .beyondLastRepresentativePoint)
        XCTAssertEqual(bindingState.presentation.category, .extrapolated)
    }

    @MainActor
    func testTriXVeryLongExposureRemainsExtrapolatedWithoutGenericUpperBoundary() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 15
        viewModel.ndStop = 10

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 16384, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Extrapolated")
        XCTAssertEqual(resultState.reciprocityState.tone, .caution)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertNotNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .extrapolatedBeyondTable)
        XCTAssertEqual(bindingState.policyResult.metadata.rangeStatus, .beyondLastRepresentativePoint)
    }

    @MainActor
    func testHP5PlusLongAdjustedExposureRemainsFormulaDerivedInsteadOfUnsupported() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.selectPresetFilm(film)
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 18

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)

        XCTAssertEqual(resultState.adjustedShutterSeconds, 8_192, accuracy: 0.0001)
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .formulaDerived)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Formula-based")
        XCTAssertEqual(resultState.reciprocityState.tone, .measured)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertNotNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeAdvisoryOnlyResultKeepsCorrectedExposureRowStateWithoutNumericValue() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 15, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "No quantified correction")
        XCTAssertEqual(resultState.reciprocityState.tone, .advisory)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 15, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposure.kind, .advisory)
        XCTAssertNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertNil(resultState.correctedExposureAction.targetSeconds)
        XCTAssertFalse(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(
            resultState.correctedExposureAction.accessibilityHint,
            "Timer unavailable because this corrected result is non-quantified"
        )
        XCTAssertEqual(resultState.correctedExposure.primaryText, "No corrected value")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "No published quantified correction is available for this metered exposure.")
        XCTAssertFalse(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .advisoryOnlyBeyondOfficialRange)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeUnsupportedResultKeepsCorrectedExposureRowStateWithoutNumericValue() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 64, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Unsupported")
        XCTAssertEqual(resultState.reciprocityState.tone, .unsupported)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 64, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposure.kind, .unsupported)
        XCTAssertNil(resultState.correctedExposure.correctedExposureSeconds)
        XCTAssertNil(resultState.correctedExposureAction.targetSeconds)
        XCTAssertFalse(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(
            resultState.correctedExposureAction.accessibilityHint,
            "Timer unavailable because this corrected result is unsupported"
        )
        XCTAssertEqual(resultState.correctedExposure.primaryText, "Unavailable")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "64 sec is not recommended.")
        XCTAssertFalse(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.presentation.category, .unsupported)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmSelectorEntriesKeepNoFilmFirstAndShowISOWhenAvailable() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.id, "no-film")
        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)

        XCTAssertEqual(
            viewModel.filmSelectorEntries.dropFirst().map(\.primaryText),
            ["Tri-X 400", "Portra 400", "Portra 400", "Velvia 50", "HP5 Plus"]
        )
        XCTAssertEqual(
            viewModel.filmSelectorEntries.dropFirst().map(\.secondaryText),
            ["ISO 400", "ISO 400", "Unofficial", "ISO 50", "ISO 400"]
        )
    }

    private func fallbackFormulaDetailsFilm() -> FilmIdentity {
        FilmIdentity(
            id: "fallback-formula-film",
            kind: .preset,
            canonicalStockName: "Fallback Formula 400",
            manufacturer: "Fallback",
            brandLabel: nil,
            aliases: [],
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "fallback-formula-profile",
                    name: "Fallback formula",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Fallback"
                    ),
                    rules: [
                        .formula(
                            FormulaReciprocityRule(
                                formula: ReciprocityFormula(
                                    exponent: 1.31,
                                    equation: nil
                                )
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }

    @MainActor
    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
    }

    private func minimalDetailsFilm() -> FilmIdentity {
        FilmIdentity(
            id: "minimal-details-film",
            kind: .preset,
            canonicalStockName: "Minimal 100",
            manufacturer: "Minimal",
            brandLabel: nil,
            aliases: [],
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "minimal-threshold-profile",
                    name: "Threshold only",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Minimal"
                    ),
                    rules: [
                        .threshold(
                            ThresholdReciprocityRule(
                                noCorrectionRange: ReciprocityTimeRange(
                                    minimumSeconds: 0,
                                    maximumSeconds: 1
                                )
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }

    private func urlBackedDetailsFilm() -> FilmIdentity {
        FilmIdentity(
            id: "url-details-film",
            kind: .preset,
            canonicalStockName: "Linked 100",
            manufacturer: "Linked",
            brandLabel: nil,
            aliases: [],
            productionStatus: .current,
            profiles: [
                ReciprocityProfile(
                    id: "url-threshold-profile",
                    name: "Linked threshold",
                    source: ReciprocitySourceProvenance(
                        kind: .manufacturerPublished,
                        authority: .official,
                        confidence: .high,
                        publisher: "Linked",
                        title: "Official reciprocity sheet",
                        citation: "https://example.com/reciprocity"
                    ),
                    rules: [
                        .threshold(
                            ThresholdReciprocityRule(
                                noCorrectionRange: ReciprocityTimeRange(
                                    minimumSeconds: 0,
                                    maximumSeconds: 4
                                )
                            )
                        )
                    ]
                )
            ],
            userMetadata: nil
        )
    }
}
