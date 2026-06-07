import XCTest
import PTimerCore
@testable import PTimer

/// Timer-start + identity-snapshot coverage for the custom film
/// path. Exercises the full chain: ViewModel →
/// TimerStartComposer → TimerWorkspaceModel → RunningTimerItem →
/// ExposureTimerIdentitySnapshot, plus the timer-metadata
/// persistence round trip and the "summary survives deletion"
/// invariant.
@MainActor
final class CalculatorViewModelCustomFilmTimerTests: XCTestCase {

    // MARK: - Start path

    func test_startTimer_fromCustomCorrectedExposure_createsRunningTimer() throws {
        let viewModel = makeViewModel()
        let film = customFilm(profileName: "Custom Personal Provia", exponent: 1.30, iso: 100)
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0

        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
        viewModel.startFilmCorrectedExposureTimer()

        let runningTimers = viewModel.timers.filter { $0.status == .running }
        XCTAssertEqual(runningTimers.count, 1)
        let timer = try XCTUnwrap(runningTimers.first)
        XCTAssertEqual(timer.exposureSource, .filmCorrectedExposure)
        XCTAssertEqual(timer.filmDisplayName, "Custom Stock")
        XCTAssertEqual(timer.filmProfileQualifier, "Custom")
    }

    // MARK: - Identity snapshot

