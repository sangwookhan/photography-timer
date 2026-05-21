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
        viewModel.scaleMode = .fullStop

        XCTAssertNil(viewModel.activeCalculatorContext.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
        XCTAssertFalse(viewModel.canShowFilmDetails)
    }

    @MainActor
    func testSelectingPresetFilmUpdatesActiveCalculatorContextAndDisplayState() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

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
        let firstFilm = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        let replacementFilm = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" }
        )

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

        // Every preset row carries an ISO secondary. Films with a
        // registered unofficial practical profile (Portra 400 today)
        // surface as a second row that shares the canonical name and
        // ISO; `supportState` drives the unofficial badge. Spot-check
        // exemplars without coupling to the full catalog ordering.
        let portraOfficial = viewModel.filmSelectorEntries.first { entry in
            entry.primaryText == "Portra 400" && entry.profileOverride == nil
        }
        let portraUnofficial = viewModel.filmSelectorEntries.first { entry in
            entry.film?.id == "kodak-portra-400" && entry.profileOverride != nil
        }
        XCTAssertNotNil(portraOfficial, "Portra 400 official row should exist.")
        XCTAssertEqual(portraOfficial?.secondaryText, "ISO 400")
        XCTAssertEqual(portraOfficial?.supportState, .officialLimitedGuidance)
        XCTAssertNotNil(portraUnofficial, "Portra 400 unofficial row should exist with a profile override.")
        XCTAssertEqual(portraUnofficial?.primaryText, "Portra 400", "Unofficial row keeps the canonical name; the badge carries the qualifier.")
        XCTAssertEqual(portraUnofficial?.secondaryText, "ISO 400", "Unofficial row's right column is the ISO speed, not the qualifier.")
        XCTAssertEqual(portraUnofficial?.supportState, .unofficialPractical)
        XCTAssertNotNil(portraUnofficial?.profileOverride, "Unofficial row carries a profile override so the model can apply it on selection.")
        XCTAssertNotEqual(
            portraOfficial?.id,
            portraUnofficial?.id,
            "Official and unofficial rows must use distinct ids so scroll-to-selection lands on the correct variant."
        )

        let exemplars: [(name: String, expectedSecondary: String)] = [
            ("Tri-X 400", "ISO 400"),
            ("HP5 Plus", "ISO 400"),
            ("Velvia 50", "ISO 50"),
            ("Delta 3200", "ISO 3200"),
        ]
        for exemplar in exemplars {
            let entry = viewModel.filmSelectorEntries.first { entry in
                entry.primaryText == exemplar.name && entry.profileOverride == nil
            }
            XCTAssertNotNil(entry, "Missing selector entry for \(exemplar.name).")
            XCTAssertEqual(entry?.secondaryText, exemplar.expectedSecondary, "Secondary text mismatch for \(exemplar.name).")
        }
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
        viewModel.scaleMode = .fullStop

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
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Formula-derived")
        XCTAssertEqual(resultState.reciprocityState.tone, .measured)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.adjustedShutterAction.accessibilityLabel, "Start timer from adjusted shutter")
        XCTAssertEqual(resultState.adjustedShutterAction.accessibilityHint, "Starts a timer using the ND-adjusted shutter value")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        // Free log-log fit through Kodak's published 1/10/100 sec
        // rows lands within 1/50 stop of the published 2 sec
        // corrected exposure at Tm = 1 sec.
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 2, accuracy: 0.05)
        XCTAssertEqual(resultState.correctedExposureAction.targetSeconds ?? 0, 2, accuracy: 0.05)
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityHint, "Starts a timer using the film-specific corrected exposure value")
        XCTAssertEqual(resultState.correctedExposure.primaryText, "2s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 2, accuracy: 0.05)
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
        XCTAssertEqual(details.summary.badgeText, "Formula-derived")
        XCTAssertEqual(details.summary.summaryText, "Reference-backed formula prediction")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.title, "Adjusted Shutter")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "8s")
        XCTAssertNil(details.currentResult.adjustedShutter.detailText)
        XCTAssertEqual(details.currentResult.correctedExposure.title, "Corrected Exposure")
        // Free log-log fit at Tm = 8 sec predicts ≈ 36.2 sec; the
        // duration formatter rounds whole seconds for values >= 10 s.
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "36s")
        XCTAssertNil(details.currentResult.correctedExposure.detailText)
        XCTAssertTrue(details.currentResult.correctedExposure.emphasizesValue)
        XCTAssertEqual(details.sections.map(\.title), [
            "Source reference",
            "Sources",
        ])
        XCTAssertEqual(details.graph?.kind, .formula)
    }

    @MainActor
    func testFilmModeDetailsPrioritizeReferenceBeforeSources() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Source reference" }))
        let sourcesSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Sources" }))

        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.referenceBlock])
        // Each Tri-X 400 source-evidence row keeps the published
        // stop correction, the published corrected time, and the
        // published development hint so the user reads exactly what
        // Kodak prints in F-4017. The threshold row reconciles
        // Kodak's "1 sec" boundary by reading "< 1s" — the 1 sec
        // anchor itself is the start of the corrected range.
        XCTAssertEqual(referenceSection.rows.map(\.value), [
            """
            < 1s    No correction range
            1s      +1 stop · 2s           Dev -10%
            10s     +2 stops · 50s         Dev -20%
            100s    +3 stops · 1200s       Dev -30%
            """,
        ])
        XCTAssertEqual(details.summary.summaryText, "Reference-backed formula prediction")
        // Sources are now an unlabeled list (one row per item); the
        // legacy Reference / Citation sub-labels are gone.
        XCTAssertEqual(sourcesSection.rows.map(\.title), ["", ""])
        XCTAssertFalse(details.sections.flatMap(\.rows).map(\.title).contains("Basis"))
        XCTAssertFalse(details.sections.flatMap(\.rows).map(\.title).contains("Entry"))
        XCTAssertEqual(sourcesSection.rows.last?.destinationURL, nil)
        XCTAssertEqual(details.graph?.currentPoint?.style, .formulaDerived)
        XCTAssertEqual(details.graph?.caption, "Adjusted shutter vs corrected exposure on the active calculation curve")
        XCTAssertEqual(details.graph?.title, "Reciprocity Graph")
    }

    @MainActor
    func testFilmModeSourceReferenceShowsBothStopAndCorrectedTimeForKodakTMax100() throws {
        // Source reference panel rule for converted formula profiles:
        // when a row carries both a stop correction and a published
        // corrected time, show both. Kodak's T-MAX 100 publishes a
        // corrected time at 10 sec (15 sec) and 100 sec (200 sec) so
        // both rows render the combined "stop · corrected" column.
        // The 1 sec row publishes only the +1/3 stop delta, so the
        // catalog does not synthesize a corrected time — that row
        // shows the stop delta alone.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "T-MAX 100" })

        viewModel.baseShutter = 4
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Source reference" }))
        let referenceText = try XCTUnwrap(referenceSection.rows.first?.value)

        XCTAssertTrue(referenceText.contains("+0.5 stops · 15s"), "T-MAX 100 10s row must show '+0.5 stops · 15s'. Got:\n\(referenceText)")
        XCTAssertTrue(referenceText.contains("+1 stop · 200s"), "T-MAX 100 100s row must show '+1 stop · 200s'. Got:\n\(referenceText)")
        let oneSecLine = try XCTUnwrap(
            referenceText.split(separator: "\n").map(String.init).first(where: { line in
                let prefix = line.prefix(while: { !$0.isWhitespace })
                return prefix == "1s"
            }),
            "T-MAX 100 1s source-evidence row must surface in the Source reference block; got:\n\(referenceText)"
        )
        XCTAssertTrue(
            oneSecLine.contains("+0.33 stop"),
            "T-MAX 100 1s row must surface the published +1/3 stop delta; got: \(oneSecLine)"
        )
        XCTAssertFalse(
            oneSecLine.contains("·"),
            "T-MAX 100 1s row publishes stop delta only; the formatter must not synthesize a corrected-time column for it; got: \(oneSecLine)"
        )
    }

    @MainActor
    func testFilmModeSourceReferenceShowsFomaMultiplierAndExactCorrectedTimeWithoutApproximateMarker() throws {
        // FOMA's data sheet publishes only the multiplier ("lengthen
        // exposure 2x"). The catalog stores `metered × multiplier` as
        // the published corrected time — an exact-arithmetic
        // conversion, not a fractional-stop irrational, so the
        // presenter must NOT prefix it with "≈". The "≈" marker is
        // reserved for stopDelta-derived corrected times where the
        // conversion (metered × 2^stop) produces irrational values
        // that round on display. After conversion FOMA's published
        // multiplier rows live in the Source reference block alongside
        // the formula curve.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Source reference" }))
        let referenceText = try XCTUnwrap(referenceSection.rows.first?.value)

        XCTAssertTrue(referenceText.contains("2x · 2s"), "Fomapan 100 Classic 1s row must show multiplier + exact corrected time. Got:\n\(referenceText)")
        XCTAssertTrue(referenceText.contains("8x · 80s"), "Fomapan 100 Classic 10s row must show multiplier + exact corrected time. Got:\n\(referenceText)")
        XCTAssertFalse(referenceText.contains("· ≈"), "Multiplier-derived rows are exact-arithmetic conversions; no row should be marked approximate. Got:\n\(referenceText)")
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
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        XCTAssertEqual(details.sections.last?.title, "Sources")
        XCTAssertEqual(referenceSection.rows.map(\.title), [""])
        XCTAssertEqual(referenceSection.rows.map(\.style), [.referenceBlock])
        XCTAssertEqual(referenceSection.rows.map(\.value), ["1/10000s-1s    No correction"])
        XCTAssertEqual(details.summary.badgeText, "No quantified prediction")
        XCTAssertEqual(details.summary.summaryText, "Beyond published no-correction range")
        // Every case shares the same comparison-card layout now,
        // including this advisory-only path.
        XCTAssertEqual(details.currentResult.layout, .comparison)
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
        viewModel.scaleMode = .fullStop

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
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Formula-derived")
        XCTAssertEqual(resultState.reciprocityState.tone, .measured)
        // Converted formula profiles lead with the Source reference
        // section that pairs the threshold band with the published
        // source rows.
        XCTAssertEqual(details.sections.first?.title, "Source reference")
        XCTAssertEqual(
            resultState.adjustedShutterAction.targetSeconds ?? 0,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            resultState.correctedExposureAction.targetSeconds ?? 0,
            2,
            accuracy: 0.05
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
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 2
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let sourcesSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Sources" }))

        // Sources rows are unlabeled now; the row carrying the
        // citation text is the last entry and exposes the link via
        // its `destinationURL`.
        XCTAssertEqual(
            sourcesSection.rows.last?.destinationURL,
            URL(string: "https://example.com/reciprocity")
        )
    }

    @MainActor
    func testFilmModeDetailsShowFormulaNearReferenceGraphForFormulaProfile() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        // Formula and Profile metadata sections are gone; the
        // formula expression now lives next to the graph.
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
        XCTAssertFalse(details.sections.contains { $0.title == "Formula" })
        XCTAssertEqual(details.sections.map(\.title), ["Sources"])
        let formula = try XCTUnwrap(details.graph?.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.31")
        XCTAssertEqual(details.summary.badgeText, "Formula-derived")
        XCTAssertEqual(details.summary.summaryText, "Formula-based correction on the active curve")
        XCTAssertEqual(details.graph?.kind, .formula)
        XCTAssertEqual(details.graph?.currentPoint?.style, .formulaDerived)
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
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 8
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let formula = try XCTUnwrap(details.graph?.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.31")
        XCTAssertEqual(details.graph?.kind, .formula)
        XCTAssertEqual(details.graph?.currentPoint?.style, .formulaDerived)
        XCTAssertFalse(details.sections.contains { $0.title == "Formula" })
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
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
        XCTAssertEqual(graph.caption, "Adjusted shutter vs corrected exposure on the active calculation curve")
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
    func testFilmModeDetailsGraphSurfacesFormulaPredictionBeyondVelvia50SourceRange() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        _ = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        // Velvia 50's 64 s row is the formula's not-recommended
        // boundary. The result is unsupported-with-numeric (formula
        // extrapolated past the source range), so the current-point
        // marker plots at its real (64 s, ~120 s) position instead
        // of collapsing to an x-only guide.
        XCTAssertEqual(details.summary.badgeText, "Beyond source range")
        XCTAssertEqual(details.summary.summaryText, "Beyond source range")
        XCTAssertEqual(
            details.summary.detailText,
            "Current input is beyond the manufacturer source range. The corrected value is a formula prediction past the published reference."
        )
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "01:04")
        XCTAssertFalse(graph.usesCurrentInputGuideOnly)
        let currentPoint = try XCTUnwrap(graph.currentPoint)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 64, accuracy: 0.0001)
        XCTAssertEqual(currentPoint.point.correctedExposureSeconds, pow(64.0, 1.1821), accuracy: 0.5)
        XCTAssertEqual(graph.currentMeteredExposureSeconds ?? 0, 64, accuracy: 0.0001)
        XCTAssertNotNil(graph.supportedRangeUpperBoundSeconds)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("source range"),
            "Graph explanation must mention the source range for converted formula profiles; got: \(explanation)"
        )
        XCTAssertEqual(graph.notRecommendedBoundarySeconds ?? 0, 64, accuracy: 0.0001)
    }

    @MainActor
    func testFilmModeDetailsSummaryPromotesCurrentStateAboveSections() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 6
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(details.summary.badgeText, "Beyond source range")
        XCTAssertEqual(details.summary.summaryText, "Beyond source range")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "17:04")
        XCTAssertNotEqual(details.currentResult.correctedExposure.valueText, "No quantified prediction")
        XCTAssertEqual(details.sections.map(\.title), ["Source reference", "Sources"])
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
        viewModel.scaleMode = .fullStop

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
        // Profile + Formula metadata sections are no longer
        // rendered; the formula expression now lives next to the
        // graph and the film authority sits in the subtitle.
        let formula = try XCTUnwrap(details.graph?.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.34")
        XCTAssertEqual(details.summary.badgeText, "Formula-derived")
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
        XCTAssertFalse(details.sections.contains { $0.title == "Formula" })
        XCTAssertTrue(
            details.subtitle?.contains("Unofficial practical") == true,
            "Details subtitle must reuse the same 'Unofficial practical' label as the main film row so the surfaces agree: \(details.subtitle ?? "<nil>")"
        )
        XCTAssertNil(details.sections.first(where: { $0.title == "Sources" }),
                     "Unofficial profile with no verified source metadata must not show Sources section.")
    }

    @MainActor
    func testFilmModeDetailsOfficialPortra400ShowsOfficialAuthorityInSubtitle() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertTrue(
            details.subtitle?.contains("Official guidance") == true,
            "Authority is surfaced in the subtitle: \(details.subtitle ?? "<nil>")"
        )
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
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
    func testFilmModeDetailsUnofficialPortra400ShowsFormulaNearGraphWithoutProfileSection() throws {
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertNotNil(details.graph, "Formula profile must produce a graph.")
        let formula = try XCTUnwrap(details.graph?.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.34")
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
        XCTAssertFalse(details.sections.contains { $0.title == "Formula" })
        XCTAssertTrue(
            details.subtitle?.contains("Unofficial practical") == true,
            "Details subtitle must reuse the same 'Unofficial practical' label as the main film row: \(details.subtitle ?? "<nil>")"
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

    // MARK: - PTIMER-143 — Sub-second No correction for formula-only profiles

    @MainActor
    func testFilmModePortra400UnofficialSubSecondReturnsNoCorrectionAndPreservesCaveat() throws {
        // Portra 400 unofficial practical has only a formula rule
        // (Tc = Tm^1.34) with no `meteredRange` minimum and no
        // companion threshold rule. Without the policy-level default
        // no-correction handoff, an adjusted shutter of ~1/30 s would
        // produce a corrected exposure shorter than the adjusted
        // shutter — a reciprocity correction can never shorten the
        // exposure. The result must read as "No correction" while
        // keeping the unofficial-authority caveat visible.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" },
            "Unofficial Portra 400 selector entry must exist."
        )

        viewModel.baseShutter = 1.0 / 30.0   // 0.033 sec, well below 1s
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let binding = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(
            binding.policyResult.metadata.basis,
            .officialThresholdNoCorrection,
            "Sub-1s metered exposure on a formula-only profile must default to No correction."
        )

        let exposure = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let corrected = try XCTUnwrap(exposure.correctedExposure.correctedExposureSeconds)
        XCTAssertEqual(
            corrected,
            exposure.adjustedShutterSeconds,
            accuracy: 1e-6,
            "corrected exposure must equal adjusted shutter when policy returns No correction."
        )
        XCTAssertGreaterThanOrEqual(
            corrected,
            exposure.adjustedShutterSeconds - 1e-6,
            "corrected exposure must never be shorter than adjusted shutter."
        )

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(details.summary.badgeText, "No correction")
        XCTAssertEqual(details.currentResult.statusText, "No correction",
                       "Status is the calculation/policy state, not the graph viewport state.")

        // Caveat remains visible under Status.
        XCTAssertEqual(
            details.summary.detailText,
            "Unofficial practical approximation. Not a Kodak-published profile.",
            "Unofficial caveat must remain visible regardless of the sub-1s No correction handoff."
        )

        // Graph does not imply official Kodak source evidence.
        XCTAssertFalse(
            details.sections.contains { $0.title == "Source reference" },
            "Unofficial profile must not show a 'Source reference' section."
        )
        XCTAssertFalse(
            details.sections.contains { $0.title == "Guidance boundary" },
            "Unofficial profile must not show a 'Guidance boundary' section."
        )
        XCTAssertFalse(
            details.sections.contains { $0.title == "Sources" },
            "Unofficial profile with no publisher/citation must not show a 'Sources' section."
        )
        XCTAssertEqual(
            details.graph?.sourceReferenceMarkers.count ?? 0,
            0,
            "Unofficial profile must not render source-reference markers on the graph."
        )
        XCTAssertNil(
            details.graph?.notRecommendedBoundarySeconds,
            "Unofficial profile must not render a manufacturer not-recommended boundary."
        )
    }

    @MainActor
    func testFilmModePortra400UnofficialAboveOneSecondStillProducesFormulaPrediction() throws {
        // Sanity guard: the default no-correction handoff applies
        // strictly below 1s. Inputs at or above 1s flow through the
        // formula rule unchanged, preserving the prior PTIMER-143
        // behavior for the unofficial profile.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let binding = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(binding.policyResult.metadata.basis, .formulaDerived)
    }

    // MARK: - PTIMER-143 — No-correction graph visibility

    @MainActor
    func testFilmModePortra400UnofficialSubSecondGraphShowsNoCorrectionRegion() throws {
        // After the policy default-handoff sends Portra 400
        // unofficial sub-1s inputs to No correction, the Details
        // graph must visibly show that no-correction state — the
        // viewport expands below 1 s so the current point lands
        // inside the plot and the no-correction overlay renders
        // up to the synthesized 1 s default upper bound.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertLessThan(
            graph.xRange.lowerBound,
            1.0,
            "Sub-second no-correction graph must expand its lower bound below 1 s so the no-correction region is visible."
        )
        XCTAssertEqual(
            graph.noCorrectionRangeUpperBoundSeconds,
            1.0,
            "Formula-only unofficial profile must surface the policy's default 1 s no-correction upper bound so the green overlay renders."
        )
        XCTAssertFalse(
            graph.isBelowVisibleRange,
            "Sub-second current input must sit inside the expanded visible range, not below it."
        )
        XCTAssertNotNil(
            graph.currentPoint,
            "The current point must remain plotted so the user can read the No correction state on the graph."
        )
        XCTAssertEqual(graph.currentPoint?.style, .noCorrection)
    }

    @MainActor
    func testFilmModeTMax100SubSecondGraphShowsNoCorrectionRegion() throws {
        // T-MAX 100's published no-correction threshold runs from
        // 1/1000 s to 1/10 s. Sub-1/10 s inputs must produce a
        // graph whose viewport extends below 1 s so the published
        // no-correction band reads as a visible region instead of
        // collapsing onto the left edge.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "T-MAX 100" })

        viewModel.baseShutter = 1.0 / 60.0      // 0.0167 s, inside T-MAX 100's 1/1000…1/10 s no-correction range
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertLessThan(graph.xRange.lowerBound, 0.1,
                          "Viewport must expand below T-MAX 100's 1/10 s no-correction upper bound so the band is visible.")
        let upper = try XCTUnwrap(graph.noCorrectionRangeUpperBoundSeconds)
        XCTAssertEqual(upper, 0.1, accuracy: 1e-6,
                       "T-MAX 100's published no-correction range ends at 1/10 s.")
        XCTAssertGreaterThan(upper, graph.xRange.lowerBound,
                             "Published no-correction upper bound must sit above the viewport's lower bound so the overlay has a visible width.")
        XCTAssertFalse(graph.isBelowVisibleRange)
        XCTAssertEqual(graph.currentPoint?.style, .noCorrection)
    }

    @MainActor
    func testFilmModeHP5PlusSubSecondGraphShowsNoCorrectionRegion() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })

        viewModel.baseShutter = 0.25            // 1/4 s
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertLessThan(graph.xRange.lowerBound, 1.0)
        XCTAssertEqual(graph.noCorrectionRangeUpperBoundSeconds ?? 0, 1.0, accuracy: 1e-6)
        XCTAssertFalse(graph.isBelowVisibleRange)
        XCTAssertEqual(graph.currentPoint?.style, .noCorrection)
    }

    @MainActor
    func testFilmModeProvia100FSubSecondGraphShowsNoCorrectionRegion() throws {
        // Provia 100F's published threshold extends to 128 s. The
        // stable viewport extends below 1 s so a sub-1 s input
        // lands inside the plot and the no-correction overlay
        // (128 s upper bound) renders end-to-end.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Provia 100F" })

        viewModel.baseShutter = 0.5
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        XCTAssertLessThan(graph.xRange.lowerBound, 1.0)
        XCTAssertGreaterThanOrEqual(graph.noCorrectionRangeUpperBoundSeconds ?? 0, 128)
        XCTAssertFalse(graph.isBelowVisibleRange)
        XCTAssertEqual(graph.currentPoint?.style, .noCorrection)
    }

    @MainActor
    func testFilmModeFormulaGraphViewportIsStableAcrossInputsWithinSameTier() throws {
        // Stable viewport contract: same profile + same scale tier
        // produces the same graph frame regardless of where the
        // current input lands. Only the current-result marker
        // moves between sub-second, near-1 s, and long-exposure
        // inputs. T-MAX 100 across 1/60 s (No correction), 1 s
        // (handoff edge), and 30 s (formula-derived) must share
        // identical xRange / yRange.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "T-MAX 100" })
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 1.0 / 60.0
        let subSecondFrame = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)

        viewModel.baseShutter = 1
        let oneSecondFrame = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)

        viewModel.baseShutter = 30
        let longFrame = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)

        XCTAssertEqual(subSecondFrame.xRange, oneSecondFrame.xRange,
                       "Sub-1 s and 1 s inputs on T-MAX 100 must share the same xRange (only the marker moves).")
        XCTAssertEqual(subSecondFrame.xRange, longFrame.xRange,
                       "Sub-1 s and 30 s inputs on T-MAX 100 must share the same xRange (only the marker moves).")
        XCTAssertEqual(subSecondFrame.yRange, longFrame.yRange,
                       "yRange must also stay stable across inputs within the same scale tier.")
        XCTAssertEqual(subSecondFrame.scaleTier, longFrame.scaleTier)
        XCTAssertLessThan(subSecondFrame.xRange.lowerBound, 1.0,
                          "Stable lower bound must sit below 1 s so the no-correction band always reads as visible.")
    }

    @MainActor
    func testFilmModePortra400UnofficialFrameIsStableAcrossSubSecondNearOneSecondAndLongInputs() throws {
        // Spec: "0.033 s, 1.1 s, 17 s on the same profile must use
        // the same graph frame; current result marker only moves."
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        viewModel.baseShutter = 1.0 / 30.0
        let subSecondFrame = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)

        viewModel.baseShutter = 1.1
        let nearOneSecondFrame = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)

        viewModel.baseShutter = 17
        let longFrame = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)

        XCTAssertEqual(subSecondFrame.xRange, nearOneSecondFrame.xRange)
        XCTAssertEqual(subSecondFrame.xRange, longFrame.xRange)
        XCTAssertEqual(subSecondFrame.yRange, longFrame.yRange)

        // Sub-second marker sits inside the visible no-correction
        // band, not below the plot.
        XCTAssertFalse(subSecondFrame.isBelowVisibleRange)
        let subSecondPoint = try XCTUnwrap(subSecondFrame.currentPoint)
        let bandUpper = try XCTUnwrap(subSecondFrame.noCorrectionRangeUpperBoundSeconds)
        XCTAssertLessThanOrEqual(subSecondPoint.point.meteredExposureSeconds, bandUpper,
                                 "Sub-second current point must sit inside the no-correction band.")
        XCTAssertEqual(subSecondPoint.style, .noCorrection)

        // Near-1 s and long inputs sit on the formula segment.
        XCTAssertEqual(nearOneSecondFrame.currentPoint?.style, .formulaDerived)
        XCTAssertEqual(longFrame.currentPoint?.style, .formulaDerived)
    }

    @MainActor
    func testFilmModePortra400UnofficialCalculationCurveJoinsIdentityAndFormulaSegments() throws {
        // The calculation curve must include an identity segment
        // (Tc = Tm) through the no-correction zone and the formula
        // segment past the threshold, with no visual gap at the
        // handoff. For Portra 400 unofficial (Tc = Tm^1.34), the
        // identity samples sit on the y = x line up to 1 s, and at
        // least one formula sample beyond 1 s lifts above it.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let graph = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)
        let threshold = try XCTUnwrap(graph.noCorrectionRangeUpperBoundSeconds)

        let identitySamples = graph.sourcePoints.filter { $0.meteredExposureSeconds <= threshold + 1e-6 }
        XCTAssertFalse(identitySamples.isEmpty,
                       "Calculation curve must include identity samples through the no-correction zone.")
        for sample in identitySamples {
            XCTAssertEqual(
                sample.correctedExposureSeconds,
                sample.meteredExposureSeconds,
                accuracy: 1e-6,
                "Identity-segment samples must satisfy corrected == metered."
            )
        }

        let pastThreshold = graph.sourcePoints.first(where: { $0.meteredExposureSeconds > threshold + 1e-3 })
        let predicted = try XCTUnwrap(pastThreshold,
                                      "Calculation curve must include at least one formula sample past the threshold.")
        XCTAssertGreaterThan(predicted.correctedExposureSeconds, predicted.meteredExposureSeconds,
                             "Formula segment must lift above the identity line for a profile with P > 1.")
    }

    @MainActor
    func testFilmModeFormulaGraphLegendUsesCalculationCurveLabel() throws {
        // The source path spans identity + formula, so the legend
        // chip reads "Calculation curve" — the user-facing curve
        // label on every formula-graph path.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "T-MAX 100" })
        viewModel.baseShutter = 30
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let graph = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph)
        XCTAssertTrue(
            graph.legendChipLabels.contains("Calculation curve"),
            "Formula graph legend must surface 'Calculation curve' as the curve label: \(graph.legendChipLabels)"
        )
        XCTAssertFalse(
            graph.legendChipLabels.contains("Formula curve"),
            "Legend must not surface 'Formula curve' as a user-visible label: \(graph.legendChipLabels)"
        )
    }

    @MainActor
    func testFilmModeFormulaGraphLegendShowsCalculationCurveAcrossProfileAuthorities() throws {
        // The "Calculation curve" wording must surface consistently
        // for every formula-graph profile authority: official
        // converted formula (Provia 100F, T-MAX 100), source-less
        // official formula (HP5 Plus), and unofficial practical
        // (Portra 400 unofficial). Official limited-guidance
        // profiles (Portra 400 official) produce no formula graph
        // and are excluded from this loop.
        let viewModel = makeViewModel()
        viewModel.ndStop = 0

        let formulaGraphFilmCases: [(name: String, baseShutter: Double, selectsUnofficial: Bool)] = [
            ("Provia 100F", 60, false),
            ("T-MAX 100", 30, false),
            ("HP5 Plus", 30, false),
            ("Portra 400", 10, true)
        ]
        for caseInfo in formulaGraphFilmCases {
            if caseInfo.selectsUnofficial {
                let entry = try XCTUnwrap(
                    viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == caseInfo.name }
                )
                viewModel.baseShutter = caseInfo.baseShutter
                viewModel.selectEntry(entry)
            } else {
                let film = try XCTUnwrap(
                    viewModel.availablePresetFilms.first { $0.canonicalStockName == caseInfo.name }
                )
                viewModel.baseShutter = caseInfo.baseShutter
                viewModel.selectPresetFilm(film)
            }

            let graph = try XCTUnwrap(viewModel.filmModeDetailsDisplayState?.graph,
                                      "\(caseInfo.name) must produce a formula graph for this assertion.")
            XCTAssertTrue(
                graph.legendChipLabels.contains("Calculation curve"),
                "[\(caseInfo.name)] legend must surface 'Calculation curve': \(graph.legendChipLabels)"
            )
            XCTAssertFalse(
                graph.legendChipLabels.contains("Formula curve"),
                "[\(caseInfo.name)] legend must not surface 'Formula curve' as a user-visible label: \(graph.legendChipLabels)"
            )
        }
    }

    // MARK: - PTIMER-143 — Normalize Film Details for unofficial reciprocity profiles

    @MainActor
    func testFilmModeDetailsUnofficialPortra400SubtitleMatchesMainRowAuthorityLabel() throws {
        // The main film row already labels unofficial Portra 400 as
        // "Unofficial practical" (via `FilmSelectionModel.filmRowAuthorityLabel`).
        // The Details subtitle must reuse the same wording so the user
        // does not read one label on the main row and a different label
        // for the same selected profile inside the sheet.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" },
            "Unofficial Portra 400 selector entry must exist."
        )

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let mainRowLabel = try XCTUnwrap(
            viewModel.filmSelectionDisplayState.secondaryText,
            "Unofficial Portra 400 must show a main-row authority label."
        )
        XCTAssertEqual(mainRowLabel, "Unofficial practical")

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let subtitle = try XCTUnwrap(details.subtitle)
        XCTAssertTrue(
            subtitle.contains(mainRowLabel),
            "Details subtitle '\(subtitle)' must contain the same authority label as the main row '\(mainRowLabel)'."
        )
        XCTAssertFalse(
            subtitle.contains("Official"),
            "Details subtitle for the unofficial profile must not surface any 'Official' wording: '\(subtitle)'."
        )
    }

    @MainActor
    func testFilmModeDetailsUnofficialPortra400SurfacesAuthorityCaveatNote() throws {
        // The unofficial Portra 400 profile carries an explicit
        // authority caveat in its profile-level notes
        // ("Unofficial practical approximation. Not a Kodak-published profile.").
        // That caveat must be visible in the Details sheet so the user
        // can recognize the lower-authority status before trusting the
        // predicted corrected exposure.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let detailTexts = collectDisplayedDetailsText(details)
        XCTAssertTrue(
            detailTexts.contains(where: { $0.contains("Not a Kodak-published profile") }),
            "Details must surface the unofficial authority caveat. Collected texts: \(detailTexts)"
        )
    }

    @MainActor
    func testFilmModeDetailsUnofficialPortra400DoesNotUseOfficialSourceWording() throws {
        // Authority-leak guard: the unofficial profile path must not
        // borrow wording that exists only for manufacturer-published
        // (converted formula) profiles. "Beyond source range",
        // "Reference-backed formula prediction", "manufacturer source
        // range", and the "Source reference" / "Guidance boundary"
        // sections all imply a published Kodak source-range, which the
        // unofficial profile does not have.
        let viewModel = makeViewModel()
        let unofficialEntry = try XCTUnwrap(
            viewModel.filmSelectorEntries.first { $0.profileOverride != nil && $0.film?.canonicalStockName == "Portra 400" }
        )

        viewModel.baseShutter = 30
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        let forbiddenWording = [
            "Beyond source range",
            "Reference-backed formula prediction",
            "manufacturer source range",
            "manufacturer-supported boundary",
            "published source range",
            "published reference"
        ]
        let allText = collectDisplayedDetailsText(details).joined(separator: "\n")
        for fragment in forbiddenWording {
            XCTAssertFalse(
                allText.contains(fragment),
                "Unofficial Portra 400 Details must not use '\(fragment)' wording (would imply a manufacturer-published source). Collected text:\n\(allText)"
            )
        }

        // Section-title guard: the source-evidence section titles are
        // reserved for converted formula profiles that carry published
        // source rows. The unofficial profile carries no `sourceEvidence`
        // and must produce neither title.
        let sectionTitles = details.sections.map(\.title)
        XCTAssertFalse(
            sectionTitles.contains("Source reference"),
            "Unofficial profile must not render a 'Source reference' section: \(sectionTitles)"
        )
        XCTAssertFalse(
            sectionTitles.contains("Guidance boundary"),
            "Unofficial profile must not render a 'Guidance boundary' section: \(sectionTitles)"
        )
    }

    @MainActor
    func testFilmModeDetailsOfficialPortra400KeepsOfficialLimitedGuidanceBeyondThreshold() throws {
        // The official Portra 400 profile must remain the default
        // official limited-guidance profile and must not expose any
        // quantified prediction beyond the published 1 s threshold.
        let viewModel = makeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 8       // metered exposure well beyond the 1 s no-correction threshold
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(officialFilm)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let subtitle = try XCTUnwrap(details.subtitle)
        XCTAssertTrue(
            subtitle.contains("Official guidance"),
            "Official Portra 400 subtitle must keep its 'Official guidance' label: \(subtitle)"
        )
        XCTAssertEqual(details.summary.badgeText, "No quantified prediction")

        let binding = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertNil(
            binding.policyResult.correctedExposureSeconds,
            "Official Portra 400 must not produce a quantified corrected exposure beyond the official threshold."
        )
    }

    @MainActor
    func testFilmModeDetailsConvertedFormulaProfilesStillShowSourceRangeWordingBeyondSupportedBound() throws {
        // Regression guard for the converted formula profiles
        // (Provia 100F, Tri-X 400, T-MAX 100, T-MAX 400, Velvia 50,
        // Velvia 100, Acros II): an input beyond their supported range
        // must still produce "Beyond source range" wording, which is
        // the converted-formula-profile vocabulary established by
        // PTIMER-128 / PTIMER-129. The unofficial-profile changes
        // must not regress this.
        let convertedFormulaStockNames = [
            "Provia 100F",
            "Tri-X 400",
            "T-MAX 100",
            "T-MAX 400",
            "Velvia 50",
            "Velvia 100",
            "Acros II"
        ]
        for stockName in convertedFormulaStockNames {
            let viewModel = makeViewModel()
            // A missing catalog entry is a real regression — a
            // silent `continue` would hide a converted formula
            // profile that disappeared from the launch catalog. The
            // assertion fails the test instead so PTIMER-134 /
            // PTIMER-135 coverage stays honest.
            let film = try XCTUnwrap(
                viewModel.availablePresetFilms.first(where: { $0.canonicalStockName == stockName }),
                "Converted formula profile '\(stockName)' must remain in the launch catalog."
            )
            viewModel.baseShutter = 4_000     // pushed past every converted formula's supported bound
            viewModel.ndStop = 0
            viewModel.selectPresetFilm(film)

            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState, "Missing details for \(stockName)")
            XCTAssertEqual(
                details.summary.badgeText,
                "Beyond source range",
                "Converted formula profile '\(stockName)' must still surface 'Beyond source range' wording past its supported bound."
            )
        }
    }

    /// Collects every user-visible text fragment from the Details
    /// display state so the assertions above can scan for forbidden /
    /// required wording without coupling to a single field.
    @MainActor
    private func collectDisplayedDetailsText(_ details: FilmModeDetailsDisplayState) -> [String] {
        var texts: [String] = []
        texts.append(details.title)
        if let subtitle = details.subtitle { texts.append(subtitle) }
        texts.append(details.summary.badgeText)
        texts.append(details.summary.summaryText)
        if let detail = details.summary.detailText { texts.append(detail) }
        texts.append(details.currentResult.statusText)
        texts.append(details.currentResult.adjustedShutter.title)
        texts.append(details.currentResult.adjustedShutter.valueText)
        if let detail = details.currentResult.adjustedShutter.detailText { texts.append(detail) }
        texts.append(details.currentResult.correctedExposure.title)
        texts.append(details.currentResult.correctedExposure.valueText)
        if let detail = details.currentResult.correctedExposure.detailText { texts.append(detail) }
        for section in details.sections {
            texts.append(section.title)
            for row in section.rows {
                texts.append(row.title)
                texts.append(row.value)
            }
        }
        if let graph = details.graph {
            texts.append(graph.title)
            texts.append(graph.caption)
            if let note = graph.unsupportedExplanation { texts.append(note) }
            texts.append(contentsOf: graph.descriptionLines)
            if let formula = graph.formulaDisplayText { texts.append(formula) }
        }
        if let legend = details.legend {
            texts.append(contentsOf: legend.lines)
        }
        return texts.filter { !$0.isEmpty }
    }

    @MainActor
    func testFilmModeDetailsSectionOrderIsConsistentAcrossOfficialAndUnofficialPortra400() throws {
        // Profile / Formula metadata sections are removed in this
        // pass; the only stable invariant is that Sources, when
        // present, is the last section in the array.
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
            XCTAssertFalse(
                details.sections.contains { $0.title == "Profile" },
                "[\(label)] Profile metadata section must no longer appear in sections."
            )
            XCTAssertFalse(
                details.sections.contains { $0.title == "Formula" },
                "[\(label)] Formula metadata section must no longer appear in sections."
            )
            if let sourcesIndex = details.sections.firstIndex(where: { $0.title == "Sources" }) {
                XCTAssertEqual(
                    sourcesIndex,
                    details.sections.count - 1,
                    "[\(label)] Sources must be the last section when present."
                )
            }
        }
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
    func testTriXAtOneSecondReturnsCorrectedExposureFromFormulaPrediction() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Formula-derived")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 2, accuracy: 0.05)
        XCTAssertEqual(resultState.correctedExposure.primaryText, "2s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 2, accuracy: 0.05)
    }

    @MainActor
    func testCorrectedExposureNumericDisplayUsesRestoredTimeFormatting() throws {
        // CHS 100 II's 2024 published rows top out at 15 sec, so 8 sec
        // is firmly inside its formula domain. A converted formula
        // profile inside its source range does not prefix the numeric
        // corrected exposure with "≈" — that marker is reserved for
        // outside-guidance numeric continuations.
        let viewModel = makeViewModel()
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
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
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
        let viewModel = makeViewModel()
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
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 5
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(resultState.correctedExposure.primaryText, "14s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.title, "Adjusted Shutter")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "4s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "14s")
    }

    @MainActor
    func testNoCorrectionDetailsUseSharedComparisonLayoutAndPlotIdentityCurrentPoint() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertEqual(details.summary.badgeText, "No correction")
        XCTAssertEqual(details.summary.summaryText, "No correction at 0.5s")
        // No-correction now shares the comparison layout with every
        // other case; the legacy `compactValue` variant is gone.
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "0.5s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "0.5s")
        XCTAssertEqual(details.currentResult.statusText, "No correction")
        // No-correction current point sits on the identity line with
        // the `.noCorrection` marker so it does not read as a formula
        // prediction.
        let currentPoint = try XCTUnwrap(details.graph?.currentPoint)
        XCTAssertEqual(currentPoint.style, .noCorrection)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 0.5, accuracy: 1e-6)
        XCTAssertEqual(currentPoint.point.correctedExposureSeconds, 0.5, accuracy: 1e-6)
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
    func testTriXBeyondSourceRangeKeepsFormulaPredictionAsQuantifiedResult() throws {
        let viewModel = makeViewModel()
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(bindingState.presentation.category, .unsupported)
        XCTAssertTrue(bindingState.profile.isConvertedFormulaProfile)
    }

    @MainActor
    func testTriXVeryLongExposureStaysBeyondSourceRangeWithFormulaContinuation() throws {
        let viewModel = makeViewModel()
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .unsupportedOutOfPolicyRange)
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
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Formula-derived")
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
        XCTAssertEqual(resultState.reciprocityState.badgeText, "No quantified prediction")
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "No official quantified prediction is available for this metered exposure.")
        XCTAssertFalse(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.policyResult.metadata.basis, .advisoryOnlyBeyondOfficialRange)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertFalse(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmModeBeyondVelvia50SourceRangeKeepsCorrectedExposureRowQuantifiedFromFormula() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        // Velvia 50's 64 s row is the formula's not-recommended
        // boundary. The formula keeps producing a numeric corrected
        // exposure past the published source range, so the
        // corrected-exposure card surfaces the predicted value and
        // the Play button enables.
        let expectedCorrected = pow(64.0, 1.1821)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 64, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Beyond source range")
        XCTAssertEqual(resultState.reciprocityState.tone, .unsupported)
        XCTAssertEqual(resultState.adjustedShutterAction.targetSeconds ?? 0, 64, accuracy: 0.0001)
        XCTAssertTrue(resultState.adjustedShutterAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(
            resultState.correctedExposure.correctedExposureSeconds ?? 0,
            expectedCorrected,
            accuracy: 0.5
        )
        XCTAssertEqual(
            resultState.correctedExposureAction.targetSeconds ?? 0,
            expectedCorrected,
            accuracy: 0.5
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
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.presentation.category, .unsupported)
        XCTAssertTrue(bindingState.profile.isConvertedFormulaProfile)
        XCTAssertNotNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertTrue(viewModel.canStartFilmAdjustedShutterTimer)
        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
    }

    @MainActor
    func testFilmSelectorSectionsGroupByManufacturerWithNoFilmAsHeaderlessLeadingSection() throws {
        let viewModel = makeViewModel()
        let sections = viewModel.filmSelectorSections

        // The leading section is the "No film" sentinel — headerless
        // (manufacturer == nil) so the view renders it as a plain row
        // outside any group card. Every subsequent section is a
        // manufacturer group card.
        let leading = try XCTUnwrap(sections.first, "Sections must not be empty.")
        XCTAssertEqual(leading.id, "no-film")
        XCTAssertNil(leading.manufacturer)
        XCTAssertEqual(leading.entries.map(\.primaryText), ["No film"])

        let manufacturerSections = Array(sections.dropFirst())
        XCTAssertFalse(manufacturerSections.isEmpty, "Catalog should produce at least one manufacturer section.")

        // No section has zero entries.
        for section in sections {
            XCTAssertFalse(section.entries.isEmpty, "Section '\(section.id)' must not be empty.")
        }

        // Every manufacturer section's entries share its manufacturer label.
        for section in manufacturerSections {
            let manufacturer = try XCTUnwrap(section.manufacturer, "Non-leading section must have a manufacturer.")
            XCTAssertEqual(section.id, manufacturer)
            for entry in section.entries {
                XCTAssertEqual(
                    entry.manufacturer,
                    manufacturer,
                    "Entry '\(entry.primaryText)' is in the '\(manufacturer)' section but reports manufacturer '\(entry.manufacturer ?? "nil")'."
                )
            }
        }

        // Manufacturers appear in alphabetical order (case-insensitive)
        // so the grouped cards are predictably ordered.
        let manufacturers = manufacturerSections.compactMap(\.manufacturer)
        let sortedManufacturers = manufacturers.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        XCTAssertEqual(manufacturers, sortedManufacturers)

        // The flattened section entries must match the flat
        // filmSelectorEntries list — sections are a regrouping, not a
        // filtered view, so scroll-to-current-selection by entry id
        // works regardless of which property the view consumes.
        XCTAssertEqual(
            sections.flatMap(\.entries).map(\.id),
            viewModel.filmSelectorEntries.map(\.id)
        )

        // Spot-check: Portra 400 official and unofficial rows live in the
        // same Kodak section, contiguously, so the user does not have to
        // hunt for the unofficial variant elsewhere in the list.
        let kodakSection = try XCTUnwrap(
            manufacturerSections.first(where: { $0.manufacturer == "Kodak" }),
            "Kodak manufacturer section is required."
        )
        let portraIndices = kodakSection.entries.enumerated().compactMap { idx, entry in
            entry.primaryText.hasPrefix("Portra 400") ? idx : nil
        }
        XCTAssertEqual(portraIndices.count, 2, "Kodak section should contain official + unofficial Portra 400 rows.")
        if portraIndices.count == 2 {
            XCTAssertEqual(portraIndices[1] - portraIndices[0], 1, "Official and unofficial Portra 400 rows must be contiguous in the Kodak section.")
        }
    }

    @MainActor
    func testFilmSelectorEntriesKeepNoFilmFirstAndShowISOWhenAvailable() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.id, "no-film")
        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)

        // The leading "No film" sentinel must precede every preset film entry.
        // Preset films carry an inferred ISO secondary when the canonical
        // name / brand label / aliases contain a recognized speed token, and
        // films registered in UnofficialPracticalProfiles add an "Unofficial"
        // secondary alongside their official primary entry.
        let entriesAfterNoFilm = viewModel.filmSelectorEntries.dropFirst()
        XCTAssertGreaterThanOrEqual(entriesAfterNoFilm.count, viewModel.availablePresetFilms.count)
        for entry in entriesAfterNoFilm {
            if let secondary = entry.secondaryText {
                XCTAssertTrue(
                    secondary.hasPrefix("ISO ") || secondary == "Unofficial",
                    "Selector secondary text '\(secondary)' for '\(entry.primaryText)' must be ISO metadata or 'Unofficial'."
                )
            }
        }
    }

    private func fallbackFormulaDetailsFilm() -> FilmIdentity {
        FilmIdentity(
            id: "fallback-formula-film",
            kind: .preset,
            canonicalStockName: "Fallback Formula 400",
            manufacturer: "Fallback",
            brandLabel: nil,
            aliases: [],
            iso: 100,
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
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        // Pin the legacy full-stop scale so the snap-style assertions
        // in this suite stay green; the shipping calculator now
        // defaults to the one-third-stop scale (per
        // docs/specs/Calculator.md §1.4) and a separate suite covers
        // the new shipping behavior.
        viewModel.scaleMode = .fullStop
        return viewModel
    }

    private func minimalDetailsFilm() -> FilmIdentity {
        FilmIdentity(
            id: "minimal-details-film",
            kind: .preset,
            canonicalStockName: "Minimal 100",
            manufacturer: "Minimal",
            brandLabel: nil,
            aliases: [],
            iso: 100,
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
            iso: 100,
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
