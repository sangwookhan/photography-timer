// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-159: the film selector stays film-stock focused; a film with
/// more than one profile/model is switched through the model selector —
/// primarily the main-screen segmented control, mirrored as a secondary
/// selector in Reciprocity Details. Switching recomputes the active
/// profile and the Details metadata. Single-profile films show no picker.
final class ReciprocityModelSelectionTests: XCTestCase {

    @MainActor
    func testCommunityPracticalModelHiddenLeavesPortra400WithNoPicker() throws {
        // PTIMER-158: Portra 400's only alternate is the unofficial practical
        // model, hidden for this release. With just the official profile left,
        // the film exposes no model picker. The film itself stays selectable.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertNil(
            viewModel.filmDetailsModelSelection,
            "The unofficial practical model is hidden, leaving a single official model (no picker)."
        )
    }

    @MainActor
    func testSingleProfileFilmHasNoModelSelection() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "HP5 Plus" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        XCTAssertNil(
            viewModel.filmDetailsModelSelection,
            "A single-profile film must not surface a model picker (no selection friction)."
        )
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertNil(details.modelSelection)
    }

    @MainActor
    func testSelectingHiddenCommunityVariantNormalizesToOfficialPrimary() throws {
        // PTIMER-158: activating the now-hidden unofficial practical model
        // normalizes back to the film's official primary profile instead of
        // switching to the community model.
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let unofficialID = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical.id
        viewModel.selectProfileVariant(profileID: unofficialID)

        XCTAssertEqual(
            viewModel.filmReciprocityBindingState?.profile.id,
            film.profiles[0].id,
            "The hidden community model is not activated; the official primary stays active."
        )
    }

    @MainActor
    func testSelectProfileVariantBackToOfficialClearsOverride() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        viewModel.selectProfileVariant(profileID: UnofficialPracticalProfiles.kodakPortra400UnofficialPractical.id)
        XCTAssertNotNil(viewModel.filmReciprocityBindingState?.profile)

        viewModel.selectProfileVariant(profileID: film.profiles[0].id)
        XCTAssertEqual(
            viewModel.filmReciprocityBindingState?.profile.id,
            film.profiles[0].id,
            "Selecting the primary option clears the override back to the official profile."
        )
    }

    @MainActor
    func testMultiModelTableDefaultShowsSourceReferenceWithoutComparison() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let titles = details.sections.map(\.title)
        XCTAssertTrue(titles.contains("Source reference"), "Fomapan keeps its published Source reference: \(titles)")
        // The table default reproduces the anchors exactly, so there is
        // no app-derived deviation to compare.
        XCTAssertFalse(titles.contains("App-derived comparison"), "Table default has nothing to compare: \(titles)")

        let metadata = try XCTUnwrap(details.sections.first { $0.title == "Reciprocity model" })
        XCTAssertEqual(metadata.rows.first { $0.title == "Source" }?.value, "Manufacturer table")
        XCTAssertEqual(metadata.rows.first { $0.title == "Calculation" }?.value, "Log-log table interpolation")
    }

    @MainActor
    func testMultiModelAppDerivedFormulaSeparatesComparisonFromSourceReference() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        // Switch to the non-default app-derived formula model.
        viewModel.selectProfileVariant(profileID: AlternateReciprocityModels.fomapan100AppDerivedFormula.id)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let titles = details.sections.map(\.title)
        XCTAssertTrue(titles.contains("Source reference"), "Source reference present: \(titles)")
        XCTAssertTrue(titles.contains("App-derived comparison"), "App-derived comparison present: \(titles)")

        let sourceText = sectionText(details, "Source reference")
        XCTAssertFalse(
            sourceText.contains("App ") || sourceText.contains(" stop"),
            "Source reference must contain source material only — no app-derived deltas: \(sourceText)"
        )
        let comparisonText = sectionText(details, "App-derived comparison")
        XCTAssertTrue(comparisonText.contains("App "), "The app-derived deltas belong in the comparison section: \(comparisonText)")
    }

    @MainActor
    func testMultiModelTableRendersGraphWithAnchorsAndCurrentPoint() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let graph = try XCTUnwrap(details.graph, "The official table model must render a graph (PTIMER-159).")
        XCTAssertGreaterThanOrEqual(graph.sourcePoints.count, 2)
        XCTAssertFalse(
            graph.sourceReferenceMarkers.isEmpty,
            "The official FOMA anchors must be shown as source-reference markers."
        )
        XCTAssertNotNil(graph.currentPoint, "The current result point must be plotted.")
    }

    @MainActor
    func testMultiModelTableBeyondSourceShowsBeyondSourceRangeWithValueAndNoFormulaWording() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.ndStop = 0
        viewModel.baseShutter = 1000   // past the 100 s published table
        viewModel.selectPresetFilm(film)

        let binding = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertNotNil(
            binding.policyResult.correctedExposureSeconds,
            "1000 s must still return a corrected value (extrapolated), not dead-end."
        )

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(details.summary.badgeText, "Beyond source range")

        let allText = collectFilmModeDetailsText(details).joined(separator: "\n")
        XCTAssertFalse(allText.contains("formula prediction"), "Table model must not say 'formula prediction': \(allText)")
        XCTAssertFalse(allText.contains("No quantified prediction"), "Table model returns a value: \(allText)")
        XCTAssertFalse(allText.contains("Outside supported reciprocity range"), "Use 'Beyond source range' wording: \(allText)")
    }

    @MainActor
    func testMainScreenActiveModelSummaryIsTwoLineSourceAndCalculation() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let summary = try XCTUnwrap(viewModel.activeFilmModelSummary)
        XCTAssertEqual(summary.name, "Official FOMA table")
        XCTAssertEqual(summary.calculation, "Log-log interpolation")
    }

    @MainActor
    func testMultiModelSelectorLabelsAreShortButNamesStayFull() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        // PTIMER-158: the Ohzart community table is hidden for this release,
        // leaving the official table and the app-derived formula (both official).
        let selection = try XCTUnwrap(viewModel.filmDetailsModelSelection)
        XCTAssertEqual(selection.options.map(\.selectorLabel), ["Official table", "App formula"])
        XCTAssertEqual(
            selection.options.map(\.name),
            ["Official FOMA table", "App-derived formula"]
        )
    }

    @MainActor
    func testMultiModelOfficialTableBadgeIsTableDerivedNotFormulaDerived() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10   // within the published table range
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let officialDetails = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(
            officialDetails.summary.badgeText,
            "Table-derived",
            "The official table model must not read as 'Formula-derived'."
        )

        // The app-derived formula alternate keeps formula wording.
        viewModel.selectProfileVariant(profileID: AlternateReciprocityModels.fomapan100AppDerivedFormula.id)
        let appDetails = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(appDetails.summary.badgeText, "Formula-derived")
    }

    @MainActor
    func testMultiModelSubtitleNamesActiveModelNotPlainOfficialGuidance() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let officialDetails = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(officialDetails.subtitle, "Fomapan 100 Classic · Official FOMA table")

        viewModel.selectProfileVariant(profileID: AlternateReciprocityModels.fomapan100AppDerivedFormula.id)
        let appDetails = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(appDetails.subtitle, "Fomapan 100 Classic · App-derived formula")
        XCTAssertFalse(
            appDetails.subtitle?.contains("Official guidance") == true,
            "The app-derived model must not read as plain 'Official guidance'."
        )
    }

    @MainActor
    func testModelSelectorLabelPrefersExplicitElseDerives() {
        // Explicit label wins (a future source-named model like "Ohzart").
        let explicit = makeModelProfile(authority: .unofficial, selectorLabel: "Ohzart")
        XCTAssertEqual(ExposureCalculatorViewModel.modelSelectorLabel(for: explicit), "Ohzart")

        // No explicit label → heuristic fallback (unchanged for current models).
        let derived = makeModelProfile(authority: .unofficial, selectorLabel: nil)
        XCTAssertEqual(ExposureCalculatorViewModel.modelSelectorLabel(for: derived), "Unofficial")
    }

    private func makeModelProfile(
        authority: ReciprocityAuthority,
        selectorLabel: String?
    ) -> ReciprocityProfile {
        ReciprocityProfile(
            id: "test-\(authority.rawValue)-\(selectorLabel ?? "nil")",
            name: "Test model",
            source: ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: authority,
                publisher: ""
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(exponent: 1.3, noCorrectionThroughSeconds: 1)
                )),
            ],
            selectorLabel: selectorLabel
        )
    }

    // MARK: - Helpers

    @MainActor
    private func sectionText(_ details: FilmModeDetailsDisplayState, _ title: String) -> String {
        details.sections
            .filter { $0.title == title }
            .flatMap { $0.rows }
            .map { "\($0.title) \($0.value)" }
            .joined(separator: "\n")
    }
}
