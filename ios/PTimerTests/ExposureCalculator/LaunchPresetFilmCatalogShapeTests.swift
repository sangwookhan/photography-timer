import XCTest
import PTimerCore
@testable import PTimer

/// Structural guard on the bundled `LaunchPresetFilmCatalog`. The
/// launch catalog ships only official manufacturer profiles, so the
/// allow-list is exactly two shapes (DomainSchema §13):
///
/// - **Official quantified formula**: threshold + formula rules.
///   Source-evidence rows OK (converted formula profiles).
/// - **Official limited guidance**: threshold + limited-guidance
///   rule, no formula rule, empty source-evidence.
///
/// Unofficial practical profiles are bundled outside the launch
/// catalog (DomainSchema §13.3) and are covered by
/// `UnofficialPracticalProfilesShapeTests`.
///
/// What this file does NOT do:
/// - It does not exercise the calculation engine. Those tests live in
///   `ReciprocityCalculationPolicyTests` and the per-film
///   `*FormulaProfileTests`.
/// - It does not exercise user-facing presentation wording. Those
///   live in `KodakLimitedGuidanceProfilesTests`,
///   `ConvertedFormulaProfileTemplateTests`, and
///   `ReciprocityConfidencePresentationTests`.
@MainActor
final class LaunchPresetFilmCatalogShapeTests: XCTestCase {

    private let films = LaunchPresetFilmCatalog.films

    // MARK: - Supported rule kinds in the bundled catalog

    /// PTIMER-159 supersedes PTIMER-140's "no table rule" contract: the
    /// launch catalog now carries the official log-log
    /// `.tableInterpolation` rule (Fomapan 100). This test confirms the
    /// catalog uses only rule kinds the evaluator implements, and that
    /// the table rule is present where expected.
    func testLaunchPresetProfilesUseOnlySupportedRuleKinds() throws {
        for film in films {
            for profile in film.profiles {
                for rule in profile.rules {
                    switch rule {
                    case .threshold, .formula, .limitedGuidance, .tableInterpolation:
                        continue
                    }
                }
            }
        }

        // The deliberate introduction: Fomapan 100 ships the official
        // table log-log model.
        let fomapan = try XCTUnwrap(films.first { $0.canonicalStockName == "Fomapan 100 Classic" })
        let usesTable = fomapan.profiles[0].rules.contains {
            if case .tableInterpolation = $0 { return true }
            return false
        }
        XCTAssertTrue(usesTable, "Fomapan 100 must ship the official table-interpolation rule (PTIMER-159).")
    }

    /// Every preset film must classify as exactly one of the two
    /// allowed launch-catalog shapes. Anything that fails to match
    /// indicates either a structurally invalid profile or a new shape
    /// that needs to be added to the allow-list deliberately.
    func testEveryLaunchPresetProfileMatchesAnAllowedShape() {
        for film in films {
            for profile in film.profiles {
                let shape = ProfileShape.classify(profile)
                XCTAssertNotNil(
                    shape,
                    "\(film.canonicalStockName) profile '\(profile.id)' does not match any allowed launch shape (official quantified formula, official limited guidance)."
                )
            }
        }
    }

    // MARK: - Formula profile invariants

    /// Formula profiles preserve manufacturer reference data through
    /// `sourceEvidence`, never through table-shaped rules. This guards
    /// the policy contract that calculation rules cannot accidentally
    /// gain a corrected-time anchor through a different rule type.
    func testFormulaProfileReferenceDataLivesInSourceEvidenceOnly() {
        for film in films {
            for profile in film.profiles where ProfileShape.classify(profile) == .officialQuantifiedFormula {
                for rule in profile.rules {
                    if case let .threshold(threshold) = rule {
                        XCTAssertTrue(
                            threshold.adjustments.isEmpty
                                || onlyContainsNoCorrectionGuidance(threshold.adjustments),
                            "\(film.canonicalStockName): threshold rule must not carry quantified adjustments (those belong in sourceEvidence)."
                        )
                    }
                }
            }
        }
    }

    // MARK: - Limited-guidance profile invariants

    /// Limited-guidance profiles must never carry a formula rule.
    /// Adding one would make the catalog produce a numeric corrected
    /// exposure outside the manufacturer's published guidance.
    func testLimitedGuidanceProfilesDoNotCarryAFormulaRule() {
        for film in films {
            for profile in film.profiles where ProfileShape.classify(profile) == .officialLimitedGuidance {
                let hasFormula = profile.rules.contains { rule in
                    if case .formula = rule { return true }
                    return false
                }
                XCTAssertFalse(
                    hasFormula,
                    "\(film.canonicalStockName): limited-guidance profile must not carry a formula rule."
                )
            }
        }
    }

