import Foundation

/// Registry of alternate reciprocity profiles/models that live OUTSIDE
/// the launch preset catalog (which enforces exactly one official
/// profile per film). These are selectable through the model selector
/// (the main-screen segmented control, mirrored in Reciprocity Details)
/// via `selectedProfileOverride`, never as duplicate top-level film
/// rows (PTIMER-159).
///
/// Films that currently expose an alternate model:
/// - Kodak Portra 400 — an unofficial practical approximation
///   (lower authority; defined in `UnofficialPracticalProfiles`).
/// - Fomapan 100 Classic — two non-default alternates alongside the
///   default official FOMA table log-log model: the Ohzart community
///   practical table (a table-derived model that reproduces the
///   community anchors exactly) and an APP-DERIVED formula fitted to the
///   official FOMA table. Both are clearly labelled and never presented
///   as the official source/model.
enum AlternateReciprocityModels {

    /// Alternate models for a film stock, in display order. Empty when
    /// the film has only its single catalog profile.
    static func alternates(forFilmID filmID: String) -> [ReciprocityProfile] {
        switch filmID {
        case "kodak-portra-400":
            return [UnofficialPracticalProfiles.kodakPortra400UnofficialPractical]
        case "foma-fomapan-100":
            // Display order after the default official table:
            // Ohzart community table, then the app-derived formula.
            return [fomapan100OhzartCommunityTable, fomapan100AppDerivedFormula]
        default:
            return []
        }
    }

    /// `true` for explicitly app-derived alternate models (a formula the
    /// app fitted to a manufacturer table). The "App-derived comparison"
    /// section is intentionally limited to these enrolled models, so it
    /// never leaks onto official converted-formula profiles (Tri-X,
    /// Provia, etc.) that merely carry source anchors. Any future
    /// app-derived alternate must be enrolled here to surface its
    /// comparison (PTIMER-159).
    static func isAppDerivedModel(id: String) -> Bool {
        id == fomapan100AppDerivedFormula.id
    }

    /// Resolves an alternate profile by its id (used by session restore
    /// to reconstruct a persisted profile override).
    static func profile(withID profileID: String) -> ReciprocityProfile? {
        let all = [
            UnofficialPracticalProfiles.kodakPortra400UnofficialPractical,
            fomapan100OhzartCommunityTable,
            fomapan100AppDerivedFormula,
        ]
        return all.first { $0.id == profileID }
    }

    /// Ohzart community practical table for Fomapan 100 — an
    /// unofficial, test-based community source (not FOMA-published).
    /// Modelled as a TABLE, not a fitted formula: the published anchors
    /// (1s→1.9s … 60s→795s) are reproduced exactly by the same log-log
    /// interpolation the official FOMA table uses, so every Ohzart row
    /// comes back without fitting error. It shares Official FOMA's
    /// 0.5 s no-correction boundary; its published range ends at 60 s,
    /// past which the model extrapolates the last segment and presents
    /// the value as beyond source range. Kept non-default and labelled
    /// "Ohzart"; its source rows stay separate from the official FOMA
    /// table and never read as manufacturer data.
    static let fomapan100OhzartCommunityTable = ReciprocityProfile(
        id: "foma-fomapan-100-ohzart-community-table",
        name: "Ohzart community table",
        source: ReciprocitySourceProvenance(
            kind: .thirdPartyPublication,
            authority: .unofficial,
            confidence: .medium,
            publisher: "Ohzart",
            title: "Reciprocity practical table",
            citation: "https://ohzart1.tistory.com/78"
        ),
        rules: [
            .tableInterpolation(TableInterpolationReciprocityRule(
                anchors: [
                    TableAnchor(meteredSeconds: 1, correctedSeconds: 1.9),
                    TableAnchor(meteredSeconds: 2, correctedSeconds: 5),
                    TableAnchor(meteredSeconds: 4, correctedSeconds: 13),
                    TableAnchor(meteredSeconds: 8, correctedSeconds: 35),
                    TableAnchor(meteredSeconds: 15, correctedSeconds: 90),
                    TableAnchor(meteredSeconds: 30, correctedSeconds: 265),
                    TableAnchor(meteredSeconds: 60, correctedSeconds: 795),
                ],
                notes: [
                    "Ohzart community practical table for Fomapan 100, reproduced by log-log interpolation between the published anchors. Practical / community guidance, not FOMA-published data.",
                ],
                noCorrectionThroughSeconds: 0.5,
                sourceRangeThroughSeconds: 60
            )),
        ],
        notes: [
            "Unofficial practical community table (Ohzart). Not FOMA-published data.",
        ],
        sourceEvidence: ohzartCommunityAnchorEvidence,
        modelBasis: ReciprocityProfileModelBasis(
            sourceModel: .practicalCommunityGuidance,
            calculationModel: .tableLogLogInterpolation
        ),
        selectorLabel: "Ohzart"
    )

