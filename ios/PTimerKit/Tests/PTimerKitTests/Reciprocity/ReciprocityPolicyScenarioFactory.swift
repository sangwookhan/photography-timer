// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore

/// Shared reciprocity policy scenario fixtures (Core-only). Duplicated
/// into the app test target so app-hosted snapshot / model tests that
/// also use these scenarios keep compiling after the relocation.
enum ReciprocityPolicyScenarioFactory {
    /// HP5+-shaped formula profile (Tc = Tm^1.31 above 1s). Used as
    /// the canonical formula profile for tests that don't care about
    /// the manufacturer. Authority maps from the policy
    /// authority-impact enum so a single scenario can stand in for
    /// archival/secondary/user-defined variants.
    static func barePowerLawFormulaProfile(
        authority: ReciprocitySourceAuthorityImpact = .currentOfficial
    ) -> ReciprocityProfile {
        ReciprocityProfile(
            id: "ilford-hp5-plus-official-formula",
            name: "Official formula",
            source: provenance(for: authority, publisher: "Ilford Photo"),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.31,
                            noCorrectionThroughSeconds: 1
                        ),
                        notes: ["Exponent p = 1.31."]
                    )
                ),
            ]
        )
    }

    /// Threshold + limited-guidance profile shape used by Kodak
    /// color negatives (Portra / Ektar / Gold).
    static func limitedGuidanceProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "kodak-portra-official-threshold",
            name: "Official threshold guidance",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Kodak",
                title: "Reciprocity statement"
            ),
            rules: [
                .threshold(
                    ThresholdReciprocityRule(
                        noCorrectionRange: ReciprocityTimeRange(minimumSeconds: 1.0 / 10_000.0, maximumSeconds: 1),
                        notes: ["No correction required in the official range."]
                    )
                ),
                .limitedGuidance(
                    LimitedGuidanceReciprocityRule(
                        appliesWhenMetered: ReciprocityTimeRange(minimumSeconds: 1),
                        adjustments: [
                            .note(ReciprocityNote(text: "Longer exposures: test under your conditions.")),
                        ]
                    )
                ),
            ]
        )
    }

    /// Formula profile whose `sourceRangeThroughSeconds = 600`
    /// triggers the beyond-source-range path: past the boundary the
    /// result is reclassified as `unsupported` but the formula still
    /// produces a numeric prediction (per the PTIMER-160 shared
    /// guarded formula contract — `sourceRangeThroughSeconds` is a
    /// confidence boundary, not a calculation stop).
    static func formulaBoundedProfile() -> ReciprocityProfile {
        ReciprocityProfile(
            id: "bounded-formula-profile",
            name: "Bounded formula",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: "Test Publisher"
            ),
            rules: [
                .formula(
                    FormulaReciprocityRule(
                        formula: ReciprocityFormula(
                            exponent: 1.31,
                            noCorrectionThroughSeconds: 1,
                            sourceRangeThroughSeconds: 600
                        )
                    )
                ),
            ]
        )
    }

    private static func provenance(
        for authority: ReciprocitySourceAuthorityImpact,
        publisher: String
    ) -> ReciprocitySourceProvenance {
        switch authority {
        case .currentOfficial:
            return ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                confidence: .high,
                publisher: publisher
            )
        case .archivalOfficial:
            return ReciprocitySourceProvenance(
                kind: .manufacturerArchive,
                authority: .official,
                confidence: .medium,
                publisher: publisher
            )
        case .unofficialSecondary:
            return ReciprocitySourceProvenance(
                kind: .thirdPartyPublication,
                authority: .unofficial,
                confidence: .low,
                publisher: publisher
            )
        case .userDefined:
            return ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: publisher
            )
        }
    }
}
