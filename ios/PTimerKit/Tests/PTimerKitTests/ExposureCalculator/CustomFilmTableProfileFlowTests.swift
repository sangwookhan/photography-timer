import XCTest
import PTimerKit
import PTimerCore

/// End-to-end coverage for custom table profiles (PTIMER-178):
/// library sanitation, persistence round trip, shooting-mode
/// calculation through the existing table log-log path,
/// display-only `sourceEvidence` independence, Details vocabulary,
/// and timer identity.
@MainActor
final class CustomFilmTableProfileFlowTests: XCTestCase {

    // MARK: - Library sanitation

    func test_library_acceptsValidTableProfile() {
        let library = CustomFilmLibrary(initial: [makeTableFilm(id: "table-1")])
        XCTAssertEqual(library.customFilms.map(\.id), ["table-1"])
    }

    func test_library_acceptsValidFormulaProfile() {
        let film = CustomFilmTestSupport.makeCustomFilm(id: "formula-1")
        let library = CustomFilmLibrary(initial: [film])
        XCTAssertEqual(library.customFilms.map(\.id), ["formula-1"])
    }

    func test_library_add_acceptsValidTableProfile() {
        let library = CustomFilmLibrary()
        library.add(makeTableFilm(id: "table-1"))
        XCTAssertEqual(library.customFilms.count, 1)
    }

