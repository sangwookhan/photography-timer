import XCTest
@testable import PTimer
import PTimerKit

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

    // MARK: - Table interpolation range (1 s … 15 s)

    // MARK: - Beyond the published source range (> 15 s)

    // MARK: - Source evidence preservation

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
