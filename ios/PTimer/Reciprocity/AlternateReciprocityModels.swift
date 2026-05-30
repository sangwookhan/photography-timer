import Foundation

/// Registry of alternate reciprocity profiles/models that live OUTSIDE
/// the launch preset catalog (which enforces exactly one official
/// profile per film). These are selectable through the model selector
/// (the main-screen segmented control, mirrored in Reciprocity Details)
/// via `selectedProfileOverride`, never as duplicate top-level film
/// rows (PTIMER-159).
///
/// Two films currently expose an alternate model:
/// - Kodak Portra 400 — an unofficial practical approximation
///   (lower authority; defined in `UnofficialPracticalProfiles`).
/// - Fomapan 100 Classic — an APP-DERIVED formula fitted to the
///   official FOMA table. It is non-default (the official table
///   log-log model is the default) and is clearly labelled app-derived,
///   never presented as the official source/model.
enum AlternateReciprocityModels {

    /// Alternate models for a film stock, in display order. Empty when
    /// the film has only its single catalog profile.
    static func alternates(forFilmID filmID: String) -> [ReciprocityProfile] {
        switch filmID {
        case "kodak-portra-400":
            return [UnofficialPracticalProfiles.kodakPortra400UnofficialPractical]
        case "foma-fomapan-100":
            return [fomapan100AppDerivedFormula]
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
            fomapan100AppDerivedFormula,
        ]
        return all.first { $0.id == profileID }
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
