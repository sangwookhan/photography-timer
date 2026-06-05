import XCTest
@testable import PTimer
import PTimerKit

extension XCTestCase {
    @MainActor
    func makeFilmModeViewModel() -> ExposureCalculatorViewModel {
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

    /// PTIMER-159: the unofficial Portra 400 practical profile is no
    /// longer a duplicate top-level film-selector entry — profile/model
    /// selection moved into Reciprocity Details. Tests that need the
    /// unofficial profile active reconstruct the selector entry the
    /// catalog used to vend and select it; selecting that entry sets the
    /// same `selectedProfileOverride` the Details model picker now sets,
    /// so the resulting calculator/Details state is identical.
    @MainActor
    func unofficialPortra400SelectorEntry(
        in viewModel: ExposureCalculatorViewModel
    ) throws -> FilmSelectorEntry {
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" },
            "Portra 400 must remain in the launch catalog."
        )
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        return FilmSelectorEntry(
            id: profile.id,
            primaryText: film.canonicalStockName,
            secondaryText: FilmSelectionModel.filmRowISOText(for: film),
            manufacturer: film.manufacturer,
            film: film,
            profileOverride: profile,
            supportState: FilmSelectorSupportPresenter.makeSupportState(
                for: film,
                profileOverride: profile
            )
        )
    }

    /// Collects every user-visible text fragment from the Details
    /// display state so the assertions can scan for forbidden /
    /// required wording without coupling to a single field.
    @MainActor
    func collectFilmModeDetailsText(_ details: FilmModeDetailsDisplayState) -> [String] {
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

    func makeFallbackFormulaDetailsFilm() -> FilmIdentity {
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
                                    noCorrectionThroughSeconds: 1
                                )
                            )
                        ),
                    ]
                ),
            ],
            userMetadata: nil
        )
    }

    func makeMinimalDetailsFilm() -> FilmIdentity {
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
                        ),
                    ]
                ),
            ],
            userMetadata: nil
        )
    }

    func makeURLBackedDetailsFilm() -> FilmIdentity {
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
                        ),
                    ]
                ),
            ],
            userMetadata: nil
        )
    }
}