    func test_identitySnapshot_preservesCustomProfileSummary() throws {
        let viewModel = makeViewModel()
        let film = customFilm(profileName: "Sandwich Provia", exponent: 1.30, iso: 100)
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first { $0.status == .running })
        let snapshot = try XCTUnwrap(timer.identitySnapshot)
        XCTAssertEqual(snapshot.filmProfileQualifier, "Custom")
        let summary = try XCTUnwrap(snapshot.customProfileSummary)
        XCTAssertTrue(summary.contains("Sandwich Provia"))
        XCTAssertTrue(summary.contains("ISO 100"))
        XCTAssertTrue(summary.contains("User-defined"))
        // The unified formatter uses "Tc" / "Tm" notation across
        // editor, Details, and timer surfaces.
        XCTAssertTrue(summary.contains("Tc"))
        XCTAssertTrue(summary.contains("1.3"))
    }

    func test_identitySnapshot_includesSourceTypeLabel() throws {
        let viewModel = makeViewModel()
        let film = customFilm(
            profileName: "Bracketed Provia",
            exponent: 1.35,
            iso: 100,
            sourceType: .personalTest
        )
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 3.0
        viewModel.ndStop = 0
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first { $0.status == .running })
        let snapshot = try XCTUnwrap(timer.identitySnapshot)
        XCTAssertTrue(snapshot.customProfileSummary?.contains("Personal test") == true)
    }

    func test_identitySnapshot_remainsStable_afterCustomProfileDeleted() throws {
        let viewModel = makeViewModel()
        let film = customFilm(profileName: "Soon-to-delete", exponent: 1.30, iso: 200)
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0
        viewModel.startFilmCorrectedExposureTimer()

        let originalSnapshot = try XCTUnwrap(
            viewModel.timers.first { $0.status == .running }?.identitySnapshot
        )

        // Remove the source profile from the library; the running
        // timer's snapshot must remain byte-for-byte identical so
        // the workspace can still render its identity.
        viewModel.customFilmLibrary.remove(id: film.id)

        let postDeletionSnapshot = try XCTUnwrap(
            viewModel.timers.first { $0.status == .running }?.identitySnapshot
        )
        XCTAssertEqual(originalSnapshot, postDeletionSnapshot)
        XCTAssertEqual(postDeletionSnapshot.filmDisplayName, "Custom Stock")
        XCTAssertEqual(postDeletionSnapshot.filmProfileQualifier, "Custom")
        XCTAssertNotNil(postDeletionSnapshot.customProfileSummary)
    }

    // MARK: - Preset regression

    func test_presetTimer_identitySnapshot_omitsCustomSummary() throws {
        let viewModel = makeViewModel()
        let provia = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Provia 100F" }
        )
        viewModel.selectPresetFilm(provia)
        viewModel.baseShutter = 5.0
        viewModel.ndStop = 0
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first { $0.status == .running })
        let snapshot = try XCTUnwrap(timer.identitySnapshot)
        XCTAssertNil(snapshot.filmProfileQualifier)
        XCTAssertNil(snapshot.customProfileSummary)
    }

    // MARK: - Persistence round-trip

    func test_persistedMetadata_roundTripsCustomProfileSummary() {
        let snapshot = PersistentTimerMetadataSnapshot(
            id: UUID(),
            order: 1,
            name: "Custom · 8s",
            basisSummary: "Base 5s · 0 stops · Custom · Corrected 8s",
            cameraSlotIDRaw: nil,
            cameraSlotDisplayName: nil,
            filmDisplayName: "Personal Stock",
            filmProfileQualifier: "Custom",
            exposureSourceRaw: ExposureTimerSource.filmCorrectedExposure.rawValue,
            isOutsideManufacturerGuidance: nil,
            customProfileSummary: "Personal Provia · ISO 100 · Personal test · T_c = T^1.30"
        )

        let encoded = try? JSONEncoder().encode(snapshot)
        XCTAssertNotNil(encoded)
        let decoded = try? JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: encoded ?? Data())
        XCTAssertEqual(decoded?.customProfileSummary, snapshot.customProfileSummary)
    }

    func test_persistedMetadata_decodesLegacyPayloadWithoutCustomSummary() throws {
        // Legacy payload: no `customProfileSummary` key. The
        // decoder must treat it as `nil` so existing timers continue
        // to decode unchanged.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "order": 0,
          "name": "Provia · 8s",
          "basisSummary": "Base 5s · 0 stops · Provia 100F · Corrected 8s",
          "filmDisplayName": "Provia 100F",
          "exposureSourceRaw": "filmCorrectedExposure"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: data)
        XCTAssertNil(decoded.customProfileSummary)
        XCTAssertEqual(decoded.filmDisplayName, "Provia 100F")
    }

    // MARK: - Formula text formatter

    func test_customProfileFormulaText_handlesCoefficientAndOffset() {
        // Custom and preset profiles share `FormulaEquationFormatter`.
        // Neutral anchors collapse the
        // display form (`Tref = 1s` drops the `(Tm / Tref)`
        // rescaling, `a = 1` drops the leading coefficient). Offsets
        // are seconds-tagged.
        let plain = TimerStartComposer.customProfileFormulaText(
            profile: makeFormulaProfile(exponent: 1.30)
        )
        XCTAssertEqual(plain, "Tc = Tm^1.3")

        let scaled = TimerStartComposer.customProfileFormulaText(
            profile: makeFormulaProfile(exponent: 1.30, coefficient: 1.10)
        )
        XCTAssertEqual(scaled, "Tc = 1.1 × Tm^1.3")

        let withOffset = TimerStartComposer.customProfileFormulaText(
            profile: makeFormulaProfile(exponent: 1.30, offsetSeconds: 0.5)
        )
        XCTAssertEqual(withOffset, "Tc = Tm^1.3 + 0.5s")

        let negativeOffset = TimerStartComposer.customProfileFormulaText(
            profile: makeFormulaProfile(exponent: 1.30, offsetSeconds: -0.25)
        )
        XCTAssertEqual(negativeOffset, "Tc = Tm^1.3 - 0.25s")
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(),
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    private func entry(for filmID: String, in viewModel: ExposureCalculatorViewModel) -> FilmSelectorEntry {
        guard let entry = viewModel.filmSelectorEntries.first(where: { $0.id == filmID }) else {
            preconditionFailure("Selector entry not built for film id \(filmID)")
        }
        return entry
    }

    private func customFilm(
        profileName: String,
        exponent: Double,
        iso: Int,
        sourceType: CustomProfileSourceType = .userDefined
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(exponent: exponent
        , noCorrectionThroughSeconds: 1)
        let profile = ReciprocityProfile(
            id: "custom-profile-\(UUID().uuidString)",
            name: profileName,
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(customSourceType: sourceType),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: "custom-film-\(UUID().uuidString)",
            kind: .custom,
            canonicalStockName: "Custom Stock",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: sourceType)
        )
    }

    private func makeFormulaProfile(
        exponent: Double,
        coefficient: Double? = nil,
        offsetSeconds: Double? = nil
    ) -> ReciprocityProfile {
        let formula = ReciprocityFormula(
            coefficientSeconds: coefficient ?? 1,
            referenceMeteredTimeSeconds: 1,
            exponent: exponent,
            offsetSeconds: offsetSeconds ?? 0,
            noCorrectionThroughSeconds: 1
        )
        return ReciprocityProfile(
            id: "tmp",
            name: "tmp",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))]
        )
    }
}
