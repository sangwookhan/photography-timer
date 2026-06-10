import XCTest
import PTimerKit
import PTimerCore

/// Behavior contract for a film stock that ships one official catalog
/// profile plus off-catalog alternate models (a community table and an
/// app-derived formula) under the same stock. The contracts here are the
/// cross-cutting coexistence/selection behaviors the table-log-log
/// source-data contract does not own: the catalog registry shape, each
/// alternate's provenance identity, view-model variant selection wording,
/// and source-neutral beyond-source notes.
///
/// Provenance is a case-data axis. Fomapan 100 Classic (official FOMA
/// table + Ohzart community table + app-derived formula) is the first
/// case row; adding another multi-model stock is another row. Source /
/// model names ("Ohzart", "FOMA") live only in case data, expected
/// user-visible strings, production profile IDs, assertion messages, and
/// comments — never in a function, class, helper, or type name.
@MainActor
final class ReciprocityMultiModelCoexistenceTests: XCTestCase {

    private struct CoexistenceCase {
        let film: String
        let filmID: String
        let alternateProfileID: String
        let appDerivedProfileID: String
        /// Off-catalog alternate order shown after the default profile.
        let alternatesOrder: [String]
        // Default (official) profile.
        let defaultSourceModel: ReciprocitySourceModel
        let defaultCalculationModel: ReciprocityCalculationModel
        let defaultSummaryText: String
        let defaultMetadataSource: String
        let defaultBeyondSample: Double
        let defaultBeyondNote: String
        // Community alternate profile.
        let alternateSourceModel: ReciprocitySourceModel
        let alternateCalculationModel: ReciprocityCalculationModel
        let alternateAuthority: ReciprocityAuthority
        let alternateConfidence: ReciprocityConfidence
        let alternateSelectorLabel: String
        let alternateSummaryText: String
        let alternateMetadataSource: String
        let alternateMetadataCalculation: String
        let alternateBeyondSample: Double
        let alternateBeyondNote: String
        /// An in-range value (bracketSample) that must interpolate
        /// strictly between two bracketing anchors (bracketLower/Upper).
        let bracketSample: Double
        let bracketLower: Double
        let bracketUpper: Double
        let alternateSelectionSample: Double
        let defaultSelectionSample: Double
        /// Substrings (matched case-insensitively) that must NOT appear in
        /// the community alternate's Details sheet.
        let forbiddenInAlternateSheet: [String]
        let requiredAlternateCaveat: String
        let appDerivedSubtitle: String
    }

    private let cases: [CoexistenceCase] = [
        CoexistenceCase(
            film: "Fomapan 100 Classic",
            filmID: "foma-fomapan-100",
            alternateProfileID: "foma-fomapan-100-ohzart-community-table",
            appDerivedProfileID: "foma-fomapan-100-app-formula",
            alternatesOrder: ["foma-fomapan-100-ohzart-community-table", "foma-fomapan-100-app-formula"],
            defaultSourceModel: .manufacturerTable,
            defaultCalculationModel: .tableLogLogInterpolation,
            defaultSummaryText: "Log-log interpolation of the official table",
            defaultMetadataSource: "Manufacturer table",
            defaultBeyondSample: 1000,
            defaultBeyondNote: "Source table ends at 100 sec.",
            alternateSourceModel: .practicalCommunityGuidance,
            alternateCalculationModel: .tableLogLogInterpolation,
            alternateAuthority: .unofficial,
            alternateConfidence: .medium,
            alternateSelectorLabel: "Ohzart",
            alternateSummaryText: "Log-log interpolation of the community table",
            alternateMetadataSource: "Practical / community guidance",
            alternateMetadataCalculation: "Log-log table interpolation",
            alternateBeyondSample: 120,
            alternateBeyondNote: "Source table ends at 60 sec.",
            bracketSample: 10, bracketLower: 35, bracketUpper: 90,
            alternateSelectionSample: 8,
            defaultSelectionSample: 10,
            forbiddenInAlternateSheet: ["app-derived", "manufacturer", "official foma"],
            requiredAlternateCaveat: "Not FOMA-published data",
            appDerivedSubtitle: "App-derived formula"
        ),
    ]

    // MARK: - Helpers