    /// Limited-guidance profiles must keep `sourceEvidence` empty so
    /// the presenter does not surface a quantified anchor that could
    /// imply a formula fit. This is the structural complement to the
    /// runtime "no-graph" expectation in
    /// `FilmDetailsGraphKindInvariantTests`.
    func testLimitedGuidanceProfilesHaveEmptySourceEvidence() {
        for film in films {
            for profile in film.profiles where ProfileShape.classify(profile) == .officialLimitedGuidance {
                XCTAssertTrue(
                    profile.sourceEvidence.isEmpty,
                    "\(film.canonicalStockName): limited-guidance profile must keep sourceEvidence empty."
                )
            }
        }
    }

    // MARK: - User-facing presentation cannot use legacy wording

    /// User-facing presentation labels must not surface the legacy
    /// table-era vocabulary. Each launch preset is evaluated at a
    /// representative metered exposure and the shortLabel asserted to
    /// avoid "Exact", "Estimated", "Interpolated", "Extrapolated", and
    /// "Advisory".
    func testLaunchPresetPresentationDoesNotUseLegacyTableWording() {
        let banned = ["Exact", "Estimated", "Interpolated", "Extrapolated", "Advisory"]
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let mapper = ReciprocityConfidencePresentationMapper()

        for film in films {
            for profile in film.profiles {
                for metered in [0.1, 1.0, 10.0, 100.0, 600.0] {
                    let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                    let presentation = mapper.map(result: result)
                    for word in banned {
                        XCTAssertFalse(
                            presentation.shortLabel.contains(word),
                            "\(film.canonicalStockName) at \(metered) s surfaced legacy wording '\(word)' in shortLabel '\(presentation.shortLabel)'."
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func onlyContainsNoCorrectionGuidance(_ adjustments: [ReciprocityAdjustment]) -> Bool {
        adjustments.allSatisfy { adjustment in
            switch adjustment {
            case .note, .warning:
                return true
            case .colorFilter, .development, .exposure:
                return false
            }
        }
    }

    enum ProfileShape: Equatable {
        case officialQuantifiedFormula
        case officialLimitedGuidance
        /// PTIMER-159: official manufacturer table evaluated by log-log
        /// interpolation (Fomapan 100).
        case officialTableLogLog

        /// Classifies a launch-catalog profile against the two-shape
        /// allow-list (DomainSchema §13). Returns `nil` for any other
        /// combination, including:
        ///
        /// - non-official authorities (`.unofficial`, `.userDefined`,
        ///   `.unknown`) — unofficial practical profiles are bundled
        ///   outside the launch catalog and have their own test
        ///   surface (`UnofficialPracticalProfilesShapeTests`);
        /// - mixed shapes (formula + limited-guidance);
        /// - partial shapes (formula or limited-guidance without a
        ///   threshold cap; threshold without a formula or
        ///   limited-guidance pair).
        ///
        /// The compiler-enforced absence of `.table` is a separate
        /// guarantee from this classifier.
        static func classify(_ profile: ReciprocityProfile) -> ProfileShape? {
            guard profile.source.authority == .official else { return nil }

            let hasFormula = profile.rules.contains { rule in
                if case .formula = rule { return true }
                return false
            }
            let hasThreshold = profile.rules.contains { rule in
                if case .threshold = rule { return true }
                return false
            }
            let hasLimitedGuidance = profile.rules.contains { rule in
                if case .limitedGuidance = rule { return true }
                return false
            }
            let hasTableInterpolation = profile.rules.contains { rule in
                if case .tableInterpolation = rule { return true }
                return false
            }

            if hasTableInterpolation && !hasFormula && !hasThreshold && !hasLimitedGuidance {
                return .officialTableLogLog
            }
            if hasFormula && !hasThreshold && !hasLimitedGuidance {
                return .officialQuantifiedFormula
            }
            if hasThreshold && hasLimitedGuidance && !hasFormula {
                return .officialLimitedGuidance
            }
            return nil
        }
    }

    // MARK: - Explicit negative shape rejection

    /// `ProfileShape.classify` shall reject every combination that is
    /// not on the allow-list. These cases would slip past the bundled
    /// catalog scan (because no shipped preset uses them today) but
    /// would silently re-enable a calculation shape the policy does not
    /// support. The explicit synthetic profiles below guard the
    /// classifier itself.
    func testClassifyRejectsOfficialFormulaPlusLimitedGuidance() {
        let profile = MixedShapeFactory.officialFormulaPlusLimitedGuidance()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    func testClassifyRejectsOfficialLimitedGuidanceWithoutThresholdCap() {
        let profile = MixedShapeFactory.officialLimitedGuidanceOnly()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    func testClassifyRejectsUnofficialPracticalFormulaProfile() {
        // Unofficial practical profiles are bundled outside the launch
        // catalog (DomainSchema §13.3); the launch-shape classifier
        // returns nil for every unofficial profile regardless of its
        // rule combination.
        let profile = MixedShapeFactory.unofficialFormulaOnly()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    func testClassifyRejectsUnofficialProfileCarryingThresholdRule() {
        let profile = MixedShapeFactory.unofficialFormulaPlusThreshold()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    func testClassifyRejectsUnofficialProfileCarryingLimitedGuidanceRule() {
        let profile = MixedShapeFactory.unofficialFormulaPlusLimitedGuidance()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    func testClassifyRejectsUserDefinedAuthority() {
        let profile = MixedShapeFactory.userDefinedFormulaOnly()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    func testClassifyRejectsUnknownAuthority() {
        let profile = MixedShapeFactory.unknownAuthorityFormulaOnly()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    /// PTIMER-160 made formula-only the canonical shape for formula
    /// profiles; the companion threshold rule was retired. A
    /// formula-only profile must now classify as
    /// `officialQuantifiedFormula`.
    func testClassifyAcceptsOfficialFormulaOnlyProfile() {
        let profile = MixedShapeFactory.officialFormulaWithoutThreshold()
        XCTAssertEqual(ProfileShape.classify(profile), .officialQuantifiedFormula)
    }

    /// PTIMER-160: a companion threshold rule on a formula profile is
    /// no longer a valid shape — the formula owns its no-correction
    /// guard.
    func testClassifyRejectsOfficialFormulaPlusThresholdProfile() {
        let profile = MixedShapeFactory.officialFormulaPlusThreshold()
        XCTAssertNil(ProfileShape.classify(profile))
    }

    // MARK: - Loader-level shape rejection

    /// Loader-level mirror of the classifier negative tests above. The
    /// runtime loader carries its own allow-list (see
    /// `LaunchPresetFilmCatalogLoader.validateProfileShape`) so a
    /// hand-edited catalog file cannot smuggle a mixed-shape profile
    /// past the decoder.
    func testLoaderRejectsFormulaProfileCarryingThresholdCompanion() throws {
        // PTIMER-160: formula profiles own their no-correction guard
        // through the formula struct; a companion threshold rule is no
        // longer allowed.
        let invalidFilm = try shapeProbeFilm(
            profile: MixedShapeFactory.officialFormulaPlusThreshold()
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "formula profiles must not carry a companion threshold rule (the formula owns its no-correction guard)"
            )
        )
    }

    func testLoaderRejectsProfileMixingFormulaAndLimitedGuidance() throws {
        let invalidFilm = try shapeProbeFilm(profile: MixedShapeFactory.officialFormulaPlusLimitedGuidance())
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "formula and limited-guidance rules cannot coexist"
            )
        )
    }

    func testLoaderRejectsThresholdOnlyProfile() throws {
        let invalidFilm = try shapeProbeFilm(profile: MixedShapeFactory.officialThresholdOnly())
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "profile must declare either a formula rule or a threshold + limited-guidance pair"
            )
        )
    }

    func testLoaderRejectsLimitedGuidanceProfileCarryingSourceEvidence() throws {
        let invalidFilm = try shapeProbeFilm(
            profile: MixedShapeFactory.officialLimitedGuidanceWithSourceEvidence()
        )
        let data = try JSONEncoder().encode([invalidFilm])

        let error = try XCTUnwrap(
            assertThrowsAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: data)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(
            error,
            .invalidRuleShape(
                filmID: invalidFilm.id,
                reason: "limited-guidance profiles cannot carry sourceEvidence rows"
            )
        )
    }

    private func shapeProbeFilm(profile: ReciprocityProfile) throws -> FilmIdentity {
        let baseFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        return FilmIdentity(
            id: baseFilm.id,
            kind: baseFilm.kind,
            canonicalStockName: baseFilm.canonicalStockName,
            manufacturer: baseFilm.manufacturer,
            brandLabel: baseFilm.brandLabel,
            aliases: baseFilm.aliases,
            iso: baseFilm.iso,
            productionStatus: baseFilm.productionStatus,
            profiles: [shapeProbeProfile(profile, source: baseFilm.profiles[0].source)],
            userMetadata: baseFilm.userMetadata
        )
    }

    private func shapeProbeProfile(_ profile: ReciprocityProfile, source: ReciprocitySourceProvenance) -> ReciprocityProfile {
        ReciprocityProfile(
            id: profile.id,
            name: profile.name,
            source: source,
            rules: profile.rules,
            notes: profile.notes,
            userMetadata: profile.userMetadata,
            sourceEvidence: profile.sourceEvidence
        )
    }

    private func assertThrowsAndReturn<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Error? {
        do {
            _ = try expression()
            XCTFail("Expected expression to throw an error.", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }
}

private enum MixedShapeFactory {
    static func officialFormulaPlusLimitedGuidance() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.official.formula+limited",
            name: "Mixed",
            source: officialSource(),
            rules: [.threshold(thresholdRule()), .formula(formulaRule()), .limitedGuidance(limitedRule())]
        )
    }

    static func officialLimitedGuidanceOnly() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.official.limited-only",
            name: "Limited only",
            source: officialSource(),
            rules: [.limitedGuidance(limitedRule())]
        )
    }

    static func unofficialFormulaOnly() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.unofficial.formula-only",
            name: "Unofficial formula",
            source: unofficialSource(),
            rules: [.formula(formulaRule())]
        )
    }

    static func unofficialFormulaPlusThreshold() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.unofficial.formula+threshold",
            name: "Unofficial mix",
            source: unofficialSource(),
            rules: [.threshold(thresholdRule()), .formula(formulaRule())]
        )
    }

    static func unofficialFormulaPlusLimitedGuidance() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.unofficial.formula+limited",
            name: "Unofficial mix",
            source: unofficialSource(),
            rules: [.formula(formulaRule()), .limitedGuidance(limitedRule())]
        )
    }

