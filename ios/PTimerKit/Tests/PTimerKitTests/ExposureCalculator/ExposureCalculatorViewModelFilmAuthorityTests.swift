import XCTest
import PTimerKit

final class FilmModeAuthorityLabelTests: XCTestCase {
    @MainActor
    func testFilmModeDetailsUnofficialProfileShowsUnofficialAuthorityAndFormula() throws {
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

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
    func testFilmModeDetailsOfficialProfileShowsOfficialAuthorityInSubtitle() throws {
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
    func testFilmSelectionDisplayStateOfficialProfileShowsOfficialGuidanceLabel() {
        let viewModel = makeFilmModeViewModel()
        let film = viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" }!
        viewModel.selectPresetFilm(film)

        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Portra 400")
        XCTAssertEqual(
            viewModel.filmSelectionDisplayState.secondaryText,
            "Official guidance",
            "Official Portra 400 must show an explicit 'Official guidance' label on the main row."
        )
    }

    @MainActor
    func testFilmSelectionDisplayStateUnofficialProfileShowsUnofficialPracticalLabel() throws {
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)
        viewModel.selectEntry(unofficialEntry)

        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "Portra 400")
        XCTAssertEqual(
            viewModel.filmSelectionDisplayState.secondaryText,
            "Unofficial practical",
            "Unofficial Portra 400 must show a clear profile qualifier on the main film row."
        )
    }

    @MainActor
    func testFilmSelectionDisplayStateOfficialAndUnofficialProfileAreDistinguishable() throws {
        let viewModel = makeFilmModeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

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
    func testFilmModeDetailsUnofficialProfileShowsFormulaNearGraphWithoutProfileSection() throws {
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

        viewModel.baseShutter = 15
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        XCTAssertNotNil(details.graph, "Formula profile must produce a graph.")
        let formula = try XCTUnwrap(details.graph?.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.34")
        XCTAssertFalse(details.sections.contains { $0.title == "Profile" })
        XCTAssertFalse(details.sections.contains { $0.title == "Formula" })
        XCTAssertTrue(
            details.subtitle?.contains("Unofficial practical") == true,
            "Details subtitle must reuse the same 'Unofficial practical' label as the main film row: \(details.subtitle ?? "<nil>")"
        )
        XCTAssertNil(details.sections.first(where: { $0.title == "Sources" }),
                     "Unofficial profile with no verified source must not show Sources section.")
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

    @MainActor
    func testFilmRowLabelClearedWhenNoFilmSelected() {
        let viewModel = makeFilmModeViewModel()
        XCTAssertNil(
            viewModel.filmSelectionDisplayState.secondaryText,
            "No-film state must not show a profile qualifier."
        )
    }

    @MainActor
    func testFilmModeDetailsDisplayStateIsNonNilForOfficialAndUnofficialProfile() throws {
        // Both official and unofficial Portra 400 must produce a non-nil details display state
        // so the sheet can open for either profile.
        let viewModel = makeFilmModeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

        viewModel.baseShutter = 15
        viewModel.ndStop = 0

        viewModel.selectPresetFilm(officialFilm)
        XCTAssertNotNil(
            viewModel.filmModeDetailsDisplayState,
            "Official Portra 400 must produce a film details display state."
        )

        viewModel.selectEntry(unofficialEntry)
        XCTAssertNotNil(
            viewModel.filmModeDetailsDisplayState,
            "Unofficial Portra 400 must produce a film details display state."
        )
    }

    // MARK: - PTIMER-143 — Normalize Film Details for unofficial reciprocity profiles

    @MainActor
    func testFilmModeDetailsUnofficialProfileSubtitleMatchesMainRowAuthorityLabel() throws {
        // The main film row already labels unofficial Portra 400 as
        // "Unofficial practical" (via `FilmSelectionModel.filmRowAuthorityLabel`).
        // The Details subtitle must reuse the same wording so the user
        // does not read one label on the main row and a different label
        // for the same selected profile inside the sheet.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let mainRowLabel = try XCTUnwrap(
            viewModel.filmSelectionDisplayState.secondaryText,
            "Unofficial Portra 400 must show a main-row authority label."
        )
        XCTAssertEqual(mainRowLabel, "Unofficial practical")

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let subtitle = try XCTUnwrap(details.subtitle)
        XCTAssertTrue(
            subtitle.contains(mainRowLabel),
            "Details subtitle '\(subtitle)' must contain the same authority label as the main row '\(mainRowLabel)'."
        )
        XCTAssertFalse(
            subtitle.contains("Official"),
            "Details subtitle for the unofficial profile must not surface any 'Official' wording: '\(subtitle)'."
        )
    }

    @MainActor
    func testFilmModeDetailsUnofficialProfileSurfacesAuthorityCaveatNote() throws {
        // The unofficial Portra 400 profile carries an explicit
        // authority caveat in its profile-level notes
        // ("Unofficial practical approximation. Not a Kodak-published profile.").
        // That caveat must be visible in the Details sheet so the user
        // can recognize the lower-authority status before trusting the
        // predicted corrected exposure.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectEntry(unofficialEntry)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let detailTexts = collectFilmModeDetailsText(details)
        XCTAssertTrue(
            detailTexts.contains(where: { $0.contains("Not a Kodak-published profile") }),
            "Details must surface the unofficial authority caveat. Collected texts: \(detailTexts)"
        )
    }

    @MainActor
    func testFilmModeDetailsUnofficialProfileDoesNotUseOfficialSourceWording() throws {
        // Authority-leak guard: the unofficial profile path must not
        // borrow wording that exists only for manufacturer-published
        // (converted formula) profiles. "Beyond source range",
        // "manufacturer source range", and the "Source reference" /
        // "Guidance boundary" sections all imply a published Kodak
        // source-range, which the unofficial profile does not have.
        let viewModel = makeFilmModeViewModel()
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

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
    func testFilmModeDetailsOfficialProfileKeepsOfficialLimitedGuidanceBeyondThreshold() throws {
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

    @MainActor
    func testFilmModeDetailsSectionOrderIsConsistentAcrossOfficialAndUnofficialProfile() throws {
        // Profile / Formula metadata sections are removed in this
        // pass; the only stable invariant is that Sources, when
        // present, is the last section in the array.
        let viewModel = makeFilmModeViewModel()
        let officialFilm = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" })
        let unofficialEntry = try unofficialPracticalSelectorEntry(in: viewModel)

        viewModel.baseShutter = 15
        viewModel.ndStop = 0

        for label in ["official", "unofficial"] {
            if label == "official" {
                viewModel.selectPresetFilm(officialFilm)
            } else {
                viewModel.selectEntry(unofficialEntry)
            }

            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
            XCTAssertFalse(
                details.sections.contains { $0.title == "Profile" },
                "[\(label)] Profile metadata section must no longer appear in sections."
            )
            XCTAssertFalse(
                details.sections.contains { $0.title == "Formula" },
                "[\(label)] Formula metadata section must no longer appear in sections."
            )
            if let sourcesIndex = details.sections.firstIndex(where: { $0.title == "Sources" }) {
                XCTAssertEqual(
                    sourcesIndex,
                    details.sections.count - 1,
                    "[\(label)] Sources must be the last section when present."
                )
            }
        }
    }
}
