import XCTest
@testable import PTimer

final class FilmModeDetailsDisplayStateTests: XCTestCase {
    @MainActor
    func testFilmModeExposureResultStateShowsCorrectedExposureForQuantifiedPresetResult() throws {
        let viewModel = makeFilmModeViewModel()
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
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canShowFilmDetails)
        XCTAssertTrue(viewModel.filmModeExposureResultState?.reciprocityState.showsInfoAffordance == true)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(details.title, "Reciprocity Details")
        XCTAssertEqual(details.summary.badgeText, "Formula-derived")
        XCTAssertEqual(details.summary.summaryText, "Formula-based correction on the active curve")
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
        let viewModel = makeFilmModeViewModel()
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
        XCTAssertEqual(details.summary.summaryText, "Formula-based correction on the active curve")
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
        let viewModel = makeFilmModeViewModel()
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
        let viewModel = makeFilmModeViewModel()
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
    func testFilmModeDetailsShowManufacturerNoDataForLimitedGuidanceResult() throws {
        let viewModel = makeFilmModeViewModel()
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
        // including this limited-guidance path.
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
            presetFilms: [makeMinimalDetailsFilm()]
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
        let viewModel = makeFilmModeViewModel()
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
            presetFilms: [makeURLBackedDetailsFilm()]
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
        let viewModel = makeFilmModeViewModel()
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
            presetFilms: [makeFallbackFormulaDetailsFilm()]
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
        let viewModel = makeFilmModeViewModel()
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
    func testFilmModeDetailsGraphOmitsCurrentPlotForLimitedGuidanceResult() throws {
        let viewModel = makeFilmModeViewModel()
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
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Velvia 50" })

        viewModel.baseShutter = 8
        viewModel.ndStop = 3
        viewModel.selectPresetFilm(film)

        _ = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph)

        // Velvia 50's 64 s row is the formula's not-recommended
        // boundary. The result is unsupported-with-numeric (formula
        // prediction outside the source range), so the current-point
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
        let viewModel = makeFilmModeViewModel()
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
            presetFilms: [makeMinimalDetailsFilm()]
        )
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 5
        viewModel.selectPresetFilm(try XCTUnwrap(viewModel.availablePresetFilms.first))

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertNil(details.graph)
        XCTAssertEqual(details.sections.first(where: { $0.title == "Reference" })?.rows.first?.value, "<= 1s    No correction")
    }
}
