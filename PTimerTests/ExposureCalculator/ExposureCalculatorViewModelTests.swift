import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelTests: XCTestCase {
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
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
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
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
    }

    @MainActor
    func testFilmSelectorEntriesKeepISOAsSecondaryMetadata() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)
        XCTAssertEqual(viewModel.filmSelectorEntries.dropFirst().map(\.primaryText), [
            "Tri-X 400",
            "Portra 400",
            "Velvia 50",
            "HP5 Plus"
        ])
        XCTAssertEqual(viewModel.filmSelectorEntries.dropFirst().map(\.secondaryText), [
            "ISO 400",
            "ISO 400",
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
    func testSelectingPresetFilmPersistsWorkingContextValues() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        XCTAssertEqual(
            contextStore.snapshot,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 15.0,
                ndStop: 4
            )
        )
    }

    @MainActor
    func testRelaunchRestoresValidFilmModeWorkingContextAndReciprocityBinding() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let initialViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        let film = try XCTUnwrap(initialViewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        initialViewModel.baseShutter = 1.0 / 15.0
        initialViewModel.ndStop = 4
        initialViewModel.selectPresetFilm(film)

        let relaunchedViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        XCTAssertEqual(relaunchedViewModel.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(relaunchedViewModel.filmSelectionDisplayState.primaryText, "Tri-X 400")
        XCTAssertTrue(relaunchedViewModel.isFilmWorkflowActive)
        XCTAssertEqual(relaunchedViewModel.baseShutter, 1.0 / 15.0, accuracy: 0.000_001)
        XCTAssertEqual(relaunchedViewModel.ndStop, 4)
        let bindingState = try XCTUnwrap(relaunchedViewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.film.id, film.id)
        XCTAssertEqual(bindingState.profile.id, film.profiles.first?.id)
        XCTAssertTrue(bindingState.policyResult.hasCalculatedExposureTime)
        XCTAssertTrue(bindingState.presentation.returnsCalculatedExposureTime)
        XCTAssertEqual(relaunchedViewModel.filmModeExposureResultState?.reciprocityState.badgeText, "Exact")
    }

    @MainActor
    func testRelaunchWithoutStoredPresetFallsBackToNoFilmState() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(contextStore.snapshot)
    }

    @MainActor
    func testRelaunchWithInvalidStoredPresetIdentifierFallsBackSafely() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: "missing-preset-id",
                baseShutterSeconds: 1,
                ndStop: 4
            )
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(contextStore.snapshot)
    }

    @MainActor
    func testInvalidStoredPresetFallbackLeavesDigitalWorkflowUnaffected() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: "missing-preset-id",
                baseShutterSeconds: 1,
                ndStop: 4
            )
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertEqual(
            viewModel.calculationResult,
            .success(
                ExposureCalculationResult(
                    baseShutterSeconds: 1.0 / 30.0,
                    stop: 6,
                    resultShutterSeconds: 2
                )
            )
        )
    }

    @MainActor
    func testDigitalWorkingContextPersistsWithoutSelectedFilm() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        viewModel.baseShutter = 1
        viewModel.ndStop = 3

        XCTAssertEqual(
            contextStore.snapshot,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: nil,
                baseShutterSeconds: 1,
                ndStop: 3
            )
        )
    }

    @MainActor
    func testRelaunchRestoresDigitalWorkingContextWithoutSelectedFilm() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: nil,
                baseShutterSeconds: 1,
                ndStop: 3
            )
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.baseShutter, 1, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.ndStop, 3)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertEqual(
            viewModel.calculationResult,
            .success(
                ExposureCalculationResult(
                    baseShutterSeconds: 1,
                    stop: 3,
                    resultShutterSeconds: 8
                )
            )
        )
    }

    @MainActor
    func testRelaunchWithInvalidStoredNumericValuesFallsBackToDefaultCalculatorInputs() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let film = try XCTUnwrap(makeViewModel().availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 0.3,
                ndStop: 99
            )
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )

        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.ndStop, 0)
        XCTAssertEqual(
            contextStore.snapshot,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 30.0,
                ndStop: 0
            )
        )
    }

    @MainActor
    func testResetFilmModeWorkingContextClearsSelectionInputsAndPersistedSnapshot() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canResetFilmModeWorkingContext)

        viewModel.resetFilmModeWorkingContext()

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertFalse(viewModel.canResetFilmModeWorkingContext)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.ndStop, 0)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(contextStore.snapshot)
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "Final shooting value")
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
        XCTAssertEqual(details.sections.map(\.title), [
            "Profile",
            "Reference",
            "Current Status",
            "Sources"
        ])
        XCTAssertTrue(details.showsGraphPlaceholder)
        XCTAssertEqual(details.sections.first?.rows.map(\.title), ["Profile"])
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
        let statusSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Current Status" }))
        let sourcesSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Sources" }))

        XCTAssertEqual(profileSection.rows.map(\.value), ["Reference table"])
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
        XCTAssertEqual(statusSection.rows.map(\.value), ["Estimated between 1s and 10s"])
        XCTAssertEqual(sourcesSection.rows.map(\.title), ["Reference", "Citation"])
        XCTAssertFalse(details.sections.flatMap(\.rows).map(\.title).contains("Basis"))
        XCTAssertFalse(details.sections.flatMap(\.rows).map(\.title).contains("Entry"))
        XCTAssertEqual(sourcesSection.rows.last?.destinationURL, nil)
    }

    @MainActor
    func testFilmModeDetailsShowManufacturerNoDataForAdvisoryOnlyResult() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let statusSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Current Status" }))
        XCTAssertEqual(details.sections.last?.title, "Sources")
        XCTAssertEqual(profileSection.rows.map(\.value), ["No quantified manufacturer data"])
        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.referenceBlock])
        XCTAssertEqual(referenceSection.rows.map(\.value), ["1/10000s-1s    No correction"])
        XCTAssertEqual(statusSection.rows.map(\.value), ["No quantified reciprocity value available"])
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
        let profileSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Profile" }))
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let statusSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Current Status" }))

        XCTAssertEqual(profileSection.rows.map(\.value), ["Formula profile"])
        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.formulaExpression])
        XCTAssertEqual(referenceSection.rows.map(\.value), ["Tc = Tm^1.31"])
        XCTAssertFalse(referenceSection.rows.contains { $0.value == "Tc = Tm^P" })
        XCTAssertEqual(statusSection.rows.map(\.value), ["Derived from formula profile"])
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
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))

        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.formulaExpression])
        XCTAssertEqual(referenceSection.rows.map(\.value), ["Tc = Tm^1.31"])
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
            viewModel.formatTimeDisplay(correctedExposureSeconds).primary
        )
        XCTAssertEqual(resultState.correctedExposure.primaryText, "03:10:32.037")
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "Low-confidence shooting value")
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "Low-confidence shooting value")
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
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Calculated")
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
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Advisory only")
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
        XCTAssertEqual(resultState.correctedExposure.primaryText, "No quantified correction")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "Only advisory continuation is available for this metered exposure.")
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
        XCTAssertEqual(resultState.correctedExposure.primaryText, "Unsupported")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "64 sec is not recommended.")
        XCTAssertFalse(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.presentation.category, .unsupported)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeCorrectedExposureTimerUsesQuantifiedCorrectedResult() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 1, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "Tri-X 400 - 1s")
        XCTAssertEqual(
            timer.basisSummary,
            "Base 1s · 0 stops · Adjusted 1s · Tri-X 400 · Corrected 1s"
        )
    }

    @MainActor
    func testFilmModeAdjustedShutterTimerStartsFromAdjustedValueWhenCorrectedIsQuantified() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 1, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "0 stops - 1s")
        XCTAssertEqual(
            timer.basisSummary,
            "Base 1s · 0 stops · Adjusted 1s · Tri-X 400"
        )
    }

    @MainActor
    func testFilmModeAdvisoryOnlyDoesNotProvideCorrectedExposureTimerSource() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)

        viewModel.startFilmCorrectedExposureTimer()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .advisory)
    }

    @MainActor
    func testFilmModeAdjustedShutterTimerStartsForAdvisoryOnlyResult() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 15, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "0 stops - 15s")
        XCTAssertEqual(timer.basisSummary, "Base 15s · 0 stops · Adjusted 15s · Portra 400")
    }

    @MainActor
    func testFilmModeUnsupportedDoesNotProvideCorrectedExposureTimerSource() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)

        viewModel.startFilmCorrectedExposureTimer()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertEqual(viewModel.filmModeExposureResultState?.correctedExposure.kind, .unsupported)
    }

    @MainActor
    func testFilmModeAdjustedShutterTimerStartsForUnsupportedResult() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)

        viewModel.startFilmAdjustedShutterTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 64, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "3 stops - 64s")
        XCTAssertEqual(timer.basisSummary, "Base 8s · 3 stops · Adjusted 64s · Velvia 50")
    }

    @MainActor
    func testDigitalModeStartTimerBehaviorRemainsUnchanged() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.name, "6 stops - 2s")
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 6 stops")
    }

    @MainActor
    func testFilmSelectorEntriesKeepNoFilmFirstAndShowISOWhenAvailable() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.id, "no-film")
        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)

        XCTAssertEqual(
            viewModel.filmSelectorEntries.dropFirst().map(\.primaryText),
            ["Tri-X 400", "Portra 400", "Velvia 50", "HP5 Plus"]
        )
        XCTAssertEqual(
            viewModel.filmSelectorEntries.dropFirst().map(\.secondaryText),
            ["ISO 400", "ISO 400", "ISO 50", "ISO 400"]
        )
    }

    @MainActor
    func testStartTimerPublishesCapturedMetadataOnFirstRuntimeEmission() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        var nonEmptyEmissions: [[RunningTimerItem]] = []

        let cancellable = viewModel.$timers.sink { timers in
            guard !timers.isEmpty else {
                return
            }

            nonEmptyEmissions.append(timers)
        }
        defer { cancellable.cancel() }

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        XCTAssertEqual(nonEmptyEmissions.count, 1)
        XCTAssertEqual(nonEmptyEmissions.first?.first?.name, "6 stops - 2s")
        XCTAssertEqual(nonEmptyEmissions.first?.first?.basisSummary, "Base 1/30s · 6 stops")
    }

    @MainActor
    func testCanStartTimerDependsOnValidCalculationInputs() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        XCTAssertTrue(viewModel.canStartTimer)
    }

    @MainActor
    func testFormatTimerClockUsesLeadingZeroMinutesAndSeconds() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimerClock(0), "0s")
        XCTAssertEqual(viewModel.formatTimerClock(5), "5s")
        XCTAssertEqual(viewModel.formatTimerClock(59), "59s")
        XCTAssertEqual(viewModel.formatTimerClock(60), "01:00")
        XCTAssertEqual(viewModel.formatTimerClock(65), "01:05")
        XCTAssertEqual(viewModel.formatTimerClock(3599), "59:59")
        XCTAssertEqual(viewModel.formatTimerClock(3600), "01:00:00")
        XCTAssertEqual(viewModel.formatTimerClock(90_000), "1d 01:00:00")
        XCTAssertEqual(viewModel.formatTimerClock(2_592_000), "1mo 00:00:00")
        XCTAssertEqual(viewModel.formatTimerClock(31_536_000), "1y 00:00:00")
    }

    @MainActor
    func testFormatTimerClockClampsSubsecondAndNegativeValuesToZero() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimerClock(0.9), "0.9s")
        XCTAssertEqual(viewModel.formatTimerClock(-3), "0s")
    }

    @MainActor
    func testFormatTimeDisplayAlwaysShowsRawSecondsAndClock() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(0), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(-3), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(5), TimeDisplay(primary: "5s", secondary: "5s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(128), TimeDisplay(primary: "02:08", secondary: "128s"))
    }

    @MainActor
    func testFormatTimeDisplayBoundaryCases() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(0), TimeDisplay(primary: "0s", secondary: "0s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.033), TimeDisplay(primary: "0.033s", secondary: "0.033s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.125), TimeDisplay(primary: "0.125s", secondary: "0.125s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.9), TimeDisplay(primary: "0.9s", secondary: "0.9s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(1), TimeDisplay(primary: "1s", secondary: "1s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(5), TimeDisplay(primary: "5s", secondary: "5s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(21.158), TimeDisplay(primary: "21.158s", secondary: "21.158s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(59.9), TimeDisplay(primary: "59.9s", secondary: "59.9s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(60), TimeDisplay(primary: "01:00", secondary: "60s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(61), TimeDisplay(primary: "01:01", secondary: "61s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(3599), TimeDisplay(primary: "59:59", secondary: "3599s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(3600), TimeDisplay(primary: "01:00:00", secondary: "3600s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(86_399), TimeDisplay(primary: "23:59:59", secondary: "86399s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(86_400), TimeDisplay(primary: "1d 00:00:00", secondary: "86400s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(2_592_000), TimeDisplay(primary: "1mo 00:00:00", secondary: "2592000s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(31_536_000), TimeDisplay(primary: "1y 00:00:00", secondary: "31536000s"))
    }

    @MainActor
    func testFormatTimeDisplayPrecisionPolicy() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(128.25), TimeDisplay(primary: "02:08.250", secondary: "128.25s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(12.345), TimeDisplay(primary: "12.345s", secondary: "12.345s"))
        XCTAssertEqual(viewModel.formatTimeDisplay(0.033), TimeDisplay(primary: "0.033s", secondary: "0.033s"))
    }

    @MainActor
    func testFormatDateTimeAndTimerContextSemanticsIncludeDate() {
        let currentDate = Date(timeIntervalSince1970: 100)
        let endDate = Date(timeIntervalSince1970: 9_060)
        let pausedDate = Date(timeIntervalSince1970: 8_940)
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { currentDate }
            )
        )

        let running = RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Timer 1",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_940),
            endDate: endDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: currentDate
        )

        let paused = RunningTimerItem(
            id: UUID(),
            order: 2,
            name: "Timer 2",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_820),
            endDate: nil,
            pausedRemainingTime: 45,
            pausedAt: pausedDate,
            status: .paused,
            referenceDate: currentDate
        )

        let completed = RunningTimerItem(
            id: UUID(),
            order: 3,
            name: "Timer 3",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 120,
            startDate: Date(timeIntervalSince1970: 8_700),
            endDate: pausedDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: currentDate
        )

        XCTAssertEqual(viewModel.timerTimeContext(for: running), "Ends \(viewModel.formatDateTime(endDate))")
        XCTAssertEqual(viewModel.timerTimeContext(for: paused), "Paused \(viewModel.formatDateTime(pausedDate))")
        XCTAssertEqual(
            viewModel.timerTimeContext(for: completed),
            "Completed \(viewModel.formatDateTime(pausedDate)) · just now"
        )
    }

    @MainActor
    func testStartTimerCreatesDisplayItemThroughManager() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        XCTAssertEqual(timerManager.timers.count, 1)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertEqual(viewModel.runningTimerCount, 1)
        XCTAssertEqual(viewModel.timers[0].name, "6 stops - 2s")
        XCTAssertEqual(viewModel.timers[0].status, TimerStatus.running)
        XCTAssertEqual(viewModel.timers[0].remainingTime, 2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.formatTimeDisplay(viewModel.timers[0].remainingTime), TimeDisplay(primary: "2s", secondary: "2s"))
        XCTAssertEqual(viewModel.timers[0].basisSummary, "Base 1/30s · 6 stops")
    }

    @MainActor
    func testRunningTimerDisplaySemanticsPreserveTargetAndContext() throws {
        let currentDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(timer.remainingTime, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 6 stops")
        XCTAssertEqual(viewModel.timerTargetContext(for: timer), "2s · 2s")
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Ends \(viewModel.formatDateTime(try XCTUnwrap(timer.endDate)))"
        )
    }

    @MainActor
    func testStartTimerFromDomainAPIUsesProvidedResult() {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 30)

        XCTAssertEqual(timerManager.timers.count, 1)
        XCTAssertEqual(viewModel.timers.first?.name, "Timer - 30s")
        XCTAssertEqual(viewModel.runningTimerCount, 1)
    }

    @MainActor
    func testClearCompletedTimersRemovesCompletedDisplayItems() {
        let startDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.startTimer()

        timerManager.tick(now: startDate.addingTimeInterval(1))
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.completed)

        viewModel.clearCompletedTimers()

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertTrue(timerManager.timers.isEmpty)
    }

    @MainActor
    func testClearCompletedTimersPreservesActiveMetadataAndRemovesCompletedMetadataBeforeNewTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        viewModel.baseShutter = 1
        viewModel.ndStop = 3
        viewModel.startTimer()

        XCTAssertEqual(viewModel.timers.count, 2)
        XCTAssertEqual(viewModel.timers.map(\.name), ["3 stops - 8s", "6 stops - 2s"])
        XCTAssertEqual(
            viewModel.timers.map(\.basisSummary),
            ["Base 1s · 3 stops", "Base 1/30s · 6 stops"]
        )

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        let completedTimer = try XCTUnwrap(viewModel.timers.first { $0.status == .completed })
        let activeTimer = try XCTUnwrap(viewModel.timers.first { $0.status == .running })

        XCTAssertEqual(completedTimer.name, "6 stops - 2s")
        XCTAssertEqual(completedTimer.basisSummary, "Base 1/30s · 6 stops")
        XCTAssertEqual(activeTimer.name, "3 stops - 8s")
        XCTAssertEqual(activeTimer.basisSummary, "Base 1s · 3 stops")

        viewModel.clearCompletedTimers()

        XCTAssertEqual(viewModel.timers.count, 1)
        let survivingTimer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(survivingTimer.status, .running)
        XCTAssertEqual(survivingTimer.name, "3 stops - 8s")
        XCTAssertEqual(survivingTimer.basisSummary, "Base 1s · 3 stops")

        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4
        viewModel.startTimer()

        XCTAssertEqual(viewModel.timers.count, 2)
        XCTAssertEqual(viewModel.timers.map(\.name), ["4 stops - 1s", "3 stops - 8s"])
        XCTAssertEqual(
            viewModel.timers.map(\.basisSummary),
            ["Base 1/15s · 4 stops", "Base 1s · 3 stops"]
        )
    }

    @MainActor
    func testPauseTimerUpdatesViewModelState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.pauseTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        let remainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(remainingTime, 6, accuracy: 0.0001)
    }

    @MainActor
    func testRunningTimerExposesLockScreenTargetUsingTimerEndDate() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 10)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(exposer.exposedTargets, [
            LockScreenTimerTarget(
                representativeTimerID: timer.id,
                representativeTimerName: timer.name,
                representativeEndDate: try XCTUnwrap(timer.endDate),
                scheduledTargets: [
                    LockScreenTimerScheduledTarget(
                        timerID: timer.id,
                        timerName: timer.name,
                        endDate: try XCTUnwrap(timer.endDate)
                    )
                ]
            )
        ])
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, timer.endDate)
        XCTAssertEqual(exposer.clearCount, 0)
    }

    @MainActor
    func testLockScreenTargetSelectionUsesEarliestRunningTimerEndDate() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 20)
        let longerRunning = try XCTUnwrap(viewModel.timers.first)
        viewModel.startTimer(from: 12)
        let shorterRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 12 }))

        XCTAssertNotEqual(viewModel.timers.first?.id, longerRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, shorterRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, shorterRunning.endDate)
        XCTAssertEqual(exposer.currentTarget?.scheduledTargets.map(\.timerID), [shorterRunning.id, longerRunning.id])
    }

    @MainActor
    func testLockScreenTargetSelectionUsesPresentationOrderWhenEarliestEndDateIsTied() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 30)
        let olderRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 30 }))

        currentDate = startDate.addingTimeInterval(10)
        viewModel.startTimer(from: 20)
        let newerRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 20 }))

        XCTAssertEqual(olderRunning.endDate, newerRunning.endDate)
        XCTAssertEqual(viewModel.timers.first?.id, newerRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, newerRunning.id)
    }

    @MainActor
    func testLockScreenTargetSelectionUsesStableIDOrderWhenEndDateAndPresentationOrderAreTied() {
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let sharedEndDate = Date(timeIntervalSince1970: 500)
        let referenceDate = Date(timeIntervalSince1970: 100)

        let laterIDTimer = RunningTimerItem(
            id: laterID,
            order: 7,
            name: "Later ID",
            basisSummary: "Manual timer",
            duration: 30,
            startDate: Date(timeIntervalSince1970: 470),
            endDate: sharedEndDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: referenceDate
        )

        let earlierIDTimer = RunningTimerItem(
            id: earlierID,
            order: 7,
            name: "Earlier ID",
            basisSummary: "Manual timer",
            duration: 30,
            startDate: Date(timeIntervalSince1970: 470),
            endDate: sharedEndDate,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: referenceDate
        )

        let target = LockScreenTimerTargetCoordinator.selectRepresentativeTarget(
            from: [laterIDTimer, earlierIDTimer]
        )

        XCTAssertEqual(target?.representativeTimerID, earlierID)
        XCTAssertEqual(target?.representativeEndDate, sharedEndDate)
    }

    @MainActor
    func testPausedTimerIsNotRepresentativeAndFallsBackToNextEarliestRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 20)
        let fallbackRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 20 }))
        viewModel.startTimer(from: 12)
        let selectedRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 12 }))

        currentDate = startDate.addingTimeInterval(5)
        viewModel.pauseTimer(id: selectedRunning.id)

        XCTAssertEqual(viewModel.timers.first(where: { $0.id == selectedRunning.id })?.status, .paused)
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, fallbackRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, fallbackRunning.endDate)
    }

    @MainActor
    func testPausedAndCompletedTimersAreIgnoredByEarliestEndDateRepresentativeSelection() {
        let sharedReferenceDate = Date(timeIntervalSince1970: 100)
        let runningTimer = RunningTimerItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            order: 3,
            name: "Running",
            basisSummary: "Manual timer",
            duration: 15,
            startDate: Date(timeIntervalSince1970: 95),
            endDate: Date(timeIntervalSince1970: 110),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: sharedReferenceDate
        )

        let pausedTimer = RunningTimerItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            order: 4,
            name: "Paused",
            basisSummary: "Manual timer",
            duration: 3,
            startDate: Date(timeIntervalSince1970: 99),
            endDate: Date(timeIntervalSince1970: 102),
            pausedRemainingTime: 2,
            pausedAt: Date(timeIntervalSince1970: 100),
            status: .paused,
            referenceDate: sharedReferenceDate
        )

        let completedTimer = RunningTimerItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            order: 5,
            name: "Completed",
            basisSummary: "Manual timer",
            duration: 2,
            startDate: Date(timeIntervalSince1970: 98),
            endDate: Date(timeIntervalSince1970: 101),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: sharedReferenceDate
        )

        let target = LockScreenTimerTargetCoordinator.selectRepresentativeTarget(
            from: [pausedTimer, completedTimer, runningTimer]
        )

        XCTAssertEqual(target?.representativeTimerID, runningTimer.id)
        XCTAssertEqual(target?.representativeEndDate, runningTimer.endDate)
    }

    @MainActor
    func testLockScreenScheduledTargetsCanHandOffToNextTimerWithoutAppStateRefresh() {
        let state = TimerTargetLiveActivityAttributes.ContentState(
            representativeTimerName: "30s timer",
            representativeEndDate: Date(timeIntervalSince1970: 130),
            scheduledTargets: [
                LockScreenTimerScheduledTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                    timerName: "30s timer",
                    endDate: Date(timeIntervalSince1970: 130)
                ),
                LockScreenTimerScheduledTarget(
                    timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
                    timerName: "2m timer",
                    endDate: Date(timeIntervalSince1970: 220)
                )
            ]
        )

        XCTAssertEqual(state.displayTarget(at: Date(timeIntervalSince1970: 120))?.timerName, "30s timer")
        XCTAssertEqual(state.displayTarget(at: Date(timeIntervalSince1970: 131))?.timerName, "2m timer")
    }

    @MainActor
    func testCompletedTimerIsNotRepresentativeCandidateAndClearsWhenNoRunningTimerRemains() {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        XCTAssertNil(exposer.currentTarget)
        XCTAssertEqual(exposer.clearCount, 1)
    }

    @MainActor
    func testCompletingRepresentativeTimerHandsOffToNextEarliestRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 10)
        let fallbackRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 10 }))
        viewModel.startTimer(from: 2)
        _ = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 2 }))

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, fallbackRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, fallbackRunning.endDate)
        XCTAssertEqual(exposer.currentTarget?.scheduledTargets.map(\.timerID), [fallbackRunning.id])
    }

    @MainActor
    func testRemovingRepresentativeTimerHandsOffToNextEarliestRunningTimer() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 15)
        let fallbackRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 15 }))
        viewModel.startTimer(from: 8)
        let selectedRunningID = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 8 })?.id)

        viewModel.removeTimer(id: selectedRunningID)

        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, fallbackRunning.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, fallbackRunning.endDate)
    }

    @MainActor
    func testResumeRecalculatesEndDateAndReselectsEarliestRunningRepresentative() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 20)
        let longRunning = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 20 }))
        viewModel.startTimer(from: 8)
        let resumableID = try XCTUnwrap(viewModel.timers.first(where: { $0.duration == 8 })?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: resumableID)

        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, longRunning.id)

        currentDate = startDate.addingTimeInterval(10)
        viewModel.resumeTimer(id: resumableID)

        let resumed = try XCTUnwrap(viewModel.timers.first(where: { $0.id == resumableID }))
        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.endDate, currentDate.addingTimeInterval(5))
        XCTAssertEqual(exposer.currentTarget?.representativeTimerID, resumed.id)
        XCTAssertEqual(exposer.currentTarget?.representativeEndDate, resumed.endDate)
        XCTAssertLessThan(try XCTUnwrap(resumed.endDate), try XCTUnwrap(longRunning.endDate))
    }

    @MainActor
    func testNoRunningTimerClearsStaleLockScreenTargetExposure() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let exposer = LockScreenTimerTargetExposerSpy()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            lockScreenTargetExposer: exposer
        )

        viewModel.startTimer(from: 6)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(2)
        viewModel.pauseTimer(id: id)

        XCTAssertNil(exposer.currentTarget)
        XCTAssertEqual(exposer.clearCount, 1)
    }

    @MainActor
    func testPausedTimerRemainingTimeStaysStableInViewModel() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)

        let pausedRemainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        XCTAssertEqual(pausedRemainingTime, 5, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(12)
        timerManager.tick(now: currentDate)

        let stableRemainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.paused)
        XCTAssertEqual(stableRemainingTime, 5, accuracy: 0.0001)
    }

    @MainActor
    func testPausedTimerDisplaySemanticsPreservePauseMetadataAndRemainResumable() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .paused)
        XCTAssertEqual(timer.remainingTime, 5, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 8, accuracy: 0.0001)
        XCTAssertEqual(timer.pausedAt, currentDate)
        XCTAssertEqual(viewModel.timerTargetContext(for: timer), "8s · 8s")
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Paused \(viewModel.formatDateTime(try XCTUnwrap(timer.pausedAt)))"
        )

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.status, .running)
    }

    @MainActor
    func testResumeTimerUpdatesViewModelState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, .paused)
        XCTAssertEqual(try XCTUnwrap(viewModel.timers.first?.remainingTime), 5, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)

        XCTAssertEqual(viewModel.timers.first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(viewModel.timers.first?.remainingTime), 5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.timers.count, 1)
        XCTAssertEqual(viewModel.timers.first?.basisSummary, "Manual timer")
    }

    @MainActor
    func testReconcileTimersAfterAppBecomesActivePublishesUpdatedTimerStateWithoutUserInteraction() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        var nonEmptyEmissions: [[RunningTimerItem]] = []

        let cancellable = viewModel.$timers.sink { timers in
            guard !timers.isEmpty else {
                return
            }

            nonEmptyEmissions.append(timers)
        }
        defer { cancellable.cancel() }

        viewModel.startTimer(from: 10)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.reconcileTimersAfterAppBecomesActive()

        XCTAssertEqual(nonEmptyEmissions.count, 2)
        XCTAssertEqual(nonEmptyEmissions[0].first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(nonEmptyEmissions[0].first).remainingTime, 10, accuracy: 0.0001)
        XCTAssertEqual(nonEmptyEmissions[1].first?.status, .running)
        XCTAssertEqual(try XCTUnwrap(nonEmptyEmissions[1].first).remainingTime, 6, accuracy: 0.0001)
    }

    @MainActor
    func testReconcileTimersAfterAppBecomesActiveUpdatesCompletedDisplayState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(4)
        viewModel.reconcileTimersAfterAppBecomesActive()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.remainingTime, 0, accuracy: 0.0001)
    }

    @MainActor
    func testCompletedTimerShowsZeroRemainingTimeInViewModel() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(4)
        timerManager.tick(now: currentDate)

        XCTAssertEqual(viewModel.timers.first?.status, TimerStatus.completed)
        let remainingTime = try XCTUnwrap(viewModel.timers.first?.remainingTime)
        XCTAssertEqual(remainingTime, 0, accuracy: 0.0001)
        XCTAssertEqual(viewModel.formatTimeDisplay(remainingTime), TimeDisplay(primary: "0s", secondary: "0s"))
    }

    @MainActor
    func testCompletedTimerDisplaySemanticsPreserveOriginalDurationAndCompletionMetadata() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 2)

        currentDate = startDate.addingTimeInterval(4)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(timer.remainingTime, 0, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 2, accuracy: 0.0001)
        XCTAssertEqual(timer.completedAt, startDate.addingTimeInterval(2))
        XCTAssertNil(viewModel.timerTargetContext(for: timer))
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Completed \(viewModel.formatDateTime(try XCTUnwrap(timer.completedAt))) · just now"
        )
    }

    @MainActor
    func testRunningTimerPrimaryIsRemainingSecondaryIsExactSeconds() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 90)
        currentDate = startDate.addingTimeInterval(8)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let display = viewModel.formatTimeDisplay(timer.remainingTime)
        XCTAssertEqual(display.primary, "01:22")
        XCTAssertEqual(display.secondary, "82s")
    }

    @MainActor
    func testCompletedTimerDisplaysOriginalDurationNotZero() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 90)

        currentDate = startDate.addingTimeInterval(120)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let display = viewModel.formatTimeDisplay(timer.duration)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(display.primary, "01:30")
        XCTAssertNotEqual(display.primary, "0s")
    }

    @MainActor
    func testRunningTimerIncludesEndDateWithFullDateFormat() throws {
        let currentDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 120)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let context = try XCTUnwrap(viewModel.timerTimeContext(for: timer))
        XCTAssertEqual(context, "Ends \(viewModel.formatDateTime(try XCTUnwrap(timer.endDate)))")
    }

    @MainActor
    func testPausedTimerIncludesPausedDateWithFullDateFormat() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 120)
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        currentDate = startDate.addingTimeInterval(10)
        viewModel.pauseTimer(id: id)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Paused \(viewModel.formatDateTime(try XCTUnwrap(timer.pausedAt)))"
        )
    }

    @MainActor
    func testCompletedTimerIncludesCompletedDateWithFullDateFormat() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 2)
        currentDate = startDate.addingTimeInterval(5)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(
            viewModel.timerTimeContext(for: timer),
            "Completed \(viewModel.formatDateTime(try XCTUnwrap(timer.completedAt))) · just now"
        )
    }

    @MainActor
    func testTimerDisplayDoesNotDuplicateInformation() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 10
        viewModel.startTimer()

        currentDate = startDate.addingTimeInterval(3)
        timerManager.tick(now: currentDate)

        let timer = try XCTUnwrap(viewModel.timers.first)
        let primary = viewModel.formatTimeDisplay(timer.remainingTime)
        let targetContext = try XCTUnwrap(viewModel.timerTargetContext(for: timer))
        let timeContext = try XCTUnwrap(viewModel.timerTimeContext(for: timer))

        XCTAssertFalse(targetContext.contains("Ends "))
        XCTAssertFalse(timeContext.contains(timer.basisSummary))
        XCTAssertFalse(targetContext.contains("Base "))
        XCTAssertFalse(targetContext.contains("ND "))
        XCTAssertFalse(timeContext.contains(primary.primary))
        XCTAssertFalse(timeContext.contains(primary.secondary))
    }

    @MainActor
    func testTimerDisplayHandlesLargeDurationsInReadableFormat() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(
            viewModel.formatTimeDisplay(2_592_000),
            TimeDisplay(primary: "1mo 00:00:00", secondary: "2592000s")
        )
        XCTAssertEqual(
            viewModel.formatTimeDisplay(31_536_000),
            TimeDisplay(primary: "1y 00:00:00", secondary: "31536000s")
        )
    }

    @MainActor
    func testTimerDisplayPrecisionDoesNotShowExcessiveDecimals() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        XCTAssertEqual(viewModel.formatTimeDisplay(128).secondary, "128s")
        XCTAssertEqual(viewModel.formatTimeDisplay(21.158).secondary, "21.158s")
        XCTAssertFalse(viewModel.formatTimeDisplay(128).secondary.contains(".000"))
    }

    @MainActor
    func testBasisSummaryRemainsStableAcrossStateChanges() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        let originalSummary = viewModel.timers.first?.basisSummary

        currentDate = startDate.addingTimeInterval(1)
        viewModel.pauseTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.basisSummary, originalSummary)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.basisSummary, originalSummary)
    }

    @MainActor
    func testTimerStateTransitionDoesNotCorruptDisplayModel() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 8)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        var timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "8s")

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .paused)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "5s")

        currentDate = startDate.addingTimeInterval(5)
        viewModel.resumeTimer(id: id)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .running)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.remainingTime).primary, "5s")

        currentDate = startDate.addingTimeInterval(11)
        timerManager.tick(now: currentDate)
        timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.status, .completed)
        XCTAssertEqual(viewModel.formatTimeDisplay(timer.duration).primary, "8s")
    }

    @MainActor
    func testExistingTimerMetadataDoesNotChangeAfterInputUpdates() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.startTimer()

        let initialTimer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(initialTimer.name, "6 stops - 2s")
        XCTAssertEqual(initialTimer.basisSummary, "Base 1/30s · 6 stops")

        viewModel.baseShutter = 1
        viewModel.ndStop = 3

        let timerAfterInputChange = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timerAfterInputChange.name, "6 stops - 2s")
        XCTAssertEqual(timerAfterInputChange.basisSummary, "Base 1/30s · 6 stops")
    }

    @MainActor
    func testNDStopSelectionUpdatesCalculationImmediately() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        guard case .success(let nd64Result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for 6-stop ND")
        }

        XCTAssertEqual(nd64Result.resultShutterSeconds, 2, accuracy: 0.0001)

        viewModel.ndStop = 10

        guard case .success(let nd1000Result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for 10-stop ND")
        }

        XCTAssertEqual(nd1000Result.resultShutterSeconds, 30, accuracy: 0.0001)
    }

    @MainActor
    func testLiveNDStopPreviewFeedsCalculationBeforeSettledSelection() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveNDStop(10)

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for live 10-stop preview")
        }

        XCTAssertEqual(result.stop, 10)
        XCTAssertEqual(result.resultShutterSeconds, 30, accuracy: 0.0001)
    }

    @MainActor
    func testLiveBaseShutterPreviewFeedsCalculationBeforeSettledSelection() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveBaseShutter(1.0 / 15.0)

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result for live 1/15s preview")
        }

        XCTAssertEqual(result.baseShutterSeconds, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(result.stop, 6)
        XCTAssertEqual(result.resultShutterSeconds, 4, accuracy: 0.0001)
    }

    @MainActor
    func testSettledNDStopClearsMatchingLivePreview() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveNDStop(10)
        viewModel.ndStop = 10

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after settled 10-stop selection")
        }

        XCTAssertEqual(result.stop, 10)
        XCTAssertEqual(result.resultShutterSeconds, 30, accuracy: 0.0001)

        viewModel.clearLiveNDStopPreview()

        guard case .success(let settledResult) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after live preview reset")
        }

        XCTAssertEqual(settledResult.stop, 10)
        XCTAssertEqual(settledResult.resultShutterSeconds, 30, accuracy: 0.0001)
    }

    @MainActor
    func testSettledBaseShutterClearsMatchingLivePreview() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveBaseShutter(1.0 / 15.0)
        viewModel.baseShutter = 1.0 / 15.0

        guard case .success(let result) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after settled 1/15s selection")
        }

        XCTAssertEqual(result.baseShutterSeconds, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(result.stop, 6)
        XCTAssertEqual(result.resultShutterSeconds, 4, accuracy: 0.0001)

        viewModel.clearLiveBaseShutterPreview()

        guard case .success(let settledResult) = viewModel.calculationResult else {
            return XCTFail("Expected valid result after live base shutter reset")
        }

        XCTAssertEqual(settledResult.baseShutterSeconds, 1.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(settledResult.stop, 6)
        XCTAssertEqual(settledResult.resultShutterSeconds, 4, accuracy: 0.0001)
    }

    @MainActor
    func testStartTimerUsesLivePreviewCalculationWhenPresent() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveNDStop(10)
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.name, "10 stops - 30s")
        XCTAssertEqual(timer.basisSummary, "Base 1/30s · 10 stops")
        XCTAssertEqual(timer.duration, 30, accuracy: 0.0001)
    }

    @MainActor
    func testStartTimerUsesLiveBaseShutterPreviewCalculationWhenPresent() throws {
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        viewModel.updateLiveBaseShutter(1.0 / 15.0)
        viewModel.startTimer()

        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.name, "6 stops - 4s")
        XCTAssertEqual(timer.basisSummary, "Base 1/15s · 6 stops")
        XCTAssertEqual(timer.duration, 4, accuracy: 0.0001)
    }

    @MainActor
    func testTargetDurationNeverChangesAcrossStateTransitions() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)

        let originalDuration = try XCTUnwrap(viewModel.timers.first?.duration)

        currentDate = startDate.addingTimeInterval(3)
        viewModel.pauseTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)

        currentDate = startDate.addingTimeInterval(6)
        viewModel.resumeTimer(id: id)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)

        currentDate = startDate.addingTimeInterval(15)
        timerManager.tick(now: currentDate)
        XCTAssertEqual(viewModel.timers.first?.duration, originalDuration)
    }

    @MainActor
    func testDisplayDoesNotUseForbiddenCharacters() throws {
        let startDate = Date(timeIntervalSince1970: 100)

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { startDate }
            )
        )

        viewModel.startTimer(from: 128)

        let timer = try XCTUnwrap(viewModel.timers.first)

        let primary = viewModel.formatTimeDisplay(timer.duration).primary
        let secondary = viewModel.formatTimeDisplay(timer.duration).secondary
        let context = viewModel.timerTimeContext(for: timer) ?? ""

        let allText = primary + secondary + context

        XCTAssertFalse(allText.contains("/"))
        XCTAssertFalse(allText.contains("("))
        XCTAssertFalse(allText.contains(")"))
    }

    @MainActor
    func testRelaunchRestoresTimerCardIdentityMetadataForMultipleTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerStore = InMemoryTimerPersistenceStore()
        let metadataStore = InMemoryTimerMetadataPersistenceStore()

        let initialTimerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: timerStore
        )
        let initialViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: initialTimerManager,
            metadataPersistenceStore: metadataStore
        )

        initialViewModel.baseShutter = 1.0 / 30.0
        initialViewModel.ndStop = 6
        initialViewModel.startTimer()

        initialViewModel.baseShutter = 1.0
        initialViewModel.ndStop = 3
        initialViewModel.startTimer()

        let runningTimer = try XCTUnwrap(initialViewModel.timers.first(where: { $0.name == "3 stops - 8s" }))
        let pausedTimer = try XCTUnwrap(initialViewModel.timers.first(where: { $0.name == "6 stops - 2s" }))

        currentDate = startDate.addingTimeInterval(1)
        initialViewModel.pauseTimer(id: pausedTimer.id)

        let relaunchedTimerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: timerStore
        )
        let relaunchedViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: relaunchedTimerManager,
            metadataPersistenceStore: metadataStore
        )

        XCTAssertEqual(relaunchedViewModel.timers.map(\.id), [runningTimer.id, pausedTimer.id])
        XCTAssertEqual(relaunchedViewModel.timers.map(\.name), ["3 stops - 8s", "6 stops - 2s"])
        XCTAssertEqual(
            relaunchedViewModel.timers.map(\.basisSummary),
            ["Base 1s · 3 stops", "Base 1/30s · 6 stops"]
        )
        XCTAssertEqual(relaunchedViewModel.timers.map(\.order), [2, 1])
        XCTAssertEqual(relaunchedViewModel.timers.map(\.status), [.running, .paused])
    }

    @MainActor
    func testRelaunchWithCorruptedMetadataSnapshotKeepsTimerRestoreIndependent() throws {
        let suiteName = "ExposureCalculatorViewModelTests.corrupted.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let timerStore = InMemoryTimerPersistenceStore()
        let timerID = UUID()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 10,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 110),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    )
                ]
            )
        )
        userDefaults.set(Data("corrupted-metadata".utf8), forKey: "ptimer.timer-metadata.snapshot")

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 104) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: UserDefaultsTimerMetadataPersistenceStore(userDefaults: userDefaults)
        )

        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.status), [.running])
        XCTAssertEqual(viewModel.timers.map(\.name), ["Timer - 10s"])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), ["Manual timer"])
    }

    @MainActor
    func testRelaunchWithoutMetadataSnapshotFallsBackToDefaultCardIdentity() {
        let timerStore = InMemoryTimerPersistenceStore()
        let timerID = UUID()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 10,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 110),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    )
                ]
            )
        )

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 104) },
            persistenceStore: timerStore
        )
        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )

        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.name), ["Timer - 10s"])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), ["Manual timer"])
        XCTAssertEqual(viewModel.timers.map(\.order), [0])
        XCTAssertNil(metadataStore.snapshot)
    }

    @MainActor
    func testOrphanedMetadataIsDroppedWhenNoTimersRestore() {
        let timerStore = InMemoryTimerPersistenceStore()
        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        let orphanID = UUID()
        metadataStore.saveSnapshot(
            PersistentTimerMetadataCollectionSnapshot(
                nextTimerOrder: 7,
                timers: [
                    PersistentTimerMetadataSnapshot(
                        id: orphanID,
                        order: 6,
                        name: "Orphan",
                        basisSummary: "Manual timer"
                    )
                ]
            )
        )

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertNil(metadataStore.snapshot)
    }

    @MainActor
    func testOrphanedMetadataIsFilteredOutWhenSomeTimersRestore() {
        let timerID = UUID()
        let orphanID = UUID()
        let timerStore = InMemoryTimerPersistenceStore()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 8,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 108),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    )
                ]
            )
        )

        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        metadataStore.saveSnapshot(
            PersistentTimerMetadataCollectionSnapshot(
                nextTimerOrder: 9,
                timers: [
                    PersistentTimerMetadataSnapshot(
                        id: timerID,
                        order: 3,
                        name: "Matched timer",
                        basisSummary: "Matched summary"
                    ),
                    PersistentTimerMetadataSnapshot(
                        id: orphanID,
                        order: 4,
                        name: "Orphan timer",
                        basisSummary: "Orphan summary"
                    )
                ]
            )
        )

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 102) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )

        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.name), ["Matched timer"])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), ["Matched summary"])
        XCTAssertEqual(metadataStore.snapshot?.timers.map(\.id), [timerID])
    }

    @MainActor
    func testRemovingLastTimerClearsPersistedTimerAndMetadataSnapshots() throws {
        let timerStore = InMemoryTimerPersistenceStore()
        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )

        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        XCTAssertNotNil(timerStore.snapshot)
        XCTAssertNotNil(metadataStore.snapshot)

        viewModel.removeTimer(id: id)

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertNil(timerStore.snapshot)
        XCTAssertNil(metadataStore.snapshot)
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
}

@MainActor
private final class LockScreenTimerTargetExposerSpy: LockScreenTimerTargetExposing {
    private(set) var exposedTargets: [LockScreenTimerTarget] = []
    private(set) var clearCount = 0
    private(set) var currentTarget: LockScreenTimerTarget?

    func expose(_ target: LockScreenTimerTarget) {
        currentTarget = target
        exposedTargets.append(target)
    }

    func clear() {
        currentTarget = nil
        clearCount += 1
    }
}

private final class InMemoryTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    private(set) var snapshot: PersistentTimerMetadataCollectionSnapshot?

    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

private final class InMemoryExposureCalculatorContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    private(set) var snapshot: PersistentExposureCalculatorContextSnapshot?

    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

private final class InMemoryTimerPersistenceStore: TimerPersistenceStoring {
    private(set) var snapshot: PersistentTimerCollectionSnapshot?

    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}
