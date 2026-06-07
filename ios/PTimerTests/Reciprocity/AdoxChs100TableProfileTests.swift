import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Behavior contract for ADOX CHS 100 II's official table profile (PTIMER-168).
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
/// The CHS 100 II profile now uses a table-interpolation rule
/// (migrated from formula in PTIMER-168). The table graph path is
/// rendered with graph.kind == .formula (same grammar as converted
/// table profiles such as Fomapan 100 Classic):
///
/// - Threshold 0 … 1 sec is unchanged (No correction band).
/// - Log-log interpolation between the four anchor rows (2/4/8/15 s)
///   gives exact corrected times at the anchor points.
/// - The 15 sec row marks the upper boundary of the published
///   source range; inputs above 15 sec use log-log extrapolation of
///   the last two anchors and surface as "Beyond source range".
///
/// Calculation/UI policy on CHS 100 II must NOT borrow CMS 20 II's
/// stop-signal vocabulary (no `Not-recommended boundary`, no
/// `Current input` chip, no `Unavailable` corrected exposure).
final class AdoxChs100TableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Threshold boundary (inclusive at 1 s)

    func testChs100IIAtOneSecondBoundaryReturnsOfficialNoCorrection() throws {
        let profile = try chs100Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0)
        XCTAssertEqual(
            result.metadata.basis,
            .officialThresholdNoCorrection,
            "CHS 100 II's 1 s threshold is inclusive — 1.0 s itself must read as no-correction."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 1.0, accuracy: 1e-6)
    }

    // MARK: - Table interpolation range (1 s … 15 s)

    func testChs100IIInsideTableRangeIsTableLogLogDerivedAtAllPublishedAnchorRows() throws {
        let profile = try chs100Profile()
        let anchorRows: [(metered: Double, corrected: Double)] = [
            (2, 3),
            (4, 8),
            (8, 20),
            (15, 45),
        ]
        for row in anchorRows {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: row.metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "CHS 100 II at \(row.metered) s must be table-log-log-derived."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                row.corrected,
                accuracy: 1e-4,
                "CHS 100 II at anchor \(row.metered) s must return the exact published corrected time \(row.corrected) sec; got \(corrected) sec."
            )
        }
    }

    func testChs100IITableInterpolationRuleExposesAnchorsAndBoundaries() throws {
        let profile = try chs100Profile()
        let tableRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r }
                return nil
            }.first,
            "CHS 100 II must contain a tableInterpolation rule after migration."
        )

        // No-correction threshold
        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 1, accuracy: 1e-6)

        // Source range
        XCTAssertEqual(
            tableRule.sourceRangeThroughSeconds,
            15,
            accuracy: 1e-6,
            "CHS 100 II's table domain must end at the last 2024 published row (15 sec)."
        )

        // Anchors: (metered → corrected)
        let expectedAnchors: [(Double, Double)] = [(2, 3), (4, 8), (8, 20), (15, 45)]
        for (metered, corrected) in expectedAnchors {
            let anchor = tableRule.anchors.first { abs($0.meteredSeconds - metered) < 1e-6 }
            XCTAssertNotNil(anchor, "Missing anchor at metered \(metered) s.")
            XCTAssertEqual(
                anchor?.correctedSeconds ?? -1,
                corrected,
                accuracy: 1e-6,
                "Anchor at \(metered) s must have corrected time \(corrected) s."
            )
        }
    }

    func testChs100IITableRuleModelBasisIsManufacturerTableLogLogInterpolation() throws {
        let profile = try chs100Profile()
        let basis = try XCTUnwrap(profile.modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
    }

    func testChs100IIHasNoFormulaRuleAfterMigration() throws {
        let profile = try chs100Profile()
        let formulaRules = profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            guard case let .formula(r) = rule else { return nil }
            return r
        }
        XCTAssertTrue(
            formulaRules.isEmpty,
            "CHS 100 II must not retain any .formula rule after migration to tableInterpolation; found \(formulaRules.count)."
        )
    }

    // MARK: - Beyond the published source range (> 15 s)

    func testChs100IIAboveFifteenSecondsBecomesBeyondSourceRange() throws {
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
            // Log-log extrapolation of the last two anchors (8→20 and 15→45).
            // Assert direction and non-nil only; do not assert any formula-coefficient value.
            XCTAssertGreaterThan(
                corrected,
                45,
                "CHS 100 II at \(metered) s corrected time must exceed the last anchor corrected time (45 s)."
            )
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
        struct EvidenceExpectation {
            let metered: Double
            let multiplier: Double
            let corrected: Double
        }
        let expected: [EvidenceExpectation] = [
            .init(metered: 2, multiplier: 1.5, corrected: 3),
            .init(metered: 4, multiplier: 2, corrected: 8),
            .init(metered: 8, multiplier: 2.5, corrected: 20),
            .init(metered: 15, multiplier: 3, corrected: 45),
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
                "CHS 100 II rows are anchor points, not source-evidence-only. The * mark is reserved for CMS 20 II's 1/1000 s row."
            )
        }
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
                "CHS 100 II at \(metered) s must render the formula Detail graph (table models use the formula graph path); got \(graph.kind)."
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

    func testChs100IIProfileIdAndNameReflectOfficialTableMigration() throws {
        let profile = try chs100Profile()
        XCTAssertEqual(
            profile.id,
            "adox-chs-100-ii-official-table",
            "Profile id must be updated to adox-chs-100-ii-official-table after migration."
        )
        XCTAssertEqual(
            profile.name,
            "Official ADOX table",
            "Profile name must read 'Official ADOX table' after migration."
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
    func testChs100IITableAnchorInputProducesTableLogLogDerivedStatusAndMarker() throws {
        for metered in [2.0, 4.0, 8.0, 15.0] {
            let displayState = try makeDisplayState(meteredExposureSeconds: metered)
            let graph = try XCTUnwrap(displayState.graph)
            let currentPoint = try XCTUnwrap(graph.currentPoint)
            XCTAssertNotEqual(
                currentPoint.style,
                .noCorrection,
                "CHS 100 II at anchor \(metered) s must not be marked as no-correction."
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Log-log interpolation of the official table",
                "CHS 100 II at anchor \(metered) s summary must read 'Log-log interpolation of the official table'."
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
                .beyondSourceRange,
                "Beyond-source CHS marker must use the beyond-source-range style."
            )
            let explanation = try XCTUnwrap(graph.unsupportedExplanation)
            XCTAssertTrue(
                explanation.lowercased().contains("source table"),
                "CHS 100 II beyond-source explanation must use source-table wording; got: \(explanation)"
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
    func testChs100IIInsideSourceRangeLegendShowsExpectedChips() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 4)
        let graph = try XCTUnwrap(displayState.graph)
        let labels = graph.legendChipLabels
        for required in ["Calculation curve", "Current result", "Source reference", "No-correction range"] {
            XCTAssertTrue(
                labels.contains(required),
                "CHS 100 II table legend must contain `\(required)`; got \(labels)."
            )
        }
    }

    // MARK: - Source reference section

    @MainActor
    func testChs100IISourceReferenceSectionContainsPublishedMultiplierTokens() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 4)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "CHS 100 II must surface a Source reference section."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        for token in ["1.5x", "2x", "2.5x", "3x"] {
            XCTAssertTrue(
                sourceBlock.contains(token),
                "Source reference block must surface the published multiplier token '\(token)'; got: \(sourceBlock)"
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
