// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore

/// Shared custom-film fixture (Core-only). Duplicated into the app test
/// target so app-hosted custom-film tests keep using the same factory
/// after CustomFilmLibraryTests moved off-simulator.
enum CustomFilmTestSupport {
    static func makeCustomFilm(
        id: String,
        stockName: String = "Custom film",
        iso: Int = 100,
        exponent: Double = 1.30,
        sourceType: CustomProfileSourceType = .userDefined
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(exponent: exponent
        , noCorrectionThroughSeconds: 1)
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: "Profile for \(stockName)",
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
            id: id,
            kind: .custom,
            canonicalStockName: stockName,
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: sourceType)
        )
    }
}
