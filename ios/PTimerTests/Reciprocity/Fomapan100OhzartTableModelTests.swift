import XCTest
@testable import PTimer

/// PTIMER-164: the Ohzart community practical table is a separate
/// unofficial, table-derived alternate model under the single Fomapan
/// 100 Classic film stock. It reproduces the community anchors exactly
/// via log-log interpolation (the same calculation the official FOMA
/// table uses), shares FOMA's 0.5 s no-correction boundary, ends its
/// published range at 60 s, and never presents as official manufacturer
/// data or as the app-derived formula. The default official FOMA table
/// is unchanged.
final class Fomapan100OhzartTableModelTests: XCTestCase {

    private let filmID = "foma-fomapan-100"
    private let ohzartID = "foma-fomapan-100-ohzart-community-table"

    /// (metered, corrected) Ohzart rows from the Community Sources Data
    /// wiki (mirrors `https://ohzart1.tistory.com/78`).
    private let ohzartAnchors: [(metered: Double, corrected: Double)] = [
        (1, 1.9),
        (2, 5),
        (4, 13),
        (8, 35),
        (15, 90),
        (30, 265),
        (60, 795),
    ]

    private func ohzartProfile() throws -> ReciprocityProfile {
        try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: filmID).first { $0.id == ohzartID },
            "Ohzart must be registered as a Fomapan 100 alternate model."
        )
    }

    private func corrected(_ profile: ReciprocityProfile, at metered: Double) -> Double? {
        ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: profile, meteredExposureSeconds: metered)
            .correctedExposureSeconds
    }

    // MARK: - Film stock / model registry

    func testFomapan100RemainsASingleFilmStockWithOneCatalogProfile() throws {
        let films = LaunchPresetFilmCatalog.films.filter { $0.canonicalStockName == "Fomapan 100 Classic" }
        XCTAssertEqual(films.count, 1, "Fomapan 100 Classic must remain a single top-level film stock.")
        XCTAssertEqual(films[0].profiles.count, 1, "The launch catalog still ships exactly one Fomapan profile.")
        XCTAssertFalse(
            LaunchPresetFilmCatalog.films.contains { $0.id == ohzartID },
            "Ohzart must not be a top-level film/catalog entry — it is an alternate model only."
        )
    }

    func testOhzartIsASeparateAlternateAndOfficialTableStaysDefault() throws {
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })
        // The catalog primary (default, no override) is the official table.
        let defaultBasis = try XCTUnwrap(film.profiles[0].modelBasis)
        XCTAssertEqual(defaultBasis.sourceModel, .manufacturerTable)
        XCTAssertEqual(defaultBasis.calculationModel, .tableLogLogInterpolation)
        XCTAssertEqual(film.profiles[0].source.authority, .official)

        let alternates = AlternateReciprocityModels.alternates(forFilmID: filmID)
        XCTAssertEqual(
            alternates.map(\.id),
            [ohzartID, "foma-fomapan-100-app-formula"],
            "Ohzart is a separate alternate, displayed before the app-derived formula."
        )
        // Session restore can reconstruct the persisted Ohzart override.
        XCTAssertEqual(AlternateReciprocityModels.profile(withID: ohzartID)?.id, ohzartID)
    }

    func testOhzartModelBasisIsCommunitySourceAndTableLogLog() throws {
        let profile = try ohzartProfile()
        let basis = try XCTUnwrap(profile.modelBasis)
        XCTAssertEqual(basis.sourceModel, .practicalCommunityGuidance)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
        XCTAssertEqual(profile.source.authority, .unofficial)
        XCTAssertEqual(profile.source.confidence, .medium)
        XCTAssertEqual(profile.selectorLabel, "Ohzart")
        // Not enrolled as an app-derived model: it must not gain the
        // app-derived comparison and must not read as a fitted formula.
        XCTAssertFalse(AlternateReciprocityModels.isAppDerivedModel(id: profile.id))
        XCTAssertTrue(profile.usesTableInterpolation)
        XCTAssertFalse(profile.isConvertedFormulaProfile)
    }

    // MARK: - Calculation correctness

    func testNoCorrectionThroughHalfSecond() throws {
        let profile = try ohzartProfile()
        // At and below 0.5 s, Tc = Tm (identity, no correction).
        XCTAssertEqual(try XCTUnwrap(corrected(profile, at: 0.4)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(corrected(profile, at: 0.5)), 0.5, accuracy: 1e-9)
        // Just above the boundary the correction starts (Tc > Tm).
        let justAbove = try XCTUnwrap(corrected(profile, at: 0.6))
        XCTAssertGreaterThan(justAbove, 0.6)
    }

    func testEveryOhzartAnchorIsReproducedExactly() throws {
        let profile = try ohzartProfile()
        for row in ohzartAnchors {
            let value = try XCTUnwrap(corrected(profile, at: row.metered))
            XCTAssertEqual(
                value,
                row.corrected,
                accuracy: 1e-6,
                "Ohzart anchor \(row.metered) s must reproduce \(row.corrected) s exactly; got \(value) s."
            )
        }
    }

    func testWithinRangeInterpolationStaysBetweenBracketingAnchors() throws {
        let profile = try ohzartProfile()
        // A value between the 8 s (35 s) and 15 s (90 s) anchors must
        // interpolate between them, never collapse onto either anchor.
        let value = try XCTUnwrap(corrected(profile, at: 10))
        XCTAssertGreaterThan(value, 35)
        XCTAssertLessThan(value, 90)
    }

    func testSourceRangeEndsAtSixtySecondsAndBeyondStillComputesAValue() throws {
        let profile = try ohzartProfile()
        let rule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                guard case let .tableInterpolation(rule) = rule else { return nil }
                return rule
            }.first
        )
        XCTAssertEqual(rule.sourceRangeThroughSeconds, 60, accuracy: 1e-9)
        XCTAssertEqual(rule.noCorrectionThroughSeconds, 0.5, accuracy: 1e-9)

        // 120 s is past the published table: still returns a value
        // (extrapolated), classified beyond source range — never a
        // value-less result.
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: profile, meteredExposureSeconds: 120)
        let beyond = try XCTUnwrap(
            result.correctedExposureSeconds,
            "Inputs past 60 s must still compute an (extrapolated) value."
        )
        XCTAssertGreaterThan(beyond, 795)
        // Past the published table the policy reclassifies the value as
        // beyond source range (the table model keeps a computed value
        // rather than dead-ending).
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(result.metadata.rangeStatus, .beyondPolicyLimit)
    }

    // MARK: - Source separation (Ohzart vs official FOMA)

    func testOhzartSourceEvidenceMatchesCommunityAnchorsAndNotFomaOfficial() throws {
        let profile = try ohzartProfile()
        let ohzartCorrected = profile.sourceEvidence.map { correctedSeconds(in: $0) }
        XCTAssertEqual(ohzartCorrected, ohzartAnchors.map(\.corrected))
        // The official FOMA corrected values (80, 1600) must not leak
        // into the Ohzart source reference.
        XCTAssertFalse(ohzartCorrected.contains(80))
        XCTAssertFalse(ohzartCorrected.contains(1600))
    }

    func testOfficialFomaSourceReferenceIsNotPollutedByOhzartRows() throws {
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })
        let fomaCorrected = film.profiles[0].sourceEvidence.map { correctedSeconds(in: $0) }
        XCTAssertEqual(fomaCorrected, [2, 80, 1600], "Official FOMA anchors are unchanged.")
        // None of the Ohzart-distinctive corrected values may appear in
        // the official FOMA source evidence.
        for ohzartOnly in [1.9, 5.0, 13.0, 35.0, 90.0, 265.0, 795.0] {
            XCTAssertFalse(
                fomaCorrected.contains(ohzartOnly),
                "Official FOMA source reference must not contain Ohzart value \(ohzartOnly)."
            )
        }
    }

    // MARK: - Presentation (selecting Ohzart in Details)

    @MainActor
    func testSelectingOhzartReadsAsCommunityTableNotOfficialNorAppDerived() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" }
        )
        viewModel.baseShutter = 8       // an Ohzart anchor, within range
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        viewModel.selectProfileVariant(profileID: ohzartID)

        XCTAssertEqual(viewModel.filmReciprocityBindingState?.profile.id, ohzartID)
        XCTAssertEqual(viewModel.filmDetailsModelSelection?.activeOptionID, ohzartID)

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)

        // Honest table-derived badge, never "Formula-derived".
        XCTAssertEqual(details.summary.badgeText, "Table-derived")
        // Summary must not call the community table "official".
        XCTAssertEqual(details.summary.summaryText, "Log-log interpolation of the community table")

        // Reciprocity model metadata: community source + log-log table.
        let metadata = try XCTUnwrap(details.sections.first { $0.title == "Reciprocity model" })
        XCTAssertEqual(metadata.rows.first { $0.title == "Source" }?.value, "Practical / community guidance")
        XCTAssertEqual(metadata.rows.first { $0.title == "Calculation" }?.value, "Log-log table interpolation")

        // Table-derived model: no app-derived comparison section, and no
        // app-derived-formula wording anywhere in the sheet.
        let titles = details.sections.map(\.title)
        XCTAssertTrue(titles.contains("Source reference"), "Ohzart keeps a Source reference: \(titles)")
        XCTAssertFalse(titles.contains("App-derived comparison"), "A table model has nothing to compare: \(titles)")

        let allText = collectFilmModeDetailsText(details).joined(separator: "\n")
        XCTAssertFalse(allText.contains("App-derived"), "Ohzart must not use app-derived wording: \(allText)")
        XCTAssertFalse(allText.contains("manufacturer"), "Ohzart must not read as manufacturer data: \(allText)")
        XCTAssertFalse(allText.lowercased().contains("official foma"), "Ohzart must not cite the official FOMA table: \(allText)")
        // The community caveat is surfaced.
        XCTAssertTrue(allText.contains("Not FOMA-published data"), "The community caveat must be visible: \(allText)")
    }

    @MainActor
    func testOfficialTableDefaultStillReadsAsOfficialAfterOhzartExists() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" }
        )
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)

        // No override → the official FOMA table is active and default.
        XCTAssertEqual(viewModel.filmDetailsModelSelection?.activeOptionID, film.profiles[0].id)
        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        XCTAssertEqual(details.summary.summaryText, "Log-log interpolation of the official table")
        let metadata = try XCTUnwrap(details.sections.first { $0.title == "Reciprocity model" })
        XCTAssertEqual(metadata.rows.first { $0.title == "Source" }?.value, "Manufacturer table")
    }

    // MARK: - Authority label wording (film row / camera slot subtitle)

    func testFilmRowAuthorityLabelsDistinguishTheThreeFomapanModels() throws {
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })

        // Official FOMA table is the only Fomapan model that reads as
        // official guidance.
        XCTAssertEqual(
            FilmSelectionModel.filmRowAuthorityLabel(for: film.profiles[0]),
            "Official guidance"
        )
        // The app-derived formula must NOT read as official guidance —
        // it names itself instead.
        XCTAssertEqual(
            FilmSelectionModel.filmRowAuthorityLabel(for: AlternateReciprocityModels.fomapan100AppDerivedFormula),
            "App-derived formula"
        )
        XCTAssertNotEqual(
            FilmSelectionModel.filmRowAuthorityLabel(for: AlternateReciprocityModels.fomapan100AppDerivedFormula),
            "Official guidance"
        )
        // Ohzart stays unofficial / practical.
        XCTAssertEqual(
            FilmSelectionModel.filmRowAuthorityLabel(for: try ohzartProfile()),
            "Unofficial practical"
        )
    }

    @MainActor
    func testActiveFilmRowSubtitleForAppFormulaIsNotOfficialGuidance() throws {
        let viewModel = makeFilmModeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Fomapan 100 Classic" }
        )
        viewModel.baseShutter = 10
        viewModel.ndStop = 0
        viewModel.selectPresetFilm(film)
        viewModel.selectProfileVariant(profileID: "foma-fomapan-100-app-formula")

        XCTAssertEqual(viewModel.filmSelectionDisplayState.secondaryText, "App-derived formula")
        XCTAssertNotEqual(viewModel.filmSelectionDisplayState.secondaryText, "Official guidance")
    }

    // MARK: - Beyond-source note wording (source-neutral)

    func testOhzartBeyondSourceNoteIsSourceNeutralNotManufacturer() throws {
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: try ohzartProfile(), meteredExposureSeconds: 120)
        let noteText = result.metadata.notes.map(\.text).joined(separator: "\n")

        XCTAssertTrue(noteText.contains("Source table ends at 60 sec."), "Got: \(noteText)")
        XCTAssertFalse(noteText.contains("Manufacturer table"), "Ohzart is not manufacturer data: \(noteText)")
        XCTAssertFalse(noteText.contains("manufacturer source range"), "Got: \(noteText)")
    }

    func testOfficialFomaBeyondSourceNoteIsStillCorrectWithSourceNeutralWording() throws {
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })
        // 1000 s is past the official 100 s table.
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: film.profiles[0], meteredExposureSeconds: 1000)
        let noteText = result.metadata.notes.map(\.text).joined(separator: "\n")

        XCTAssertTrue(noteText.contains("Source table ends at 100 sec."), "Got: \(noteText)")
        XCTAssertFalse(noteText.contains("Manufacturer table"), "Got: \(noteText)")
    }

    // MARK: - Badge tone (status reflects calculation, not authority)

    func testOhzartInRangeTableDerivedToneIsNotWarning() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let binding = try bindingState(profile: try ohzartProfile(), meteredSeconds: 8)

        // 8 s is within the published table (an exact anchor).
        XCTAssertEqual(binding.presentation.category, .formulaDerived)
        XCTAssertEqual(presenter.badgeText(for: binding), "Table-derived")
        XCTAssertEqual(
            presenter.tone(for: binding),
            .measured,
            "A successful in-range Ohzart table result must use the normal derived tone, not caution/orange."
        )
        XCTAssertNotEqual(presenter.tone(for: binding), .caution)
    }

    func testOhzartNoCorrectionToneIsGreenSuccess() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let binding = try bindingState(profile: try ohzartProfile(), meteredSeconds: 0.4)

        XCTAssertEqual(binding.presentation.category, .noCorrection)
        XCTAssertEqual(presenter.badgeText(for: binding), "No correction")
        XCTAssertEqual(
            presenter.tone(for: binding),
            .trusted,
            "No correction is a normal/safe state — green/success — even for an unofficial source."
        )
    }

    func testOfficialFomaNoCorrectionToneIsGreenSuccess() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })
        // 0.4 s is within FOMA's 0.5 s no-correction band.
        let binding = try bindingState(profile: film.profiles[0], meteredSeconds: 0.4)

        XCTAssertEqual(binding.presentation.category, .noCorrection)
        XCTAssertEqual(presenter.badgeText(for: binding), "No correction")
        XCTAssertEqual(presenter.tone(for: binding), .trusted)
    }

    func testPortraUnofficialNoCorrectionToneIsGreenSuccess() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Portra 400" }
        )
        let profile = UnofficialPracticalProfiles.kodakPortra400UnofficialPractical
        // 0.5 s is below the unofficial 1 s no-correction boundary.
        let policyResult = ReciprocityModel().evaluate(profile: profile, meteredExposureSeconds: 0.5)
        let binding = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        XCTAssertEqual(binding.presentation.category, .noCorrection)
        XCTAssertEqual(presenter.badgeText(for: binding), "No correction")
        XCTAssertEqual(
            presenter.tone(for: binding),
            .trusted,
            "Unofficial Portra no-correction must also read as green/success."
        )
    }

    func testOhzartBeyondSourceKeepsUnsupportedTone() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let binding = try bindingState(profile: try ohzartProfile(), meteredSeconds: 120)

        XCTAssertEqual(binding.presentation.category, .unsupported)
        XCTAssertEqual(presenter.badgeText(for: binding), "Beyond source range")
        XCTAssertEqual(
            presenter.tone(for: binding),
            .unsupported,
            "Beyond-source range must keep its stronger warning/unsupported tone."
        )
    }

    func testOfficialFomaInRangeTableToneStaysMeasured() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })
        let binding = try bindingState(profile: film.profiles[0], meteredSeconds: 10)

        XCTAssertEqual(presenter.badgeText(for: binding), "Table-derived")
        XCTAssertEqual(presenter.tone(for: binding), .measured, "Official table-derived stays the normal derived tone.")
    }

    func testAppFormulaInRangeToneIsNotWarning() throws {
        let presenter = ReciprocityDetailsVocabularyPresenter()
        let binding = try bindingState(
            profile: AlternateReciprocityModels.fomapan100AppDerivedFormula,
            meteredSeconds: 10
        )

        XCTAssertEqual(presenter.badgeText(for: binding), "Formula-derived")
        XCTAssertNotEqual(presenter.tone(for: binding), .caution)
    }

    // MARK: - Helpers

    /// Builds a binding state for the Fomapan 100 film identity with the
    /// given profile active, mirroring how the view model assembles it.
    private func bindingState(
        profile: ReciprocityProfile,
        meteredSeconds: Double
    ) throws -> FilmModeReciprocityBindingState {
        let film = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == filmID })
        let policyResult = ReciprocityModel().evaluate(profile: profile, meteredExposureSeconds: meteredSeconds)
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    /// Extracts the corrected-time value carried by a source-evidence row.
    private func correctedSeconds(in row: ReciprocitySourceEvidenceRow) -> Double {
        for adjustment in row.adjustments {
            if case let .exposure(.correctedTime(mapping)) = adjustment {
                return mapping.correctedSeconds
            }
        }
        return .nan
    }
}