    private func defaultProfile(for c: CoexistenceCase) throws -> ReciprocityProfile {
        try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == c.filmID }).profiles[0]
    }

    private func alternateProfile(for c: CoexistenceCase) throws -> ReciprocityProfile {
        try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: c.filmID).first { $0.id == c.alternateProfileID },
            "\(c.film): the community alternate must be registered as an alternate model."
        )
    }

    private func corrected(_ profile: ReciprocityProfile, at metered: Double) -> Double? {
        ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: profile, meteredExposureSeconds: metered)
            .correctedExposureSeconds
    }

    // MARK: - Catalog registry

    func testFilmStockShipsOneCatalogProfileWithAlternatesOffCatalog() throws {
        for c in cases {
            let stockEntries = LaunchPresetFilmCatalog.films.filter { $0.canonicalStockName == c.film }
            XCTAssertEqual(stockEntries.count, 1, "\(c.film) must remain a single top-level film stock.")
            XCTAssertEqual(stockEntries[0].profiles.count, 1, "\(c.film) must ship exactly one catalog profile.")
            for alternateID in c.alternatesOrder {
                XCTAssertFalse(
                    LaunchPresetFilmCatalog.films.contains { $0.id == alternateID },
                    "\(c.film): \(alternateID) must be an alternate model only, not a top-level catalog entry."
                )
            }
        }
    }

    func testDefaultProfileStaysOfficialAndAlternatesAreOffCatalog() throws {
        for c in cases {
            let basis = try XCTUnwrap(defaultProfile(for: c).modelBasis)
            XCTAssertEqual(basis.sourceModel, c.defaultSourceModel, "\(c.film): default source model")
            XCTAssertEqual(basis.calculationModel, c.defaultCalculationModel, "\(c.film): default calculation model")
            XCTAssertEqual(try defaultProfile(for: c).source.authority, .official, "\(c.film): default authority")

            XCTAssertEqual(
                AlternateReciprocityModels.alternates(forFilmID: c.filmID).map(\.id),
                c.alternatesOrder,
                "\(c.film): alternate order"
            )
            // Session restore can reconstruct the persisted alternate override.
            XCTAssertEqual(AlternateReciprocityModels.profile(withID: c.alternateProfileID)?.id, c.alternateProfileID, "\(c.film): alternate round-trips by id")
        }
    }

    // MARK: - Alternate provenance identity

    func testAlternateProfileIdentityMatchesItsProvenance() throws {
        for c in cases {
            let profile = try alternateProfile(for: c)
            let basis = try XCTUnwrap(profile.modelBasis)
            XCTAssertEqual(basis.sourceModel, c.alternateSourceModel, "\(c.film): alternate source model")
            XCTAssertEqual(basis.calculationModel, c.alternateCalculationModel, "\(c.film): alternate calculation model")
            XCTAssertEqual(profile.source.authority, c.alternateAuthority, "\(c.film): alternate authority")
            XCTAssertEqual(profile.source.confidence, c.alternateConfidence, "\(c.film): alternate confidence")
            XCTAssertEqual(profile.selectorLabel, c.alternateSelectorLabel, "\(c.film): alternate selector label")
            XCTAssertFalse(AlternateReciprocityModels.isAppDerivedModel(id: profile.id), "\(c.film): alternate is not app-derived")
            XCTAssertTrue(profile.usesTableInterpolation, "\(c.film): alternate uses table interpolation")
            XCTAssertFalse(profile.isConvertedFormulaProfile, "\(c.film): alternate is not a converted formula")
        }
    }

    func testAlternateInRangeInterpolationStaysBetweenBracketingAnchors() throws {
        for c in cases {
            let value = try XCTUnwrap(corrected(alternateProfile(for: c), at: c.bracketSample), "\(c.film): alternate must compute an in-range value.")
            XCTAssertGreaterThan(value, c.bracketLower, "\(c.film) @ \(c.bracketSample)s: must interpolate above the lower anchor.")
            XCTAssertLessThan(value, c.bracketUpper, "\(c.film) @ \(c.bracketSample)s: must interpolate below the upper anchor.")
        }
    }

    // MARK: - View-model variant selection wording

    func testSelectingAlternateReadsAsItsProvenanceNotOfficialNorAppDerived() throws {
        for c in cases {
            let viewModel = makeFilmModeViewModel()
            let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == c.film })
            viewModel.baseShutter = c.alternateSelectionSample
            viewModel.ndStop = 0
            viewModel.selectPresetFilm(film)
            viewModel.selectProfileVariant(profileID: c.alternateProfileID)

            XCTAssertEqual(viewModel.filmReciprocityBindingState?.profile.id, c.alternateProfileID, "\(c.film): alternate is the active profile")
            XCTAssertEqual(viewModel.filmDetailsModelSelection?.activeOptionID, c.alternateProfileID, "\(c.film): alternate is the active option")

            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
            XCTAssertEqual(details.summary.badgeText, "Table-derived", "\(c.film): honest table-derived badge")
            XCTAssertEqual(details.summary.summaryText, c.alternateSummaryText, "\(c.film): alternate summary wording")

            let metadata = try XCTUnwrap(details.sections.first { $0.title == "Reciprocity model" })
            XCTAssertEqual(metadata.rows.first { $0.title == "Source" }?.value, c.alternateMetadataSource, "\(c.film): alternate source metadata")
            XCTAssertEqual(metadata.rows.first { $0.title == "Calculation" }?.value, c.alternateMetadataCalculation, "\(c.film): alternate calculation metadata")

            let titles = details.sections.map(\.title)
            XCTAssertTrue(titles.contains("Source reference"), "\(c.film): alternate keeps a Source reference: \(titles)")
            XCTAssertFalse(titles.contains("App-derived comparison"), "\(c.film): a table model has nothing to compare: \(titles)")

            let allText = collectFilmModeDetailsText(details).joined(separator: "\n").lowercased()
            for forbidden in c.forbiddenInAlternateSheet {
                XCTAssertFalse(allText.contains(forbidden.lowercased()), "\(c.film): alternate sheet must not contain '\(forbidden)'.")
            }
            XCTAssertTrue(
                collectFilmModeDetailsText(details).joined(separator: "\n").contains(c.requiredAlternateCaveat),
                "\(c.film): the community caveat '\(c.requiredAlternateCaveat)' must be visible."
            )
        }
    }

    func testDefaultProfileStillReadsAsOfficialWhenAlternatesExist() throws {
        for c in cases {
            let viewModel = makeFilmModeViewModel()
            let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == c.film })
            viewModel.baseShutter = c.defaultSelectionSample
            viewModel.ndStop = 0
            viewModel.selectPresetFilm(film)

            XCTAssertEqual(viewModel.filmDetailsModelSelection?.activeOptionID, film.profiles[0].id, "\(c.film): default profile is active with no override")
            let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
            XCTAssertEqual(details.summary.summaryText, c.defaultSummaryText, "\(c.film): default summary wording")
            let metadata = try XCTUnwrap(details.sections.first { $0.title == "Reciprocity model" })
            XCTAssertEqual(metadata.rows.first { $0.title == "Source" }?.value, c.defaultMetadataSource, "\(c.film): default source metadata")
        }
    }

    func testActiveFilmRowSubtitleForAppDerivedAlternateIsNotOfficialGuidance() throws {
        for c in cases {
            let viewModel = makeFilmModeViewModel()
            let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == c.film })
            viewModel.baseShutter = c.defaultSelectionSample
            viewModel.ndStop = 0
            viewModel.selectPresetFilm(film)
            viewModel.selectProfileVariant(profileID: c.appDerivedProfileID)

            XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, c.appDerivedSubtitle, "\(c.film): app-derived subtitle")
            XCTAssertNotEqual(viewModel.filmSelectionDisplayState.secondaryText, "Official guidance", "\(c.film): app-derived must not read as official guidance")
        }
    }

    // MARK: - Source-neutral beyond-source notes

    func testAlternateBeyondSourceNoteIsSourceNeutralNotManufacturer() throws {
        for c in cases {
            let result = ReciprocityCalculationPolicyEvaluator()
                .evaluate(profile: try alternateProfile(for: c), meteredExposureSeconds: c.alternateBeyondSample)
            let noteText = result.metadata.notes.map(\.text).joined(separator: "\n")
            XCTAssertTrue(noteText.contains(c.alternateBeyondNote), "\(c.film): alternate beyond-source note. Got: \(noteText)")
            XCTAssertFalse(noteText.contains("Manufacturer table"), "\(c.film): community alternate is not manufacturer data: \(noteText)")
            XCTAssertFalse(noteText.contains("manufacturer source range"), "\(c.film): \(noteText)")
        }
    }

    func testDefaultBeyondSourceNoteIsSourceNeutral() throws {
        for c in cases {
            let result = ReciprocityCalculationPolicyEvaluator()
                .evaluate(profile: try defaultProfile(for: c), meteredExposureSeconds: c.defaultBeyondSample)
            let noteText = result.metadata.notes.map(\.text).joined(separator: "\n")
            XCTAssertTrue(noteText.contains(c.defaultBeyondNote), "\(c.film): default beyond-source note. Got: \(noteText)")
            XCTAssertFalse(noteText.contains("Manufacturer table"), "\(c.film): \(noteText)")
        }
    }
}