    func test_library_dropsTableProfile_withSingleAnchor() {
        let film = makeTableFilm(
            id: "bad",
            anchors: [TableAnchor(meteredSeconds: 10, correctedSeconds: 80)],
            sourceRangeThroughSeconds: 10
        )
        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_acceptsTableProfile_withUnsortedAnchors() {
        // The domain contract sorts anchors before validating and
        // evaluating, so storage order is not part of well-formedness
        // — only the editor enforces typed-in ascending order.
        let film = makeTableFilm(
            id: "unsorted",
            anchors: [
                TableAnchor(meteredSeconds: 10, correctedSeconds: 80),
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
            ],
            sourceRangeThroughSeconds: 10
        )
        XCTAssertEqual(CustomFilmLibrary(initial: [film]).customFilms.count, 1)
    }

    func test_library_dropsTableProfile_withDuplicateMeteredAnchors() {
        let film = makeTableFilm(
            id: "bad",
            anchors: [
                TableAnchor(meteredSeconds: 10, correctedSeconds: 80),
                TableAnchor(meteredSeconds: 10, correctedSeconds: 90),
            ],
            sourceRangeThroughSeconds: 10
        )
        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_dropsTableProfile_withShorteningAnchor() {
        let film = makeTableFilm(
            id: "bad",
            anchors: [
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
                TableAnchor(meteredSeconds: 10, correctedSeconds: 5),
            ],
            sourceRangeThroughSeconds: 10
        )
        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_dropsTableProfile_withZeroNoCorrection() {
        // `hasValidParameters` allows 0, but the custom sanitizer is
        // stricter: the evaluator feeds the knee into log-log space,
        // so a persisted 0 dead-ends the first segment.
        let film = makeTableFilm(id: "bad", noCorrectionThroughSeconds: 0)
        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_dropsTableProfile_withNonFiniteAnchor() {
        let film = makeTableFilm(
            id: "bad",
            anchors: [
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
                TableAnchor(meteredSeconds: 10, correctedSeconds: .infinity),
            ],
            sourceRangeThroughSeconds: 10
        )
        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_keepsFormulaProfile_alongsideTableProfile() {
        let formulaFilm = CustomFilmTestSupport.makeCustomFilm(id: "formula-1")
        let library = CustomFilmLibrary(initial: [formulaFilm, makeTableFilm(id: "table-1")])
        XCTAssertEqual(library.customFilms.map(\.id), ["formula-1", "table-1"])
    }

    func test_library_dropsProfile_withMixedFormulaAndTableRules() {
        let formulaRule = defaultFormulaRule()
        let tableRule = defaultTableRule()
        let film = makeCustomFilm(
            id: "mixed",
            rules: [.formula(formulaRule), .tableInterpolation(tableRule)]
        )

        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_dropsProfile_withTwoFormulaRules() {
        let formulaRule = defaultFormulaRule()
        let film = makeCustomFilm(
            id: "two-formulas",
            rules: [.formula(formulaRule), .formula(formulaRule)]
        )

        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    func test_library_dropsProfile_withTwoTableRules() {
        let tableRule = defaultTableRule()
        let film = makeCustomFilm(
            id: "two-tables",
            rules: [.tableInterpolation(tableRule), .tableInterpolation(tableRule)]
        )

        XCTAssertTrue(CustomFilmLibrary(initial: [film]).isEmpty)
    }

    // MARK: - Persistence round trip

    func test_persistentSnapshot_roundTripsTableProfile() throws {
        let film = makeTableFilm(id: "table-1")
        let snapshot = PersistentCustomFilmLibrarySnapshot(films: [film])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            PersistentCustomFilmLibrarySnapshot.self,
            from: data
        )

        XCTAssertEqual(decoded, snapshot)
        let profile = try XCTUnwrap(decoded.films.first?.profiles.first)
        guard case .tableInterpolation(let rule) = try XCTUnwrap(profile.rules.first) else {
            return XCTFail("Expected tableInterpolation rule after decode")
        }
        XCTAssertEqual(rule.anchors.count, 3)
        XCTAssertEqual(profile.sourceEvidence.count, 3)
    }

    func test_libraryWithStore_restoresTableProfile() {
        let store = InMemoryCustomFilmLibraryStore()
        let writing = CustomFilmLibrary(store: store)
        writing.add(makeTableFilm(id: "table-1"))

        let restored = CustomFilmLibrary(store: store)
        XCTAssertEqual(restored.customFilms.map(\.id), ["table-1"])
    }

    // MARK: - Shooting-mode calculation (existing table log-log path)

    func test_selectedTableProfile_reproducesAnchorExactly() throws {
        let viewModel = makeViewModel()
        let film = makeTableFilm(id: "table-1")
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 10.0
        viewModel.ndStop = 0

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        XCTAssertTrue(resultState.hasQuantifiedCorrectedExposure)
        let corrected = try XCTUnwrap(resultState.correctedExposure.correctedExposureSeconds)
        // Interpolation passes through every anchor exactly: 10 s → 80 s.
        XCTAssertEqual(corrected, 80, accuracy: 1e-6)
    }

    func test_selectedTableProfile_interpolatesBetweenAnchorsInLogLogSpace() throws {
        let viewModel = makeViewModel()
        let film = makeTableFilm(id: "table-1")
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 30.0
        viewModel.ndStop = 0

        let resultState = try XCTUnwrap(viewModel.filmModeExposureResultState)
        let corrected = try XCTUnwrap(resultState.correctedExposure.correctedExposureSeconds)
        // Log-log interpolation between (10, 80) and (100, 1600).
        let slope = (log10(1600.0) - log10(80.0)) / (log10(100.0) - log10(10.0))
        let expected = pow(10, log10(80.0) + slope * (log10(30.0) - log10(10.0)))
        XCTAssertEqual(corrected, expected, accuracy: 0.01)
    }

    func test_tableCalculation_readsRuleAnchors_notSourceEvidence() throws {
        // The display-only evidence rows deliberately carry WRONG
        // corrected values; the calculation must be unaffected
        // because the policy reads only the rule's anchors.
        let anchors = defaultAnchors
        let corruptedEvidence = anchors.map { anchor in
            ReciprocitySourceEvidenceRow(
                meteredExposure: .exactSeconds(anchor.meteredSeconds),
                adjustments: [
                    .exposure(.correctedTime(CorrectedTimeMapping(
                        meteredSeconds: anchor.meteredSeconds,
                        correctedSeconds: anchor.correctedSeconds * 1000
                    ))),
                ]
            )
        }
        let withCorruptedEvidence = makeTableProfile(
            id: "p1",
            anchors: anchors,
            sourceEvidence: corruptedEvidence
        )
        let withoutEvidence = makeTableProfile(
            id: "p2",
            anchors: anchors,
            sourceEvidence: []
        )

        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let first = evaluator.evaluate(
            profile: withCorruptedEvidence,
            meteredExposureSeconds: 10
        )
        let second = evaluator.evaluate(
            profile: withoutEvidence,
            meteredExposureSeconds: 10
        )
        let firstCorrected = try XCTUnwrap(first.correctedExposureSeconds)
        let secondCorrected = try XCTUnwrap(second.correctedExposureSeconds)
        XCTAssertEqual(firstCorrected, 80, accuracy: 1e-6)
        XCTAssertEqual(firstCorrected, secondCorrected, accuracy: 1e-12)
    }

    // MARK: - Details vocabulary

    func test_detailsBadge_inRange_readsCustomTable() {
        let bindingState = makeBindingState(meteredExposureSeconds: 10)
        let presenter = ReciprocityDetailsVocabularyPresenter()
        XCTAssertEqual(presenter.badgeText(for: bindingState), "Custom table")
    }

    func test_detailsBadge_beyondSourceRange_readsBeyondSourceRange() {
        let bindingState = makeBindingState(meteredExposureSeconds: 500)
        let presenter = ReciprocityDetailsVocabularyPresenter()
        XCTAssertEqual(presenter.badgeText(for: bindingState), "Beyond source range")
        XCTAssertNotNil(
            bindingState.policyResult.correctedExposureSeconds,
            "Beyond-source still carries a numeric continuation"
        )
    }

    func test_detailsSummary_customTableBeyondSource_usesNeutralTableCopy() throws {
        let viewModel = makeViewModel()
        let film = makeTableFilm(id: "table-1")
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 500.0
        viewModel.ndStop = 0

        let details = try XCTUnwrap(viewModel.filmModeDetailsDisplayState)
        let detailText = try XCTUnwrap(details.summary.detailText)
        XCTAssertEqual(
            detailText,
            "Current input is beyond this table's source range. The corrected value is extrapolated past the last table anchor."
        )
        XCTAssertFalse(detailText.localizedCaseInsensitiveContains("published"))
        XCTAssertFalse(detailText.localizedCaseInsensitiveContains("official"))
    }

    func test_detailsBadge_customFormula_unchanged() {
        let film = CustomFilmTestSupport.makeCustomFilm(id: "formula-1")
        let profile = film.profiles[0]
        let policyResult = ReciprocityCalculationPolicyEvaluator().evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let presenter = ReciprocityDetailsVocabularyPresenter()
        XCTAssertEqual(presenter.badgeText(for: bindingState), "Custom formula")
    }

    func test_detailsSummary_customFormulaDetailText_unchanged() {
        let film = CustomFilmTestSupport.makeCustomFilm(id: "formula-1")
        let profile = film.profiles[0]
        let policyResult = ReciprocityCalculationPolicyEvaluator().evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let presenter = ReciprocityDetailsVocabularyPresenter()
        XCTAssertNil(presenter.summaryDetailText(for: bindingState))
    }

    func test_customRangeLines_tableProfile_reportBothBoundaries() {
        let profile = makeTableProfile(
            id: "p1",
            anchors: defaultAnchors,
            sourceEvidence: []
        )
        let lines = ReciprocityDetailsVocabularyPresenter().customRangeLines(profile: profile)
        // Seconds-first with an hms supplement for long values
        // (PTIMER-179), so 100 s reads as "100s (1m 40s)" rather than
        // the old decimal-minute "1.7m".
        XCTAssertEqual(
            lines,
            ["No correction through 0.10s", "Source range through 100s (1m 40s)"]
        )
    }

    // MARK: - Timer identity

    func test_timerIdentity_distinguishesTableProfile() throws {
        let viewModel = makeViewModel()
        let film = makeTableFilm(id: "table-1")
        viewModel.addCustomFilm(film)
        viewModel.selectEntry(entry(for: film.id, in: viewModel))
        viewModel.baseShutter = 10.0
        viewModel.ndStop = 0

        XCTAssertTrue(viewModel.canStartFilmCorrectedExposureTimer)
        viewModel.startFilmCorrectedExposureTimer()

        let timer = try XCTUnwrap(viewModel.timers.first { $0.status == .running })
        XCTAssertEqual(timer.filmProfileQualifier, "Custom")
        let snapshot = try XCTUnwrap(timer.identitySnapshot)
        let summary = try XCTUnwrap(snapshot.customProfileSummary)
        XCTAssertTrue(summary.contains("Custom table · 3 anchors"), summary)
        XCTAssertTrue(summary.contains("ISO 100"), summary)
    }

    func test_customProfileCalculationText_formulaProfile_staysFormulaText() {
        let film = CustomFilmTestSupport.makeCustomFilm(id: "formula-1")
        let text = TimerStartComposer.customProfileCalculationText(profile: film.profiles[0])
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.contains("Custom table") == true)
    }

    // MARK: - Fixtures

    private var defaultAnchors: [TableAnchor] {
        [
            TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
            TableAnchor(meteredSeconds: 10, correctedSeconds: 80),
            TableAnchor(meteredSeconds: 100, correctedSeconds: 1600),
        ]
    }

    private func makeTableProfile(
        id: String,
        anchors: [TableAnchor],
        sourceEvidence: [ReciprocitySourceEvidenceRow],
        noCorrectionThroughSeconds: Double = 0.1,
        sourceRangeThroughSeconds: Double? = nil
    ) -> ReciprocityProfile {
        let rule = TableInterpolationReciprocityRule(
            anchors: anchors,
            noCorrectionThroughSeconds: noCorrectionThroughSeconds,
            sourceRangeThroughSeconds: sourceRangeThroughSeconds
                ?? anchors.map(\.meteredSeconds).max()
                ?? 0
        )
        return ReciprocityProfile(
            id: id,
            name: "Custom Table Profile",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.tableInterpolation(rule)],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest),
            sourceEvidence: sourceEvidence
        )
    }

    private func defaultFormulaRule() -> FormulaReciprocityRule {
        FormulaReciprocityRule(formula: ReciprocityFormula(
            exponent: 1.30,
            noCorrectionThroughSeconds: 1
        ))
    }

    private func defaultTableRule() -> TableInterpolationReciprocityRule {
        TableInterpolationReciprocityRule(
            anchors: defaultAnchors,
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100
        )
    }

    private func makeCustomFilm(
        id: String,
        rules: [ReciprocityRule]
    ) -> FilmIdentity {
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: "Custom Profile",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: rules,
            userMetadata: UserEditableMetadata(customSourceType: .personalTest),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: "Custom Stock",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )
    }

    private func makeTableFilm(
        id: String,
        anchors: [TableAnchor]? = nil,
        noCorrectionThroughSeconds: Double = 0.1,
        sourceRangeThroughSeconds: Double? = nil
    ) -> FilmIdentity {
        let resolvedAnchors = anchors ?? defaultAnchors
        let profile = makeTableProfile(
            id: "\(id)-profile",
            anchors: resolvedAnchors,
            sourceEvidence: CustomFilmEditorFormState.displayEvidenceRows(
                for: resolvedAnchors
            ),
            noCorrectionThroughSeconds: noCorrectionThroughSeconds,
            sourceRangeThroughSeconds: sourceRangeThroughSeconds
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: "Custom Table Stock",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )
    }

    private func makeBindingState(
        meteredExposureSeconds: Double
    ) -> FilmModeReciprocityBindingState {
        let film = makeTableFilm(id: "table-1")
        let profile = film.profiles[0]
        let policyResult = ReciprocityCalculationPolicyEvaluator().evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
        return FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
    }

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(),
            customFilmLibrary: CustomFilmLibrary()
        )
    }

    private func entry(
        for filmID: String,
        in viewModel: ExposureCalculatorViewModel
    ) -> FilmSelectorEntry {
        guard let entry = viewModel.filmSelectorEntries.first(where: { $0.id == filmID }) else {
            preconditionFailure("Selector entry not built for film id \(filmID)")
        }
        return entry
    }
}

/// Minimal in-memory store double for restore-path coverage —
/// records the last saved snapshot and serves it back to a second
/// library instance, mirroring a relaunch without UserDefaults.
private final class InMemoryCustomFilmLibraryStore: CustomFilmLibraryStoring {
    private var snapshot: PersistentCustomFilmLibrarySnapshot?
    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? { snapshot }
    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) {
        self.snapshot = snapshot
    }
    func clearSnapshot() { snapshot = nil }
}
