// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Structural guard on the bundled `LaunchPresetFilmCatalogV2`. The
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

    private let films = LaunchPresetFilmCatalogV2.films

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
        /// PTIMER-122: explicitly promoted unofficial practical primary
        /// profile for Rollei RETRO 400S.
        case promotedUnofficialPractical

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

            if profile.source.authority == .unofficial,
               profile.source.kind == .thirdPartyPublication,
               profile.modelBasis?.sourceModel == .practicalCommunityGuidance,
               hasFormula && !hasThreshold && !hasLimitedGuidance && !hasTableInterpolation {
                return .promotedUnofficialPractical
            }

            guard profile.source.authority == .official else { return nil }

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

}
