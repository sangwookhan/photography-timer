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

        // Every preset row carries an ISO secondary. Films that ship a
        // registered unofficial practical profile (Portra 400 today) are
        // surfaced as a second row whose primary text appends " · Unofficial"
        // — the qualifier lives on the left because it describes the
        // profile, not the ISO. Spot-check exemplars across batches without
        // coupling to the full launch-catalog ordering.
        let portraOfficial = viewModel.filmSelectorEntries.first { entry in
            entry.primaryText == "Portra 400" && entry.profileOverride == nil
        }
        let portraUnofficial = viewModel.filmSelectorEntries.first { entry in
            entry.primaryText == "Portra 400 · Unofficial"
        }
        XCTAssertNotNil(portraOfficial, "Portra 400 official row should exist.")
        XCTAssertEqual(portraOfficial?.secondaryText, "ISO 400")
        XCTAssertNotNil(portraUnofficial, "Portra 400 unofficial row should exist with the · Unofficial suffix.")
        XCTAssertEqual(portraUnofficial?.secondaryText, "ISO 400", "Unofficial row's right column is the ISO speed, not the qualifier.")
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
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposureAction.targetSeconds ?? 0, 2, accuracy: 0.0001)
        XCTAssertTrue(resultState.correctedExposureAction.canStartTimer)
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityLabel, "Start timer from corrected exposure")
        XCTAssertEqual(resultState.correctedExposureAction.accessibilityHint, "Starts a timer using the film-specific corrected exposure value")
        XCTAssertEqual(resultState.correctedExposure.primaryText, "2s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 2, accuracy: 0.0001)
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
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "37s")
        XCTAssertNil(details.currentResult.correctedExposure.detailText)
        XCTAssertTrue(details.currentResult.correctedExposure.emphasizesValue)
        XCTAssertEqual(details.sections.map(\.title), [
            "Profile",
            "Reference",
            "Sources"
        ])
        XCTAssertEqual(details.graph?.kind, .table)
        XCTAssertEqual(details.sections.first?.rows.map(\.title), ["Method", "Authority"])
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
        // Each TRI-X 400 row in the Reference panel keeps both the
        // published stop correction and the published adjusted time
        // alongside its development hint, so the user sees what the
        // source actually says rather than only one fact per row.
        XCTAssertEqual(referenceSection.rows.map(\.value), [
            """
            <= 1s    No correction
            1s       +1 stop · 2s        Dev -10%
            10s      +2 stops · 50s      Dev -20%
            100s     +3 stops · 1200s    Dev -30%
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
    func testFilmModeReferenceShowsBothStopAndCorrectedTimeForKodakTMax100() throws {
        // Reference panel rule: when a row carries both a stop
        // correction and an adjusted/corrected time, show both —
        // neither half of the source publication should be hidden by
        // a "first match wins" formatter. T-MAX 100 1s carries a
        // catalog-derived corrected time (the source publishes only
        // the +1/3 stop), so the formatter renders it with an "≈"
        // prefix to distinguish it from published values like the
        // 15s at 10 sec or 200s at 100 sec.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "T-MAX 100" })

        viewModel.baseShutter = 4
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let referenceText = try XCTUnwrap(referenceSection.rows.first?.value)

        // Source-published anchors keep their corrected time without
        // an "≈" marker. The existing app style renders stop deltas as
        // decimals (e.g. "+0.5 stops") rather than fractions, so the
        // combined column reads "<stop> · <time>" using that style.
        XCTAssertTrue(referenceText.contains("+0.5 stops · 15s"), "T-MAX 100 10s row must show '+0.5 stops · 15s'. Got:\n\(referenceText)")
        XCTAssertTrue(referenceText.contains("+1 stop · 200s"), "T-MAX 100 100s row must show '+1 stop · 200s'. Got:\n\(referenceText)")
        // The 1s row's corrected time was derived from +0.33 stops
        // (the policy-compatible logLog anchoring fix), so it must
        // read with the approximate marker.
        XCTAssertTrue(referenceText.contains("+0.33 stops · ≈"), "T-MAX 100 1s row must mark its derived corrected time with '≈'. Got:\n\(referenceText)")
    }

    @MainActor
    func testFilmModeReferenceShowsFomaMultiplierAndExactCorrectedTimeWithoutApproximateMarker() throws {
        // FOMA's data sheet publishes only the multiplier ("lengthen
        // exposure 2x"). The catalog stores `metered × multiplier` as
        // a corrected time so the policy can interpolate the table —
        // but that conversion is exact arithmetic, not a fractional-
        // stop irrational, so the presenter must NOT prefix it with
        // "≈". The "≈" marker is reserved for stopDelta-derived
        // corrected times where the conversion (metered × 2^stop)
        // produces irrational values that round on display.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })

        viewModel.baseShutter = 1
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let referenceText = try XCTUnwrap(referenceSection.rows.first?.value)

        XCTAssertTrue(referenceText.contains("2x · 2s"), "Fomapan 100 Classic 1s row must show multiplier + exact corrected time. Got:\n\(referenceText)")
        XCTAssertTrue(referenceText.contains("8x · 80s"), "Fomapan 100 Classic 10s row must show multiplier + exact corrected time. Got:\n\(referenceText)")
        XCTAssertFalse(referenceText.contains("· ≈"), "Multiplier-derived rows are exact-arithmetic conversions; no row should be marked approximate. Got:\n\(referenceText)")
    }

    @MainActor
    func testFilmModeReferenceShowsBothStopAndPublishedCorrectedTimeForAdoxChs100II() throws {
        // ADOX publishes both the multiplier and the explicit
        // corrected time ("2 sec → 1.5x (3 sec)"), so neither value
        // is approximate. The Reference row must show both without
        // any "≈" marker.
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "CHS 100 II" })

        viewModel.baseShutter = 4
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let referenceSection = try XCTUnwrap(details.sections.first(where: { $0.title == "Reference" }))
        let referenceText = try XCTUnwrap(referenceSection.rows.first?.value)

        XCTAssertTrue(referenceText.contains("2x · 8s"), "CHS 100 II 4s row must show '2x · 8s' with no approximate marker. Got:\n\(referenceText)")
        XCTAssertFalse(referenceText.contains("· ≈"), "CHS 100 II rows have source-published corrected times; no row should be marked approximate. Got:\n\(referenceText)")
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
            2,
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
        XCTAssertEqual(graph.currentPoint?.point.correctedExposureSeconds ?? 0, 13.8890884987, accuracy: 0.0001)
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

        XCTAssertEqual(profileSection.rows.map(\.title), ["Method", "Authority"])
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
    func testTriXAtOneSecondReturnsCorrectedExposureFromWikiAuthority() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(film)

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertEqual(resultState.adjustedShutterSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(resultState.reciprocityState.badgeText, "Exact")
        XCTAssertEqual(resultState.correctedExposure.kind, .quantified)
        XCTAssertEqual(resultState.correctedExposure.correctedExposureSeconds ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(resultState.correctedExposure.primaryText, "2s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(viewModel.filmModePrimaryResultSeconds ?? 0, 2, accuracy: 0.0001)
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

        XCTAssertEqual(resultState.correctedExposure.primaryText, "14s")
        XCTAssertEqual(resultState.correctedExposure.secondaryText, "")
        XCTAssertEqual(details.currentResult.layout, .comparison)
        XCTAssertEqual(details.currentResult.adjustedShutter.title, "Adjusted Shutter")
        XCTAssertEqual(details.currentResult.adjustedShutter.valueText, "4s")
        XCTAssertEqual(details.currentResult.correctedExposure.valueText, "14s")
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
