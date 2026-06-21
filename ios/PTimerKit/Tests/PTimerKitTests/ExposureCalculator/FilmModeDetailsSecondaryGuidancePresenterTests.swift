// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

@MainActor
final class FilmModeSecondaryGuidanceTests: XCTestCase {

    // MARK: - Velvia 50

    func testFormulaProfileSourceReferenceAndGuidanceBoundaryPreservePerEntryColorCorrectionAndStopRow() throws {
        let film = try XCTUnwrap(film(named: "Velvia 50"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Additional Guidance" }),
            "PTIMER-119 follow-up: the detached Additional Guidance section must remain removed."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Velvia 50 is now a formula profile with source evidence; legacy Reference section must be gone."
        )

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Velvia 50 must surface a Source reference section for its converted formula profile."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        let sourceLines = sourceBlock.split(separator: "\n").map(String.init)

        func assertPaired(in lines: [String], block: String, meteredPrefix: String, valueSuffix: String, file: StaticString = #filePath, line: UInt = #line) {
            let match = lines.first { candidate in
                candidate.hasPrefix(meteredPrefix) && candidate.hasSuffix(" \(valueSuffix)")
            }
            XCTAssertNotNil(match, "Expected \(meteredPrefix) row to end with \(valueSuffix). Block was:\n\(block)", file: file, line: line)
        }

        // PTIMER-179 layout: the per-entry color note now renders on its
        // own indented line directly below the metered row, instead of as
        // a crowded third column. Verify the metered row is immediately
        // followed by its color note.
        func assertNoteBelow(in lines: [String], block: String, meteredPrefix: String, note: String, file: StaticString = #filePath, line: UInt = #line) {
            guard let index = lines.firstIndex(where: { $0.hasPrefix(meteredPrefix) }) else {
                XCTFail("Expected a row with prefix \(meteredPrefix). Block was:\n\(block)", file: file, line: line)
                return
            }
            let below = index + 1 < lines.count
                ? lines[index + 1].trimmingCharacters(in: .whitespaces)
                : ""
            XCTAssertEqual(below, note, "Expected \(meteredPrefix) row to be followed by note \(note). Block was:\n\(block)", file: file, line: line)
        }

        assertNoteBelow(in: sourceLines, block: sourceBlock, meteredPrefix: "4.0s", note: "5M")
        assertNoteBelow(in: sourceLines, block: sourceBlock, meteredPrefix: "8.0s", note: "7.5M")
        assertNoteBelow(in: sourceLines, block: sourceBlock, meteredPrefix: "16.0s", note: "10M")
        assertNoteBelow(in: sourceLines, block: sourceBlock, meteredPrefix: "32.0s", note: "12.5M")
        XCTAssertFalse(
            sourceBlock.contains("Not recommended"),
            "Source reference section must not pull the 64 s not-recommended boundary row into it."
        )

        let guidanceBoundarySection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" }),
            "Velvia 50's 64 s not-recommended boundary must surface in the Guidance boundary section."
        )
        let boundaryBlock = try XCTUnwrap(guidanceBoundarySection.rows.first?.value)
        let boundaryLines = boundaryBlock.split(separator: "\n").map(String.init)
        assertPaired(in: boundaryLines, block: boundaryBlock, meteredPrefix: "64.0s", valueSuffix: "Not recommended")
        XCTAssertFalse(
            boundaryBlock.contains("5M"),
            "Guidance boundary section must not pull source-reference color rows into it."
        )
    }

