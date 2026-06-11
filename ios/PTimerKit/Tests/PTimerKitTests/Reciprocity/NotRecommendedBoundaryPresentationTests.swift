import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-169 Stage 4: manufacturer stop signals ("64 sec is not
/// recommended.") become visible at the calculation-result point of
/// use once the metered exposure reaches the published boundary —
/// not only inside Film Details.
///
/// The surfacing is presentation-only: the classifier reads the
/// profile's source evidence, the vocabulary presenter enriches the
/// result info/detail text, and the calculation policy stays
/// sourceEvidence-agnostic (corrected exposures do not move — see
/// `SourceShapePreservationBaselineTests`).
final class NotRecommendedBoundaryPresentationTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()
    private let vocabulary = ReciprocityDetailsVocabularyPresenter()

    /// One published stop signal expectation: the stock's boundary in
    /// seconds and the manufacturer's verbatim warning message.
    private struct StopSignalPin {
        let stock: String
        let boundary: Double
        let message: String

        init(_ stock: String, _ boundary: Double, _ message: String) {
            self.stock = stock
            self.boundary = boundary
            self.message = message
        }
    }

    // MARK: - Classifier

    func testStopSignalMessagesFireOnceBoundaryIsReached() throws {
        let pins: [StopSignalPin] = [
            StopSignalPin("Velvia 50", 64, "64 sec is not recommended."),
            StopSignalPin("Provia 100F", 480, "8 min is not recommended."),
            StopSignalPin("CMS 20 II", 100, "100 sec is not recommended."),
        ]
        for pin in pins {
            let profile = try profile(pin.stock)
            XCTAssertEqual(
                ReciprocitySourceEvidenceClassifier.reachedStopSignalMessages(
                    in: profile,
                    meteredExposureSeconds: pin.boundary
                ),
                [pin.message],
                "\(pin.stock) stop signal must fire at the \(pin.boundary) s boundary."
            )
            XCTAssertEqual(
                ReciprocitySourceEvidenceClassifier.reachedStopSignalMessages(
                    in: profile,
                    meteredExposureSeconds: pin.boundary * 2
                ),
                [pin.message],
                "\(pin.stock) stop signal must stay visible past the boundary."
            )
            XCTAssertTrue(
                ReciprocitySourceEvidenceClassifier.reachedStopSignalMessages(
                    in: profile,
                    meteredExposureSeconds: pin.boundary - 0.01
                ).isEmpty,
                "\(pin.stock) stop signal must not fire below the boundary."
            )
        }
    }

    func testProfilesWithoutStopSignalRowsStaySilent() throws {
        for stock in ["Acros II", "Velvia 100", "RETRO 80S", "SUPERPAN 200", "HP5 Plus"] {
            let profile = try profile(stock)
            XCTAssertTrue(
                ReciprocitySourceEvidenceClassifier.reachedStopSignalMessages(
                    in: profile,
                    meteredExposureSeconds: 10_000
                ).isEmpty,
                "\(stock) publishes no not-recommended boundary and must stay silent."
            )
        }
    }

    // MARK: - Result-band info text (point of use)

    func testVelvia50InfoTextLeadsWithStopSignalAtBoundary() throws {
        let state = vocabulary.reciprocityStateDisplayState(
            for: try bindingState("Velvia 50", metered: 64)
        )
        XCTAssertTrue(
            state.infoText.hasPrefix("Manufacturer guidance: 64 sec is not recommended."),
            "Info text must lead with the manufacturer stop signal, got: \(state.infoText)"
        )
        XCTAssertEqual(
            state.badgeText,
            "Beyond source range",
            "The badge keeps its calculation-state wording; the stop signal rides the info text."
        )
    }

    func testVelvia50InfoTextStaysGenericBelowBoundary() throws {
        let state = vocabulary.reciprocityStateDisplayState(
            for: try bindingState("Velvia 50", metered: 32)
        )
        // The formula's own policy note quotes the 64 s row, so the
        // assertion targets the stop-signal prefix, not the substring.
        XCTAssertFalse(
            state.infoText.hasPrefix("Manufacturer guidance:"),
            "No stop signal below the published boundary, got: \(state.infoText)"
        )
    }

    func testProviaAndCmsInfoTextLeadWithStopSignalAtBoundary() throws {
        let pins: [StopSignalPin] = [
            StopSignalPin("Provia 100F", 480, "8 min is not recommended."),
            StopSignalPin("CMS 20 II", 100, "100 sec is not recommended."),
        ]
        for pin in pins {
            let state = vocabulary.reciprocityStateDisplayState(
                for: try bindingState(pin.stock, metered: pin.boundary)
            )
            XCTAssertTrue(
                state.infoText.hasPrefix("Manufacturer guidance: \(pin.message)"),
                "\(pin.stock) info text must lead with the stop signal, got: \(state.infoText)"
            )
        }
    }

    // MARK: - Deliberate scope: unsupported state only, first message only

    /// The stop signal is scoped to the beyond-source-range
    /// (`unsupported`) presentation. A fixture whose boundary sits
    /// INSIDE the source range still produces a quantified in-range
    /// result past the boundary — and must stay silent: no-correction
    /// and in-range derived states do not grow the warning.
    func testStopSignalDoesNotSurfaceOnQuantifiedInRangeResults() throws {
        let bindingState = try fixtureBindingState(
            sourceRangeThroughSeconds: 100,
            boundaries: [(20, "20 sec is not recommended.")],
            metered: 50
        )
        XCTAssertEqual(bindingState.presentation.category, .formulaDerived)
        XCTAssertNil(vocabulary.manufacturerStopSignalText(for: bindingState))
        XCTAssertFalse(
            vocabulary.reciprocityStateDisplayState(for: bindingState)
                .infoText.hasPrefix("Manufacturer guidance:")
        )
    }

    /// Deliberate single-message policy: when several boundaries have
    /// been passed, only the FIRST reached stop signal leads the text.
    /// No shipped profile publishes more than one boundary; a
    /// multi-warning UI is out of scope for PTIMER-169.
    func testOnlyFirstReachedStopSignalSurfaces() throws {
        let bindingState = try fixtureBindingState(
            sourceRangeThroughSeconds: 10,
            boundaries: [
                (20, "20 sec is not recommended."),
                (40, "40 sec is not recommended."),
            ],
            metered: 50
        )
        XCTAssertEqual(
            ReciprocitySourceEvidenceClassifier.reachedStopSignalMessages(
                in: bindingState.profile,
                meteredExposureSeconds: 50
            ),
            ["20 sec is not recommended.", "40 sec is not recommended."],
            "The classifier reports every reached boundary in row order."
        )
        XCTAssertEqual(
            vocabulary.manufacturerStopSignalText(for: bindingState),
            "Manufacturer guidance: 20 sec is not recommended.",
            "The presenter surfaces only the first reached message."
        )
    }

    // MARK: - Details summary detail text

    func testVelvia50SummaryDetailLeadsWithStopSignalAtBoundary() throws {
        let detail = try XCTUnwrap(
            vocabulary.summaryDetailText(for: try bindingState("Velvia 50", metered: 64))
        )
        XCTAssertTrue(
            detail.hasPrefix("Manufacturer guidance: 64 sec is not recommended."),
            "Details summary must lead with the stop signal, got: \(detail)"
        )
        XCTAssertTrue(
            detail.contains("beyond the manufacturer source range"),
            "The generic beyond-source-range explanation stays present, got: \(detail)"
        )
    }

    func testVelvia50SummaryDetailStaysGenericBelowBoundary() throws {
        let detail = vocabulary.summaryDetailText(for: try bindingState("Velvia 50", metered: 32))
        XCTAssertNil(
            detail,
            "Within the source range there is no detail line and no stop signal."
        )
    }

    // MARK: - Helpers

    /// Synthetic official formula profile carrying `notRecommended`
    /// boundary rows at the given seconds, evaluated at `metered`.
    private func fixtureBindingState(
        sourceRangeThroughSeconds: Double,
        boundaries: [(seconds: Double, message: String)],
        metered: Double
    ) throws -> FilmModeReciprocityBindingState {
        let profile = ReciprocityProfile(
            id: "fixture.stop-signal",
            name: "Stop-signal fixture",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Test"
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        exponent: 1.3,
                        noCorrectionThroughSeconds: 1,
                        sourceRangeThroughSeconds: sourceRangeThroughSeconds
                    )
                )),
            ],
            sourceEvidence: boundaries.map { boundary in
                ReciprocitySourceEvidenceRow(
                    meteredExposure: .exactSeconds(boundary.seconds),
                    adjustments: [
                        .warning(ReciprocityWarning(
                            severity: .notRecommended,
                            message: boundary.message
                        )),
                    ]
                )
            }
        )
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: result,
            presentation: result.confidencePresentation
        )
    }

    private func bindingState(
        _ stock: String,
        metered: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmModeReciprocityBindingState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            file: file,
            line: line
        )
        let profile = try XCTUnwrap(film.profiles.first, file: file, line: line)
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: result,
            presentation: result.confidencePresentation
        )
    }

    private func profile(
        _ stock: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog.",
            file: file,
            line: line
        )
        return try XCTUnwrap(film.profiles.first, file: file, line: line)
    }
}
