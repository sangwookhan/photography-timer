import XCTest
import PTimerKit

final class FilmModeGraphVisibilityTests: XCTestCase {
    // MARK: - PTIMER-143 — Sub-second No correction for formula-only profiles

    @MainActor
    func testFormulaGraphSourcePointsCoverCanonicalRangeRegardlessOfCurrentInput() throws {
        // With a short current input, the graph should still plot source points up to
        // the canonical 120s upper bound so the graph feels stable, not auto-scaled.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

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
    func testFilmModeUnofficialProfileSubSecondReturnsNoCorrectionAndPreservesCaveat() throws {
        // Portra 400 unofficial practical has a single formula rule
        // (Tc = Tm^1.34) whose `noCorrectionThroughSeconds` open
        // boundary at ~1 s owns the long-exposure threshold — no
        // companion threshold rule. Without that guard, an adjusted
        // shutter of ~1/30 s would produce a corrected exposure
        // shorter than the adjusted shutter, which a reciprocity
        // correction must never do. The result reads as "No
        // correction" while keeping the unofficial-authority caveat
        // visible.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

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
    func testFilmModeUnofficialProfileAboveOneSecondStillProducesFormulaPrediction() throws {
        // Sanity guard: the default no-correction handoff applies
        // strictly below 1s. Inputs at or above 1s flow through the
        // formula rule unchanged, preserving the prior PTIMER-143
        // behavior for the unofficial profile.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let binding = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(binding.policyResult.metadata.basis, .formulaDerived)
    }

    // MARK: - PTIMER-143 — No-correction graph visibility

    @MainActor
    func testFilmModeUnofficialProfileSubSecondGraphShowsNoCorrectionRegion() throws {
        // After the policy default-handoff sends Portra 400
        // unofficial sub-1s inputs to No correction, the Details
        // graph must visibly show that no-correction state — the
        // viewport expands below 1 s so the current point lands
        // inside the plot and the no-correction overlay renders
        // up to the synthesized 1 s default upper bound.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

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
        // PTIMER-160: the unofficial profile stores its no-correction
        // boundary on the formula itself; the practical 1 s long-
        // exposure threshold is encoded as 0.999999 so Tm = 1 s
        // activates the formula (matching the rest of the catalog).
        XCTAssertEqual(
            graph.noCorrectionRangeUpperBoundSeconds,
            0.999_999,
            "Formula-only unofficial profile must surface the formula's no-correction boundary so the green overlay renders."
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
    func testFilmModeFormulaGraphViewportIsStableAcrossInputsWithinSameTier() throws {
        // Stable viewport contract: same profile + same scale tier
        // produces the same graph frame regardless of where the
        // current input lands. Only the current-result marker
        // moves between sub-second, near-1 s, and long-exposure
        // inputs. T-MAX 100 across 1/60 s (No correction), 1 s
        // (table-derived correction), and 30 s (table-derived correction)
        // must share identical xRange / yRange.
        let viewModel = makeFilmModeViewModel()
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
    func testFilmModeUnofficialProfileFrameIsStableAcrossSubSecondNearOneSecondAndLongInputs() throws {
        // Spec: "0.033 s, 1.1 s, 17 s on the same profile must use
        // the same graph frame; current result marker only moves."
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)
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
    func testFilmModeUnofficialProfileCalculationCurveJoinsIdentityAndFormulaSegments() throws {
        // The calculation curve must include an identity segment
        // (Tc = Tm) through the no-correction zone and the formula
        // segment past the threshold, with no visual gap at the
        // handoff. For Portra 400 unofficial (Tc = Tm^1.34), the
        // identity samples sit on the y = x line up to 1 s, and at
        // least one formula sample beyond 1 s lifts above it.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)
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
        let viewModel = makeFilmModeViewModel()
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
        // across every model type that renders a formula-kind graph:
        // an official table-origin / table-derived profile (T-MAX 100,
        // PTIMER-168), an official converted-formula profile
        // (Provia 100F), a no-source-range official formula (HP5 Plus), and
        // an unofficial practical profile (Portra 400 unofficial).
        // Official limited-guidance profiles (Portra 400 official)
        // produce no formula graph and are excluded from this loop.
        let viewModel = makeFilmModeViewModel()
        viewModel.ndStop = 0

        struct FormulaGraphFilmCase {
            let name: String
            let baseShutter: Double
            let selectsUnofficial: Bool
        }
        let formulaGraphFilmCases: [FormulaGraphFilmCase] = [
            .init(name: "Provia 100F", baseShutter: 60, selectsUnofficial: false),
            .init(name: "T-MAX 100", baseShutter: 30, selectsUnofficial: false),
            .init(name: "HP5 Plus", baseShutter: 30, selectsUnofficial: false),
            .init(name: "Portra 400", baseShutter: 10, selectsUnofficial: true),
        ]
        for caseInfo in formulaGraphFilmCases {
            if caseInfo.selectsUnofficial {
                // Portra 400 is the only unofficial-practical case today;
                // activate it via the relocated profile/model path.
                let entry = try unofficialPracticalSelectorEntry(in: viewModel)
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

    // MARK: - Preset sub-second inputs surface a visible no-correction region

    private struct PresetSubSecondNoCorrectionCase {
        let film: String
        let sample: Double
        let viewportLowerBelow: Double
        let expectedNoCorrectionUpperBound: Double
        let upperBoundIsMinimum: Bool
    }

    /// Profiles whose no-correction band reaches into the sub-second
    /// region must, for a sub-second input, expand the graph viewport
    /// below the band so the no-correction overlay renders as a visible
    /// region instead of collapsing onto the left edge. The per-film
    /// no-correction upper bound and viewport expansion are case data;
    /// the visibility contract is shared.
    private let presetSubSecondNoCorrectionCases: [PresetSubSecondNoCorrectionCase] = [
        // PTIMER-168: Kodak's table applies no correction through 0.5 sec
        // but the 1 sec +1/3 stop row marks 1 sec as outside the band, so
        // the no-correction range ends at 0.1 s.
        PresetSubSecondNoCorrectionCase(film: "T-MAX 100", sample: 1.0 / 60.0,
                                        viewportLowerBelow: 0.1,
                                        expectedNoCorrectionUpperBound: 0.1,
                                        upperBoundIsMinimum: false),
        PresetSubSecondNoCorrectionCase(film: "HP5 Plus", sample: 0.25,
                                        viewportLowerBelow: 1.0,
                                        expectedNoCorrectionUpperBound: 1.0,
                                        upperBoundIsMinimum: false),
        // Provia 100F's published no-correction threshold extends to 128 s.
        PresetSubSecondNoCorrectionCase(film: "Provia 100F", sample: 0.5,
                                        viewportLowerBelow: 1.0,
                                        expectedNoCorrectionUpperBound: 128,
                                        upperBoundIsMinimum: true),
    ]

    @MainActor
    func testPresetSubSecondInputShowsVisibleNoCorrectionRegion() throws {
        for c in presetSubSecondNoCorrectionCases {
            let viewModel = makeFilmModeViewModel()
            let film = try XCTUnwrap(
                viewModel.availablePresetFilms.first { $0.canonicalStockName == c.film },
                "\(c.film): must remain in the launch catalog."
            )

            viewModel.baseShutter = c.sample
            viewModel.ndStop = 0
            viewModel.selectPresetFilm(film)

            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState, "\(c.film): must produce details.")
            let graph = try XCTUnwrap(details.graph, "\(c.film): must surface a graph.")

            XCTAssertLessThan(
                graph.xRange.lowerBound,
                c.viewportLowerBelow,
                "\(c.film): viewport must expand below the no-correction band so the region is visible."
            )
            let upper = try XCTUnwrap(
                graph.noCorrectionRangeUpperBoundSeconds,
                "\(c.film): no-correction upper bound must be present."
            )
            if c.upperBoundIsMinimum {
                XCTAssertGreaterThanOrEqual(
                    upper, c.expectedNoCorrectionUpperBound,
                    "\(c.film): no-correction overlay must reach at least its published upper bound."
                )
            } else {
                XCTAssertEqual(
                    upper, c.expectedNoCorrectionUpperBound, accuracy: 1e-6,
                    "\(c.film): no-correction range upper bound."
                )
            }
            XCTAssertGreaterThan(
                upper, graph.xRange.lowerBound,
                "\(c.film): no-correction upper bound must sit above the viewport lower bound so the overlay has visible width."
            )
            XCTAssertFalse(graph.isBelowVisibleRange, "\(c.film): sub-second input must sit inside the expanded visible range.")
            XCTAssertEqual(graph.currentPoint?.style, .noCorrection, "\(c.film): current point must read as No correction.")
        }
    }
}
