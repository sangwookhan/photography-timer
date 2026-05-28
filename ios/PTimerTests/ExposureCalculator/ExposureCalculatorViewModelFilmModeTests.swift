import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelFilmModeTests: XCTestCase {
    @MainActor
    func testFilmRowDefaultsToNoFilmSelectorState() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        XCTAssertNil(viewModel.activeCalculatorContext.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
        XCTAssertFalse(viewModel.canShowFilmDetails)
    }

    @MainActor
    func testSelectingPresetFilmUpdatesActiveCalculatorContextAndDisplayState() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )

        viewModel.selectPresetFilm(film)

        XCTAssertEqual(viewModel.activeCalculatorContext.selectedPresetFilm, film)
        XCTAssertTrue(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Tri-X 400")
        XCTAssertFalse(viewModel.filmSelectionDisplayState.primaryText.contains("ISO"))
        XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, "Official guidance")
    }

    @MainActor
    func testReplacingPresetFilmUpdatesActiveCalculatorContext() throws {
        let viewModel = makeFilmModeViewModel()
        let firstFilm = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        let replacementFilm = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" }
        )

        viewModel.selectPresetFilm(firstFilm)
        viewModel.selectPresetFilm(replacementFilm)

        XCTAssertEqual(viewModel.activeCalculatorContext.selectedPresetFilm, replacementFilm)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Portra 400")
        XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, "Official guidance")
    }

    @MainActor
    func testFilmSelectorEntriesKeepISOAsSecondaryMetadata() {
        let viewModel = makeFilmModeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)

        // Every preset row carries an ISO secondary. Films with a
        // registered unofficial practical profile (Portra 400 today)
        // surface as a second row that shares the canonical name and
        // ISO; `supportState` drives the unofficial badge. Spot-check
        // exemplars without coupling to the full catalog ordering.
        let portraOfficial = viewModel.filmSelectorEntries.first { entry in
            entry.primaryText == "Portra 400" && entry.profileOverride == nil
        }
        let portraUnofficial = viewModel.filmSelectorEntries.first { entry in
            entry.film?.id == "kodak-portra-400" && entry.profileOverride != nil
        }
        XCTAssertNotNil(portraOfficial, "Portra 400 official row should exist.")
        XCTAssertEqual(portraOfficial?.secondaryText, "ISO 400")
        XCTAssertEqual(portraOfficial?.supportState, .officialLimitedGuidance)
        XCTAssertNotNil(portraUnofficial, "Portra 400 unofficial row should exist with a profile override.")
        XCTAssertEqual(portraUnofficial?.primaryText, "Portra 400", "Unofficial row keeps the canonical name; the badge carries the qualifier.")
        XCTAssertEqual(portraUnofficial?.secondaryText, "ISO 400", "Unofficial row's right column is the ISO speed, not the qualifier.")
        XCTAssertEqual(portraUnofficial?.supportState, .unofficialPractical)
        XCTAssertNotNil(portraUnofficial?.profileOverride, "Unofficial row carries a profile override so the model can apply it on selection.")
        XCTAssertNotEqual(
            portraOfficial?.id,
            portraUnofficial?.id,
            "Official and unofficial rows must use distinct ids so scroll-to-selection lands on the correct variant."
        )

        let exemplars: [(name: String, expectedSecondary: String)] = [
            ("Tri-X 400", "ISO 400"),
            ("HP5 Plus", "ISO 400"),
            ("Velvia 50", "ISO 50"),
            ("Delta 3200", "ISO 3200"),
        ]
        for exemplar in exemplars {
            let entry = viewModel.filmSelectorEntries.first { entry in
                entry.primaryText == exemplar.name && entry.profileOverride == nil
            }
            XCTAssertNotNil(entry, "Missing selector entry for \(exemplar.name).")
            XCTAssertEqual(entry?.secondaryText, exemplar.expectedSecondary, "Secondary text mismatch for \(exemplar.name).")
        }
    }

    @MainActor
    func testChangingFromPresetFilmToNoFilmReturnsToDigitalWorkflow() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first)

        viewModel.selectPresetFilm(film)
        viewModel.clearSelectedPresetFilm()

        XCTAssertNil(viewModel.activeCalculatorContext.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectionDisplayState.secondaryText)
        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertNil(viewModel.filmModeExposureResultState)
    }

    @MainActor
    func testSelectingPresetFilmActivatesFilmWorkflowAndReciprocityBinding() throws {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
        viewModel.scaleMode = .fullStop

        viewModel.baseShutter = 1
        viewModel.ndStop = 0

        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)

        let film = try XCTUnwrap(viewModel.availablePresetFilms.last)
        viewModel.selectPresetFilm(film)

        let bindingState = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.film.id, film.id)
        XCTAssertEqual(bindingState.profile.source.kind, .manufacturerPublished)
        XCTAssertEqual(bindingState.profile.source.authority, .official)
        XCTAssertTrue(bindingState.policyResult.hasCalculatedExposureTime)
        XCTAssertTrue(bindingState.presentation.returnsCalculatedExposureTime)
        XCTAssertTrue(viewModel.isFilmWorkflowActive)
    }

    @MainActor
    func testNoFilmBehavesAsDigitalWorkflow() throws {
        let viewModel = makeFilmModeViewModel()

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertEqual(viewModel.calculationResult, .success(
            ExposureCalculationResult(
                baseShutterSeconds: 1.0 / 30.0,
                stop: 6,
                resultShutterSeconds: 2
            )
        ))
    }

    // MARK: - Film selector sections

    @MainActor
    func testFilmSelectorSectionsGroupByManufacturerWithNoFilmAsHeaderlessLeadingSection() throws {
        let viewModel = makeFilmModeViewModel()
        let sections = viewModel.filmSelectorSections

        // The leading section is the "No film" sentinel followed by
        // the explicit "New custom film" action row — both headerless
        // (manufacturer == nil) so the view renders them as plain
        // rows outside any group card. Every subsequent section is a
        // manufacturer group card.
        let leading = try XCTUnwrap(sections.first, "Sections must not be empty.")
        XCTAssertEqual(leading.id, "no-film")
        XCTAssertNil(leading.manufacturer)
        XCTAssertEqual(leading.entries.map(\.primaryText), ["No film", "New custom film"])

        let manufacturerSections = Array(sections.dropFirst())
        XCTAssertFalse(manufacturerSections.isEmpty, "Catalog should produce at least one manufacturer section.")

        // No section has zero entries.
        for section in sections {
            XCTAssertFalse(section.entries.isEmpty, "Section '\(section.id)' must not be empty.")
        }

        // Every manufacturer section's entries share its manufacturer label.
        for section in manufacturerSections {
            let manufacturer = try XCTUnwrap(section.manufacturer, "Non-leading section must have a manufacturer.")
            XCTAssertEqual(section.id, manufacturer)
            for entry in section.entries {
                XCTAssertEqual(
                    entry.manufacturer,
                    manufacturer,
                    "Entry '\(entry.primaryText)' is in the '\(manufacturer)' section but reports manufacturer '\(entry.manufacturer ?? "nil")'."
                )
            }
        }

        // Manufacturers appear in alphabetical order (case-insensitive)
        // so the grouped cards are predictably ordered.
        let manufacturers = manufacturerSections.compactMap(\.manufacturer)
        let sortedManufacturers = manufacturers.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        XCTAssertEqual(manufacturers, sortedManufacturers)

        // The flattened section entries must match the flat
        // filmSelectorEntries list — sections are a regrouping, not a
        // filtered view, so scroll-to-current-selection by entry id
        // works regardless of which property the view consumes.
        XCTAssertEqual(
            sections.flatMap(\.entries).map(\.id),
            viewModel.filmSelectorEntries.map(\.id)
        )

        // Spot-check: Portra 400 official and unofficial rows live in the
        // same Kodak section, contiguously, so the user does not have to
        // hunt for the unofficial variant elsewhere in the list.
        let kodakSection = try XCTUnwrap(
            manufacturerSections.first(where: { $0.manufacturer == "Kodak" }),
            "Kodak manufacturer section is required."
        )
        let portraIndices = kodakSection.entries.enumerated().compactMap { idx, entry in
            entry.primaryText.hasPrefix("Portra 400") ? idx : nil
        }
        XCTAssertEqual(portraIndices.count, 2, "Kodak section should contain official + unofficial Portra 400 rows.")
        if portraIndices.count == 2 {
            XCTAssertEqual(portraIndices[1] - portraIndices[0], 1, "Official and unofficial Portra 400 rows must be contiguous in the Kodak section.")
        }
    }

    @MainActor
    func testFilmSelectorEntriesKeepNoFilmFirstAndShowISOWhenAvailable() {
        let viewModel = makeFilmModeViewModel()

        XCTAssertEqual(viewModel.filmSelectorEntries.first?.id, "no-film")
        XCTAssertEqual(viewModel.filmSelectorEntries.first?.primaryText, "No film")
        XCTAssertNil(viewModel.filmSelectorEntries.first?.secondaryText)

        // The leading "No film" sentinel must precede every preset film entry.
        // Preset films carry an inferred ISO secondary when the canonical
        // name / brand label / aliases contain a recognized speed token, and
        // films registered in UnofficialPracticalProfiles add an "Unofficial"
        // secondary alongside their official primary entry.
        let entriesAfterNoFilm = viewModel.filmSelectorEntries.dropFirst()
        XCTAssertGreaterThanOrEqual(entriesAfterNoFilm.count, viewModel.availablePresetFilms.count)
        for entry in entriesAfterNoFilm {
            if let secondary = entry.secondaryText {
                XCTAssertTrue(
                    secondary.hasPrefix("ISO ") || secondary == "Unofficial",
                    "Selector secondary text '\(secondary)' for '\(entry.primaryText)' must be ISO metadata or 'Unofficial'."
                )
            }
        }
    }
}
