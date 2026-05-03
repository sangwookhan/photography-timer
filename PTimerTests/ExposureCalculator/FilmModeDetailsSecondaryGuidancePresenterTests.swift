import XCTest
@testable import PTimer

@MainActor
final class FilmModeDetailsSecondaryGuidancePresenterTests: XCTestCase {

    // MARK: - Velvia 50

    func testVelvia50ReferenceDataPreservesPerEntryColorCorrectionAndStopRow() throws {
        let film = try XCTUnwrap(film(named: "Velvia 50"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Additional Guidance" }),
            "PTIMER-119 follow-up: the detached Additional Guidance section must remain removed."
        )

        let referenceSection = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Reference" }))
        let block = try XCTUnwrap(referenceSection.rows.first?.value)
        let lines = block.split(separator: "\n").map(String.init)

        func assertPaired(meteredPrefix: String, valueSuffix: String, file: StaticString = #filePath, line: UInt = #line) {
            let match = lines.first { candidate in
                candidate.hasPrefix(meteredPrefix) && candidate.hasSuffix(" \(valueSuffix)")
            }
            XCTAssertNotNil(match, "Expected \(meteredPrefix) row to end with \(valueSuffix). Block was:\n\(block)", file: file, line: line)
        }

        assertPaired(meteredPrefix: "4.0s", valueSuffix: "5M")
        assertPaired(meteredPrefix: "8.0s", valueSuffix: "7.5M")
        assertPaired(meteredPrefix: "16.0s", valueSuffix: "10M")
        assertPaired(meteredPrefix: "32.0s", valueSuffix: "12.5M")
        assertPaired(meteredPrefix: "64.0s", valueSuffix: "Not recommended")
    }

    func testVelvia50DetailsExposesFilmSubtitleAndLegend() throws {
        let film = try XCTUnwrap(film(named: "Velvia 50"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertEqual(displayState.subtitle, "Velvia 50 · Official guidance")

        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Color correction: M = magenta filtration." },
            "Expected magenta legend line. Got \(legend.lines)."
        )
        XCTAssertTrue(
            legend.lines.contains { $0 == "Warning: Not recommended marks a manufacturer stop-signal." },
            "Expected stop-signal legend line. Got \(legend.lines)."
        )
        XCTAssertFalse(
            legend.lines.contains(where: { $0.contains("development time") }),
            "Velvia 50 must not show a development-adjustment legend line."
        )
    }

    // MARK: - Provia 100F

    func testProvia100FReferenceDataPreservesGreenChannelContextAndStopRow() throws {
        let film = try XCTUnwrap(film(named: "Provia 100F"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        let referenceSection = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Reference" }))
        let block = try XCTUnwrap(referenceSection.rows.first?.value)

        let greenLine = try XCTUnwrap(
            block.split(separator: "\n").map(String.init).first(where: { $0.contains("2.5G") })
        )
        XCTAssertTrue(greenLine.first?.isNumber ?? false, "Green-correction row should start with a metered exposure: \(greenLine)")

        let stopLine = try XCTUnwrap(
            block.split(separator: "\n").map(String.init).first(where: { $0.contains("Not recommended") })
        )
        XCTAssertTrue(stopLine.first?.isNumber ?? false, "Stop row should start with a metered exposure: \(stopLine)")
    }

    func testProvia100FDetailsExposesFilmSubtitleAndGreenLegend() throws {
        let film = try XCTUnwrap(film(named: "Provia 100F"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertEqual(displayState.subtitle, "Provia 100F · Official guidance")

        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(legend.lines.contains { $0 == "Color correction: G = green filtration." })
        XCTAssertTrue(legend.lines.contains { $0 == "Warning: Not recommended marks a manufacturer stop-signal." })
    }

    // MARK: - Ektachrome E100

    func testEktachromeE100ReferenceDataPreservesCC10RWithMeteredContext() throws {
        let film = try XCTUnwrap(film(named: "Ektachrome E100"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        let referenceSection = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Reference" }))
        let block = try XCTUnwrap(referenceSection.rows.first?.value)

        let cc10RLine = try XCTUnwrap(
            block.split(separator: "\n").map(String.init).first(where: { $0.contains("CC10R") })
        )
        XCTAssertTrue(cc10RLine.contains("Color correction"))
        XCTAssertTrue(cc10RLine.contains("CC10R"))
        XCTAssertTrue(cc10RLine.contains("120"))
    }

    func testEktachromeE100DetailsExposesFilmSubtitleAndCC10RLegend() throws {
        let film = try XCTUnwrap(film(named: "Ektachrome E100"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertEqual(displayState.subtitle, "Ektachrome E100 · Official guidance")

        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Color correction: CC10R = color-compensating red filtration." },
            "Expected CC10R legend line. Got \(legend.lines)."
        )
        XCTAssertFalse(legend.lines.contains(where: { $0.contains("development time") }))
        XCTAssertFalse(legend.lines.contains(where: { $0.contains("manufacturer stop-signal") }))
    }

    // MARK: - Tri-X 400

    func testTriX400ReferenceDataKeepsDevelopmentRowsWithMeteredContext() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Additional Guidance" }))

        let referenceSection = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Reference" }))
        let block = try XCTUnwrap(referenceSection.rows.first?.value)
        let lines = block.split(separator: "\n").map(String.init)

        let devLines = lines.filter { $0.contains("Dev ") }
        XCTAssertEqual(devLines.count, 3)
        XCTAssertTrue(devLines.contains(where: { $0.hasPrefix("1.0s")   && $0.contains("Dev -10%") }))
        XCTAssertTrue(devLines.contains(where: { $0.hasPrefix("10.0s")  && $0.contains("Dev -20%") }))
        XCTAssertTrue(devLines.contains(where: { $0.hasPrefix("100.0s") && $0.contains("Dev -30%") }))

        for line in lines {
            XCTAssertNil(
                line.range(of: #"\b\d+(?:\.\d+)?[A-Z]\b"#, options: .regularExpression),
                "Tri-X row should not carry color-correction-style notation: \(line)"
            )
        }
    }

    func testTriX400DetailsExposesFilmSubtitleAndDevelopmentLegend() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertEqual(displayState.subtitle, "Tri-X 400 · Official guidance")

        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Development adjustment: Dev -10% means adjust development time by -10%." },
            "Expected development-adjustment legend line. Got \(legend.lines)."
        )
        XCTAssertFalse(legend.lines.contains(where: { $0.contains("magenta") }))
        XCTAssertFalse(legend.lines.contains(where: { $0.contains("manufacturer stop-signal") }))
    }

    // MARK: - Pan F Plus (no secondary guidance)

    func testPanFPlusFormulaProfileDoesNotProduceLegendOrAdditionalGuidance() throws {
        let film = try XCTUnwrap(film(named: "Pan F Plus"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 4))

        XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Additional Guidance" }))
        XCTAssertTrue(displayState.sections.contains(where: { $0.title == "Formula" }))
        XCTAssertEqual(displayState.subtitle, "Pan F Plus · Official guidance")
        XCTAssertNil(displayState.legend, "Films without secondary guidance must not produce an empty legend.")
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }

    private func makeDisplayState(
        film: FilmIdentity,
        meteredExposureSeconds: Double
    ) -> FilmModeDetailsDisplayState? {
        guard let profile = film.profiles.first else { return nil }
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: meteredExposureSeconds)
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
        return model.makeDetailsDisplayState(
            input: FilmModeDetailsPresenterInput(
                bindingState: bindingState,
                calculationResult: calculationResult,
                filmModeExposureResultState: nil,
                formatDuration: { "\($0)s" },
                formatDurationCoarse: { "\($0)s" },
                formatAxisDuration: { "\($0)s" }
            )
        )
    }
}