    static func userDefinedFormulaOnly() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.userdefined.formula",
            name: "User defined",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                publisher: "User"
            ),
            rules: [.formula(formulaRule())]
        )
    }

    static func unknownAuthorityFormulaOnly() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.unknown.formula",
            name: "Unknown authority",
            source: ReciprocitySourceProvenance(
                kind: .unknown,
                authority: .unknown,
                publisher: "Unknown"
            ),
            rules: [.formula(formulaRule())]
        )
    }

    static func officialFormulaWithoutThreshold() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.official.formula-only",
            name: "Formula without cap",
            source: officialSource(),
            rules: [.formula(formulaRule())]
        )
    }

    static func officialFormulaPlusThreshold() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.official.formula+threshold",
            name: "Formula with companion threshold",
            source: officialSource(),
            rules: [.threshold(thresholdRule()), .formula(formulaRule())]
        )
    }

    static func officialThresholdOnly() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.official.threshold-only",
            name: "Threshold only",
            source: officialSource(),
            rules: [.threshold(thresholdRule())]
        )
    }

    static func officialLimitedGuidanceWithSourceEvidence() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "mixed.official.limited+evidence",
            name: "Limited with evidence",
            source: officialSource(),
            rules: [.threshold(thresholdRule()), .limitedGuidance(limitedRule())],
            sourceEvidence: [
                ReciprocitySourceEvidenceRow(
                    meteredExposure: .exactSeconds(10),
                    adjustments: [],
                    notes: []
                ),
            ]
        )
    }

    private static func officialSource() -> ReciprocitySourceProvenance {
        ReciprocitySourceProvenance(
            kind: .manufacturerPublished,
            authority: .official,
            publisher: "Test"
        )
    }

    private static func unofficialSource() -> ReciprocitySourceProvenance {
        ReciprocitySourceProvenance(
            kind: .thirdPartyPublication,
            authority: .unofficial,
            publisher: "Test"
        )
    }

    private static func thresholdRule() -> ThresholdReciprocityRule {
        ThresholdReciprocityRule(
            noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 0, maximumSeconds: 1)
        )
    }

    private static func formulaRule() -> FormulaReciprocityRule {
        FormulaReciprocityRule(
            formula: ReciprocityFormula(
                exponent: 1.3,
                noCorrectionThroughSeconds: 1,
                sourceRangeThroughSeconds: 100
            )
        )
    }

    private static func limitedRule() -> LimitedGuidanceReciprocityRule {
        LimitedGuidanceReciprocityRule(
            appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1)
        )
    }
}
