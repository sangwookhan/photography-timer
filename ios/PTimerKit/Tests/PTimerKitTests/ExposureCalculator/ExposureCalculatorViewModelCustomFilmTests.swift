import XCTest
import PTimerKit
import PTimerCore

@MainActor
final class CalculatorViewModelCustomFilmTests: XCTestCase {

    func test_addCustomFilm_appendsToSelectorEntries() {
        let library = CustomFilmLibrary()
        let viewModel = makeViewModel(library: library)
        let initialCount = viewModel.filmSelectorEntries.count

        let film = CustomFilmTestSupport.makeCustomFilm(id: "test-1", stockName: "My Test Film")
        viewModel.addCustomFilm(film)

        XCTAssertEqual(viewModel.customFilms.map(\.id), ["test-1"])
        let entries = viewModel.filmSelectorEntries
        // Single canonical entry — no Quick Access alias duplication.
        XCTAssertEqual(entries.count, initialCount + 1)
        XCTAssertEqual(entries.filter { $0.id == "test-1" }.count, 1)
        XCTAssertTrue(entries.contains { $0.id == "test-1" })
    }

    func test_addCustomFilm_populatesCustomFilmsSection() {
        let library = CustomFilmLibrary()
        let viewModel = makeViewModel(library: library)
        viewModel.addCustomFilm(
            CustomFilmTestSupport.makeCustomFilm(id: "alpha", stockName: "Alpha")
        )
        viewModel.addCustomFilm(
            CustomFilmTestSupport.makeCustomFilm(id: "beta", stockName: "Beta")
        )

        let customSection = viewModel.filmSelectorSections.first {
            $0.manufacturer == ExposureCalculatorViewModel.customFilmsSectionManufacturerLabel
        }

        XCTAssertNotNil(customSection)
        XCTAssertEqual(customSection?.entries.map(\.primaryText), ["Alpha", "Beta"])
    }

    func test_filmSelectorEntries_customFilmsAppearAheadOfManufacturerSections() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        viewModel.addCustomFilm(
            CustomFilmTestSupport.makeCustomFilm(id: "alpha", stockName: "Alpha")
        )

        let entries = viewModel.filmSelectorEntries
        let customIndex = entries.firstIndex { $0.id == "alpha" }
        let firstPresetIndex = entries.firstIndex { entry in
            guard let film = entry.film else { return false }
            return film.kind == .preset
        }

        XCTAssertNotNil(customIndex)
        XCTAssertNotNil(firstPresetIndex)
        if let customIndex, let firstPresetIndex {
            XCTAssertLessThan(customIndex, firstPresetIndex)
        }
    }

    func test_filmSelectorEntries_customEntry_usesCustomSupportState() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        viewModel.addCustomFilm(
            CustomFilmTestSupport.makeCustomFilm(id: "custom-1", stockName: "Custom")
        )

        let entry = viewModel.filmSelectorEntries.first { $0.id == "custom-1" }
        XCTAssertEqual(entry?.supportState, .userDefinedFormulaPrediction)
        XCTAssertEqual(entry?.supportState.unofficialBadgeText, "Custom")
    }

    func test_filmSelectorEntries_presetEntries_unchanged() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let presetEntriesWithoutCustom = viewModel.filmSelectorEntries
            .filter { entry in
                guard let film = entry.film else { return entry.id == "no-film" }
                return film.kind == .preset || entry.profileOverride != nil
            }

        viewModel.addCustomFilm(
            CustomFilmTestSupport.makeCustomFilm(id: "custom-1", stockName: "Custom")
        )

        let presetEntriesWithCustom = viewModel.filmSelectorEntries
            .filter { entry in
                guard let film = entry.film else { return entry.id == "no-film" }
                return film.kind == .preset || entry.profileOverride != nil
            }

        XCTAssertEqual(
            presetEntriesWithoutCustom.map(\.id),
            presetEntriesWithCustom.map(\.id)
        )
    }

    func test_selectCustomFilm_marksItAsSelectedSelectorEntry() {
        let viewModel = makeViewModel(library: CustomFilmLibrary())
        let film = CustomFilmTestSupport.makeCustomFilm(id: "selected", stockName: "Selected")
        viewModel.addCustomFilm(film)
        let entry = viewModel.filmSelectorEntries.first { $0.id == "selected" }
        XCTAssertNotNil(entry, "Custom film entry must exist before selection")

        viewModel.selectEntry(entry!)

        XCTAssertEqual(viewModel.selectedSelectorEntryID, "selected")
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, "selected")
        XCTAssertEqual(viewModel.selectedPresetFilm?.kind, .custom)
    }

    // MARK: - Helpers

    private func makeViewModel(library: CustomFilmLibrary) -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            customFilmLibrary: library
        )
    }
}