    func testFormulaProfileDetailsExposeSubtitleAndColorLegend() throws {
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

    func testFormulaProfileSourceReferenceAndGuidanceBoundaryPreserveGreenChannelAndStopRow() throws {
        let film = try XCTUnwrap(film(named: "Provia 100F"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" })
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        let sourceLines = sourceBlock.split(separator: "\n").map(String.init)
        let greenIndex = try XCTUnwrap(sourceLines.firstIndex(where: { $0.contains("2.5G") }))
        // PTIMER-179 layout: the green-correction note renders on its own
        // indented line directly below its metered row, so the metered
        // context is the preceding line rather than this line's prefix.
        XCTAssertEqual(sourceLines[greenIndex].trimmingCharacters(in: .whitespaces), "2.5G")
        XCTAssertGreaterThan(greenIndex, 0)
        XCTAssertTrue(
            sourceLines[greenIndex - 1].first?.isNumber ?? false,
            "Green-correction note should sit directly below a metered row: \(greenIndex > 0 ? sourceLines[greenIndex - 1] : "")"
        )

        let guidanceBoundarySection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Guidance boundary" })
        )
        let boundaryBlock = try XCTUnwrap(guidanceBoundarySection.rows.first?.value)
        let stopLine = try XCTUnwrap(
            boundaryBlock.split(separator: "\n").map(String.init).first(where: { $0.contains("Not recommended") })
        )
        XCTAssertTrue(
            stopLine.first?.isNumber ?? false,
            "Stop row should start with a metered exposure: \(stopLine)"
        )

        XCTAssertFalse(
            sourceBlock.contains("Not recommended"),
            "Source reference section must not pull in the 480 s not-recommended boundary."
        )
        XCTAssertFalse(
            boundaryBlock.contains("2.5G"),
            "Guidance boundary section must not pull in the 240 s source-reference row."
        )
    }

    func testFormulaProfileDetailsExposeSubtitleAndGreenLegend() throws {
        let film = try XCTUnwrap(film(named: "Provia 100F"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertEqual(displayState.subtitle, "Provia 100F · Official guidance")

        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(legend.lines.contains { $0 == "Color correction: G = green filtration." })
        XCTAssertTrue(legend.lines.contains { $0 == "Warning: Not recommended marks a manufacturer stop-signal." })
    }

    // MARK: - Ektachrome E100

    func testLimitedGuidanceReferenceDataPreservesFiltrationWithMeteredContext() throws {
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

    func testLimitedGuidanceDetailsExposeSubtitleAndFiltrationLegend() throws {
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

    func testTableProfileSourceReferenceKeepsDevelopmentRowsWithMeteredContext() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Additional Guidance" }))
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Converted Tri-X 400 must not surface the legacy Reference section."
        )

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Converted Tri-X 400 must surface a Source reference section carrying the published rows."
        )
        let block = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        let lines = block.split(separator: "\n").map(String.init)

        let devLines = lines.filter { $0.contains("Dev ") }
        XCTAssertEqual(devLines.count, 3)
        // PTIMER-179: a development note now renders on its own indented
        // line directly below its metered row (2-column layout), so the
        // metered context is positional rather than inline.
        func devNoteFollows(meteredPrefix: String, note: String) -> Bool {
            guard let index = lines.firstIndex(where: { $0.hasPrefix(meteredPrefix) }) else { return false }
            return index + 1 < lines.count && lines[index + 1].contains(note)
        }
        XCTAssertTrue(devNoteFollows(meteredPrefix: "1.0s", note: "Dev -10%"))
        XCTAssertTrue(devNoteFollows(meteredPrefix: "10.0s", note: "Dev -20%"))
        XCTAssertTrue(devNoteFollows(meteredPrefix: "100.0s", note: "Dev -30%"))

        for line in lines {
            XCTAssertNil(
                line.range(of: #"\b\d+(?:\.\d+)?[A-Z]\b"#, options: .regularExpression),
                "Tri-X row should not carry color-correction-style notation: \(line)"
            )
        }
    }

    func testTableProfileDetailsExposeSubtitleAndDevelopmentLegend() throws {
        let film = try XCTUnwrap(film(named: "Tri-X 400"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 1))

        // PTIMER-159/168: the log-log table model names itself in the
        // subtitle, so the migrated Tri-X profile reads "Official Kodak
        // graph/table" rather than the generic "Official guidance".
        XCTAssertEqual(displayState.subtitle, "Tri-X 400 · Official Kodak graph/table")

        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Development adjustment: Dev -10% means adjust development time by -10%." },
            "Expected development-adjustment legend line. Got \(legend.lines)."
        )
        XCTAssertFalse(legend.lines.contains(where: { $0.contains("magenta") }))
        XCTAssertFalse(legend.lines.contains(where: { $0.contains("manufacturer stop-signal") }))
    }

    // MARK: - Pan F Plus (no secondary guidance)

    func testBarePowerLawProfileDoesNotProduceLegendOrAdditionalGuidance() throws {
        let film = try XCTUnwrap(film(named: "Pan F Plus"))
        let displayState = try XCTUnwrap(makeDisplayState(film: film, meteredExposureSeconds: 4))

        XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Additional Guidance" }))
        // The Formula metadata section is gone; the formula
        // expression now sits next to the graph.
        XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Formula" }))
        XCTAssertNotNil(displayState.graph?.formulaDisplayText)
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
