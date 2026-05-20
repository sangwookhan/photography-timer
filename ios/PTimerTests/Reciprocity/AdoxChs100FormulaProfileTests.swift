import XCTest
@testable import PTimer

/// Behavior contract for ADOX CHS 100 II's formula profile (PTIMER-139).
///
/// ADOX's 2024 CHS 100 II technical sheet publishes reciprocity
/// guidance only through 15 sec; older / community / derived
/// extensions to 30 sec or 60 sec are not part of the current
/// official source and must not appear as fitting points or
/// Source reference markers.
///
/// Current published rows (Fotoimpex / ADOX 2024-07-11):
///
///   <= 1 s     No correction
///    2 s       ×1.5   →   3 s
///    4 s       ×2     →   8 s
///    8 s       ×2.5   →  20 s
///   15 s       ×3     →  45 s
///
/// The CHS 100 II profile uses the formula graph path (same grammar
/// as FOMA, Provia, HP5 Plus, etc.):
///
/// - Threshold 0 … 1 sec is unchanged (No correction band).
/// - `Tc = 1.2102 × Tm^1.3423` anchors a log-log fit through the
///   four published multiplier rows (2 / 4 / 8 / 15 sec).
/// - The 15 sec row marks the upper boundary of the published
///   source range; inputs above 15 sec keep the formula numeric
///   continuation and surface as "Beyond source range" with the
///   standard converted-formula-profile wording.
///
/// Calculation/UI policy on CHS 100 II must NOT borrow CMS 20 II's
/// stop-signal vocabulary (no `Not-recommended boundary`, no
/// `Current input` chip, no `Unavailable` corrected exposure). It
/// also must not retain table-graph vocabulary (no `Exact` chip).
final class AdoxChs100FormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold range (≤ 1 s)

    func testChs100IIBelowOneSecondReturnsOfficialNoCorrection() throws {
        let profile = try chs100Profile()
        for metered in [0.001, 0.25, 0.5, 0.999, 1.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "CHS 100 II at \(metered) s sits inside the 0…1 sec no-correction band."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, metered, accuracy: 1e-6)
        }
    }

    // MARK: - Formula range (1 s … 15 s)

    func testChs100IIInsideFormulaRangeIsFormulaDerivedAtAllPublishedAnchorRows() throws {
        let profile = try chs100Profile()
        let publishedRows: [(metered: Double, published: Double)] = [
            (2, 3),
            (4, 8),
            (8, 20),
            (15, 45),
        ]
        for row in publishedRows {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: row.metered)
            XCTAssertEqual(
                result.metadata.basis,
                .formulaDerived,
                "CHS 100 II at \(row.metered) s must be formula-derived, never resurrected as an exact-table point."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            let stopError = log2(corrected / row.published)
            XCTAssertEqual(
                stopError,
                0,
                accuracy: 0.2,
                "CHS 100 II formula at \(row.metered) s (\(corrected) sec) must stay within 0.2 stop of the published row \(row.published) sec; got error \(stopError) stop."
            )
        }
    }

    func testChs100IIFormulaRuleExposesPublishedCoefficientAndExponent() throws {
        let profile = try chs100Profile()
        let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(rule) = rule else { return nil }
            return rule
        }.first)

        XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
        XCTAssertEqual(formulaRule.formula.exponent, 1.3423, accuracy: 1e-4)
        let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
        XCTAssertEqual(coefficient, 1.2102, accuracy: 1e-4)

        let equation = try XCTUnwrap(formulaRule.formula.equation)
        XCTAssertTrue(
            equation.contains("Tm^P"),
            "Equation must use the Tm^P placeholder so the graph renders the exponent superscript; got: \(equation)"
        )

        let range = try XCTUnwrap(formulaRule.meteredRange)
        XCTAssertEqual(range.minimumSeconds, 1, accuracy: 1e-6)
        XCTAssertEqual(
            range.maximumSeconds ?? 0,
            15,
            accuracy: 1e-6,
            "CHS 100 II's formula domain must end at the last 2024 published row (15 sec)."
        )
        XCTAssertTrue(
            formulaRule.extrapolateBeyondMaximum,
            "CHS 100 II must keep the default formula extrapolation past 15 sec so 'Beyond source range' surfaces a numeric continuation, not an Unavailable value."
        )
    }

    // MARK: - Beyond the published source range (> 15 s)

    func testChs100IIAboveFifteenSecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try chs100Profile()
        for metered in [16.0, 30.0, 60.0, 200.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "CHS 100 II at \(metered) s sits above the 15 sec last published row and must be marked outside manufacturer guidance."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "CHS 100 II at \(metered) s must keep a numeric continuation past the source range — Beyond source range is not Unavailable."
            )
            let expected = 1.2102 * pow(metered, 1.3423)
            XCTAssertEqual(corrected, expected, accuracy: expected * 0.01)
        }
    }

    // MARK: - Source evidence preservation

    func testChs100IISourceEvidencePreservesFour2024PublishedRows() throws {
        let profile = try chs100Profile()
        let metereds = profile.sourceEvidence.compactMap { row -> Double? in
            if case let .exactSeconds(seconds) = row.meteredExposure { return seconds }
            return nil
        }
        XCTAssertEqual(
            metereds,
            [2, 4, 8, 15],
            "CHS 100 II must preserve only the four 2024-published multiplier rows as source evidence; 30 sec and 60 sec are not part of the current official source."
        )
    }

    func testChs100IIDropsLegacyThirtyAndSixtySecondRowsFromSourceEvidence() throws {
        let profile = try chs100Profile()
        for legacy in [30.0, 60.0] {
            let leaked = profile.sourceEvidence.contains { row in
                if case let .exactSeconds(seconds) = row.meteredExposure {
                    return abs(seconds - legacy) < 1e-6
                }
                return false
            }
            XCTAssertFalse(
                leaked,
                "CHS 100 II must not retain the legacy \(legacy) sec row — it is not in the 2024 ADOX technical sheet."
            )
        }
    }

    func testChs100IISourceEvidenceRowsKeepMultiplierAndCorrectedTime() throws {
        let profile = try chs100Profile()
        let expected: [(metered: Double, multiplier: Double, corrected: Double)] = [
            (2, 1.5, 3),
            (4, 2, 8),
            (8, 2.5, 20),
            (15, 3, 45),
        ]
        for entry in expected {
            let row = try XCTUnwrap(profile.sourceEvidence.first { row in
                if case let .exactSeconds(seconds) = row.meteredExposure {
                    return abs(seconds - entry.metered) < 1e-9
                }
                return false
            })

            let multiplier = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.multiplier(value)) = adjustment else { return nil }
                return value.factor
            }.first
            XCTAssertEqual(
                multiplier ?? -1,
                entry.multiplier,
                accuracy: 1e-6,
                "Source evidence at \(entry.metered) s must keep the published multiplier ×\(entry.multiplier)."
            )

            let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            XCTAssertEqual(
                correctedSeconds ?? -1,
                entry.corrected,
                accuracy: 1e-6,
                "Source evidence at \(entry.metered) s must keep the published corrected time \(entry.corrected) sec."
            )

            XCTAssertFalse(
                row.isSourceEvidenceOnly,
                "CHS 100 II rows are fitting/anchor points, not source-evidence-only. The * mark is reserved for CMS 20 II's 1/1000 s row."
            )
        }
    }

    func testChs100IICalculationRulesDoNotContainATableRule() throws {
        let profile = try chs100Profile()
        for rule in profile.rules {
            if case .table = rule {
                XCTFail("CHS 100 II must no longer carry a table rule — the published rows live as source evidence only.")
            }
        }
    }

    func testChs100IIProfileIsClassifiedAsConvertedFormulaProfile() throws {
        let profile = try chs100Profile()
        XCTAssertTrue(
            profile.isConvertedFormulaProfile,
            "CHS 100 II carries a formula rule + source evidence and must surface as a converted formula profile so beyond-source wording fires."
        )
    }

    // MARK: - Graph display state

    @MainActor
    func testChs100IIGraphIsFormulaKindNotTablePreview() throws {
        for metered in [0.25, 4.0, 30.0, 120.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.kind,
                .formula,
                "CHS 100 II at \(metered) s must render the formula Detail graph; got \(graph.kind)."
            )
        }
    }

    func testChs100IIProfileCitesThe2024TechnicalSheet() throws {
        let profile = try chs100Profile()
        XCTAssertEqual(
            profile.source.title,
            "ADOX CHS 100 II S/W Film — Technische Beschreibung, 11. Juli 2024",
            "CHS 100 II must cite the current (2024-07-11) ADOX / Fotoimpex technical sheet."
        )
        XCTAssertEqual(profile.source.publisher, "ADOX")
        XCTAssertFalse(
            profile.source.title?.lowercased().contains("adotech") ?? false,
            "ADOTECH IV belongs to CMS 20 II; CHS 100 II must not borrow the CMS 20 II citation."
        )
    }

    @MainActor
    func testChs100IIGraphExposesFormulaText() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 4)
        let graph = try XCTUnwrap(displayState.graph)
        let formula = try XCTUnwrap(
            graph.formulaDisplayText,
            "CHS 100 II must expose the formula expression next to the graph."
        )
        XCTAssertTrue(
            formula.contains("1.2102"),
            "Formula text must surface the published coefficient 1.2102; got: \(formula)"
        )
        XCTAssertTrue(
            formula.contains("1.3423"),
            "Formula text must surface the published exponent 1.3423; got: \(formula)"
        )
    }

    @MainActor
    func testChs100IIGraphCarriesFourPublishedSourceReferenceMarkers() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 4)
        let graph = try XCTUnwrap(displayState.graph)
        let markerMetereds = Set(graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() })
        XCTAssertEqual(
            markerMetereds,
            Set([2.0, 4.0, 8.0, 15.0]),
            "CHS 100 II must surface only the four 2024-published rows as source-reference markers; 30 sec and 60 sec are not part of the current official source."
        )
        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "CHS 100 II has no published stop signal; the red not-recommended dashed boundary must not render."
        )
    }

    @MainActor
    func testChs100IIBeyondSourceRangeShadingStartsAtFifteenSeconds() throws {
        for metered in [4.0, 30.0, 60.0, 200.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let start = try XCTUnwrap(
                graph.beyondSourceRangeStartSeconds,
                "Metered \(metered) s: CHS 100 II must render the pink beyond-source-range shading anchored at 15 sec."
            )
            XCTAssertEqual(start, 15.000001, accuracy: 1e-3)
        }
    }

    @MainActor
    func testChs100IINoCorrectionInputProducesIdentityMarkerAndNoCorrectionStatus() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 0.25)
        let graph = try XCTUnwrap(displayState.graph)
        let currentPoint = try XCTUnwrap(graph.currentPoint)
        XCTAssertEqual(currentPoint.style, .noCorrection)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 0.25, accuracy: 1e-9)
        XCTAssertEqual(currentPoint.point.correctedExposureSeconds, 0.25, accuracy: 1e-9)

        XCTAssertEqual(
            displayState.currentResult.statusText,
            "No correction",
            "CHS 100 II sub-1 sec input must surface the No correction status."
        )
    }

    @MainActor
    func testChs100IIFormulaInputProducesFormulaDerivedStatusAndMarker() throws {
        for metered in [2.0, 4.0, 8.0, 15.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let currentPoint = try XCTUnwrap(graph.currentPoint)
            XCTAssertEqual(
                currentPoint.style,
                .formulaDerived,
                "CHS 100 II at \(metered) s must mark the current point as formula-derived, not Exact."
            )
            XCTAssertEqual(
                displayState.currentResult.statusText,
                "Formula-derived",
                "CHS 100 II at \(metered) s status must read Formula-derived, not Exact or Estimated."
            )
        }
    }

    @MainActor
    func testChs100IIBeyondSourceRangeInputUsesBeyondSourceRangeWording() throws {
        for metered in [30.0, 60.0, 128.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Beyond source range",
                "CHS 100 II at \(metered) s must surface Beyond source range — 30 sec and 60 sec are no longer official rows."
            )
            XCTAssertEqual(displayState.currentResult.statusText, "Beyond source range")

            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(graph.kind, .formula, "Beyond-source CHS inputs must keep the formula Detail graph.")
            XCTAssertEqual(
                graph.currentPoint?.style,
                .extrapolated,
                "Beyond-source CHS marker must use the extrapolated style, not the Exact table-anchor style."
            )
            let explanation = try XCTUnwrap(graph.unsupportedExplanation)
            XCTAssertTrue(
                explanation.lowercased().contains("source range"),
                "CHS 100 II beyond-source explanation must use source-range wording; got: \(explanation)"
            )
        }
    }

    // MARK: - Legend vocabulary

    @MainActor
    func testChs100IILegendDoesNotShowExactOrCmsStopSignalChips() throws {
        for metered in [0.25, 4.0, 30.0, 200.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let labels = graph.legendChipLabels
            XCTAssertFalse(
                labels.contains("Exact"),
                "CHS 100 II legend must not contain the table-graph Exact chip; got \(labels) at \(metered) s."
            )
            XCTAssertFalse(
                labels.contains("Estimated"),
                "CHS 100 II legend must not contain the table-graph Estimated chip; got \(labels) at \(metered) s."
            )
            XCTAssertFalse(
                labels.contains("Extrapolated"),
                "CHS 100 II legend must not contain the table-graph Extrapolated chip; got \(labels) at \(metered) s."
            )
            XCTAssertFalse(
                labels.contains("Not-recommended boundary"),
                "CHS 100 II has no manufacturer stop signal; CMS-style chip must not appear. Got \(labels) at \(metered) s."
            )
        }
    }

    @MainActor
    func testChs100IIInsideSourceRangeLegendShowsFormulaGraphChips() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 4)
        let graph = try XCTUnwrap(displayState.graph)
        let labels = graph.legendChipLabels
        for required in ["Calculation curve", "Current result", "Source reference", "No-correction range"] {
            XCTAssertTrue(
                labels.contains(required),
                "CHS 100 II formula legend must contain `\(required)`; got \(labels)."
            )
        }
    }

    // MARK: - Helpers

    private func chs100Profile() throws -> ReciprocityProfile {
        let film = try chs100Film()
        return try XCTUnwrap(film.profiles.first)
    }

    private func chs100Film() throws -> FilmIdentity {
        try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "CHS 100 II" },
            "CHS 100 II must remain in the launch catalog."
        )
    }

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        let film = try chs100Film()
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> = .success(
            ExposureCalculationResult(
                baseShutterSeconds: meteredExposureSeconds,
                stop: 0,
                resultShutterSeconds: meteredExposureSeconds
            )
        )
        return try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: calculationResult,
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )
    }
}
