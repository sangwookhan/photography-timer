import XCTest
@testable import PTimer

final class FilmModeAuthorityLabelTests: XCTestCase {
    @MainActor
    func testFilmModeDetailsUnofficialPortra400ShowsUnofficialAuthorityAndFormula() throws {
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPortra400SelectorEntry(in: viewModel)

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        // Profile + Formula metadata sections are no longer
        // rendered; the formula expression now lives next to the
        // graph and the film authority sits in the subtitle.
        let formula = try XCTUnwrap(details.graph?.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.34")
        XCTAssertEqual(details.summary.badgeText, "Formula-derived")
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
        XCTAssertFalse(details.sections.contains { $0.title == "Formula" })
        XCTAssertTrue(
            details.subtitle?.contains("Unofficial practical") == true,
            "Details subtitle must reuse the same 'Unofficial practical' label as the main film row so the surfaces agree: \(details.subtitle ?? "<nil>")"
        )
        XCTAssertNil(details.sections.first(where: { $0.title == "Sources" }),
                     "Unofficial profile with no verified source metadata must not show Sources section.")
    }

    @MainActor
    func testFilmModeDetailsOfficialPortra400ShowsOfficialAuthorityInSubtitle() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertTrue(
            details.subtitle?.contains("Official guidance") == true,
            "Authority is surfaced in the subtitle: \(details.subtitle ?? "<nil>")"
        )
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
    }

    @MainActor
    func testFilmSelectionDisplayStateOfficialAndUnofficialPortra400AreDistinguishable() throws {
        let viewModel = makeFilmModeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try unofficialPortra400SelectorEntry(in: viewModel)

        viewModel.selectPresetFilm(officialFilm)
        let officialDisplay = viewModel.filmSelectionDisplayState

        viewModel.selectEntry(unofficialEntry)
        let unofficialDisplay = viewModel.filmSelectionDisplayState

        XCTAssertEqual(officialDisplay.primaryText, unofficialDisplay.primaryText,
                       "Primary film name should be identical for official and unofficial Portra 400.")
        XCTAssertNotEqual(
            officialDisplay.secondaryText,
            unofficialDisplay.secondaryText,
            "Official and unofficial Portra 400 must produce different secondary labels so the user can distinguish them."
        )
        XCTAssertEqual(officialDisplay.secondaryText, "Official guidance")
        XCTAssertEqual(unofficialDisplay.secondaryText, "Unofficial practical")
    }

    @MainActor
    func testFilmRowOfficialGuidanceLabelAppliesToAllOfficialPresetFilms() {
        // Every preset film with authority=official must show "Official guidance" on the main row.
        // This ensures the label is consistent across all catalog films, not only Portra 400.
        let viewModel = makeFilmModeViewModel()
        for film in viewModel.availablePresetFilms {
            viewModel.selectPresetFilm(film)
            XCTAssertEqual(
                viewModel.filmSelectionDisplayState.secondaryText,
                "Official guidance",
                "\(film.canonicalStockName) has authority=official and must show 'Official guidance'."
            )
        }
    }

    // MARK: - PTIMER-143 — Normalize Film Details for unofficial reciprocity profiles

    @MainActor
    func testFilmModeDetailsUnofficialPortra400DoesNotUseOfficialSourceWording() throws {
        // Authority-leak guard: the unofficial profile path must not
        // borrow wording that exists only for manufacturer-published
        // (converted formula) profiles. "Beyond source range",
        // "manufacturer source range", and the "Source reference" /
        // "Guidance boundary" sections all imply a published Kodak
        // source-range, which the unofficial profile does not have.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPortra400SelectorEntry(in: viewModel)

        viewModel.baseShutter = 30
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        let forbiddenWording = [
            "Beyond source range",
            "manufacturer source range",
            "manufacturer-supported boundary",
            "published source range",
            "published reference",
        ]
        let allText = collectFilmModeDetailsText(details).joined(separator: "\n")
        for fragment in forbiddenWording {
            XCTAssertFalse(
                allText.contains(fragment),
                "Unofficial Portra 400 Details must not use '\(fragment)' wording (would imply a manufacturer-published source). Collected text:\n\(allText)"
            )
        }

        // Section-title guard: the source-evidence section titles are
        // reserved for converted formula profiles that carry published
        // source rows. The unofficial profile carries no `sourceEvidence`
        // and must produce neither title.
        let sectionTitles = details.sections.map(\.title)
        XCTAssertFalse(
            sectionTitles.contains("Source reference"),
            "Unofficial profile must not render a 'Source reference' section: \(sectionTitles)"
        )
        XCTAssertFalse(
            sectionTitles.contains("Guidance boundary"),
            "Unofficial profile must not render a 'Guidance boundary' section: \(sectionTitles)"
        )
    }

    @MainActor
    func testFilmModeDetailsOfficialPortra400KeepsOfficialLimitedGuidanceBeyondThreshold() throws {
        // The official Portra 400 profile must remain the default
        // official limited-guidance profile and must not expose any
        // quantified prediction beyond the published 10 s threshold
        // (PTIMER-168 corrected the Portra no-correction band to 10 s).
        let viewModel = makeFilmModeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })

        viewModel.baseShutter = 30      // metered exposure well beyond the 10 s no-correction threshold
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(officialFilm)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let subtitle = try XCTUnwrap(details.subtitle)
        XCTAssertTrue(
            subtitle.contains("Official guidance"),
            "Official Portra 400 subtitle must keep its 'Official guidance' label: \(subtitle)"
        )
        XCTAssertEqual(details.summary.badgeText, "No quantified prediction")

        let binding = try XCTUnwrap(viewModel.filmReciprocityBindingState)
        XCTAssertNil(
            binding.policyResult.correctedExposureSeconds,
            "Official Portra 400 must not produce a quantified corrected exposure beyond the official threshold."
        )
    }

    @MainActor
    func testFilmModeDetailsSourceBackedProfilesStillShowSourceRangeWordingBeyondSupportedBound() throws {
        // Regression guard for manufacturer source-backed profiles —
        // both still-converted-formula profiles (Provia 100F, Velvia 50,
        // Velvia 100, Acros II) and the PTIMER-168 table-origin profiles
        // (Tri-X 400, T-MAX 100, T-MAX 400): an input beyond their
        // supported range must still produce "Beyond source range"
        // wording. The unofficial-profile changes must not regress this.
        let sourceBackedStockNames = [
            "Provia 100F",
            "Tri-X 400",
            "T-MAX 100",
            "T-MAX 400",
            "Velvia 50",
            "Velvia 100",
            "Acros II",
        ]
        for stockName in sourceBackedStockNames {
            let viewModel = makeFilmModeViewModel()
            // A missing catalog entry is a real regression — a silent
            // `continue` would hide a source-backed profile that
            // disappeared from the launch catalog. The assertion fails
            // the test instead so coverage stays honest.
            let film = try XCTUnwrap(
                viewModel.availablePresetFilms.first(where: { $0.canonicalStockName == stockName }),
                "Source-backed profile '\(stockName)' must remain in the launch catalog."
            )
            viewModel.baseShutter = 4_000     // pushed past every profile's supported bound
            viewModel.ndStop = 0
            viewModel.selectPresetFilm(film)

            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState, "Missing details for \(stockName)")
            XCTAssertEqual(
                details.summary.badgeText,
                "Beyond source range",
                "Source-backed profile '\(stockName)' must still surface 'Beyond source range' wording past its supported bound."
            )
        }
    }

}