    /// The Ohzart anchor rows preserved as source evidence so the
    /// "Source reference" section and graph markers show the community
    /// table values (kept distinct from the official FOMA anchors).
    /// Ohzart publishes corrected times directly, so each row carries
    /// only a corrected-time mapping — no multiplier column.
    private static let ohzartCommunityAnchorEvidence: [ReciprocitySourceEvidenceRow] = [
        ohzartAnchorEvidence(metered: 1, corrected: 1.9),
        ohzartAnchorEvidence(metered: 2, corrected: 5),
        ohzartAnchorEvidence(metered: 4, corrected: 13),
        ohzartAnchorEvidence(metered: 8, corrected: 35),
        ohzartAnchorEvidence(metered: 15, corrected: 90),
        ohzartAnchorEvidence(metered: 30, corrected: 265),
        ohzartAnchorEvidence(metered: 60, corrected: 795),
    ]

    private static func ohzartAnchorEvidence(
        metered: Double,
        corrected: Double
    ) -> ReciprocitySourceEvidenceRow {
        ReciprocitySourceEvidenceRow(
            meteredExposure: .exactSeconds(metered),
            adjustments: [
                .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: metered, correctedSeconds: corrected))),
            ]
        )
    }

    /// App-derived guarded formula for Fomapan 100 — the retired free
    /// log-log fit `Tc = 2.2457 × Tm^1.4515`. Source is the official
    /// FOMA table (so it cites FOMA), but the calculation is the app's
    /// own fitted formula, not manufacturer-published guidance. Kept
    /// non-default and clearly labelled; selecting it surfaces the
    /// app-derived comparison against the official anchors.
    static let fomapan100AppDerivedFormula = ReciprocityProfile(
        id: "foma-fomapan-100-app-formula",
        name: "App-derived formula",
        source: ReciprocitySourceProvenance(
            kind: .manufacturerPublished,
            authority: .official,
            confidence: .high,
            publisher: "FOMA BOHEMIA",
            title: "FOMAPAN 100 CLASSIC — Technical sheet",
            citation: "Foma technical sheet"
        ),
        rules: [
            .formula(FormulaReciprocityRule(
                formula: ReciprocityFormula(
                    formulaFamily: .modifiedSchwarzschild,
                    coefficientSeconds: 2.2457,
                    exponent: 1.4515,
                    noCorrectionThroughSeconds: 0.5,
                    sourceRangeThroughSeconds: 100.0
                ),
                notes: [
                    "App-derived: Tc = 2.2457 × Tm^1.4515, a free log-log fit through FOMA's published 1/10/100 sec anchors. Not manufacturer-published guidance; the official table model is the default.",
                ]
            )),
        ],
        sourceEvidence: fomapanOfficialAnchorEvidence,
        modelBasis: ReciprocityProfileModelBasis(
            sourceModel: .manufacturerTable,
            calculationModel: .guardedFormula
        )
    )

    /// The official FOMA anchor rows, preserved as source evidence so a
    /// formula-model comparison can be shown against the published data.
    private static let fomapanOfficialAnchorEvidence: [ReciprocitySourceEvidenceRow] = [
        anchorEvidence(metered: 1, multiplier: 2, corrected: 2, note: "1 sec → ×2 (corrected 2 sec)."),
        anchorEvidence(metered: 10, multiplier: 8, corrected: 80, note: "10 sec → ×8 (corrected 80 sec)."),
        anchorEvidence(metered: 100, multiplier: 16, corrected: 1600, note: "100 sec → ×16 (corrected 1600 sec)."),
    ]

    private static func anchorEvidence(
        metered: Double,
        multiplier: Double,
        corrected: Double,
        note: String
    ) -> ReciprocitySourceEvidenceRow {
        ReciprocitySourceEvidenceRow(
            meteredExposure: .exactSeconds(metered),
            adjustments: [
                .exposure(.multiplier(MultiplierAdjustment(factor: multiplier))),
                .exposure(.correctedTime(CorrectedTimeMapping(meteredSeconds: metered, correctedSeconds: corrected))),
            ],
            notes: [note]
        )
    }
}
