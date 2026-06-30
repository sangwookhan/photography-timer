// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-170: the two accepted app-derived formula alternates —
/// T-MAX 100 (`Tc = 1.2364 × Tm^1.1003`) and CHS 100 II
/// (`Tc = 1.2102 × Tm^1.3423`). Locks the registry shape, the default
/// table model staying default, the formula outputs against the
/// published anchors, the app-derived labeling that keeps the fit
/// from reading as manufacturer source data, and restore by profile
/// id. The films whose fits failed the PTIMER-170 residual policy
/// must NOT gain a formula alternate (see
/// `AppDerivedFormulaEvaluationTests` for the evaluation).
final class AppDerivedFormulaAlternateTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    private struct AcceptedAlternate {
        let stock: String
        let filmID: String
        let profileID: String
        let coefficient: Double
        let exponent: Double
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double
        /// Published (metered, corrected) rows the formula approximates.
        let anchors: [(metered: Double, corrected: Double)]
        /// Worst tolerated |stop error| at any anchor, from the
        /// evaluation fixture, with headroom for constant rounding.
        let worstStopError: Double
    }

    private let accepted: [AcceptedAlternate] = [
        AcceptedAlternate(
            stock: "T-MAX 100",
            filmID: "kodak-tmax-100",
            profileID: "kodak-tmax-100-app-formula",
            coefficient: 1.2364,
            exponent: 1.1003,
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            anchors: [(1, 1.2599210498948732), (10, 15), (100, 200)],
            worstStopError: 0.055
        ),
        AcceptedAlternate(
            stock: "CHS 100 II",
            filmID: "adox-chs-100-ii",
            profileID: "adox-chs-100-ii-app-formula",
            coefficient: 1.2102,
            exponent: 1.3423,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 15,
            anchors: [(2, 3), (4, 8), (8, 20), (15, 45)],
            worstStopError: 0.041
        ),
    ]

    // MARK: - Registry shape

    func testAcceptedFilmsExposeExactlyOneAppFormulaAlternate() {
        for entry in accepted {
            let alternates = AlternateReciprocityModels.alternates(forFilmID: entry.filmID)
            XCTAssertEqual(
                alternates.map(\.id), [entry.profileID],
                "\(entry.stock) must expose exactly the app-derived formula alternate."
            )
            XCTAssertTrue(
                AlternateReciprocityModels.isAppDerivedModel(id: entry.profileID),
                "\(entry.stock) app formula must be enrolled as an app-derived model."
            )
        }
    }

    func testRejectedCandidatesGainNoAlternate() {
        // Borderline (T-MAX 400, Fomapan 200) and poor fits (Fomapan
        // 400, RPX 100/400) are document-only decisions.
        for filmID in [
            "kodak-tmax-400", "foma-fomapan-200", "foma-fomapan-400",
            "rollei-rpx-100", "rollei-rpx-400",
        ] {
            XCTAssertTrue(
                AlternateReciprocityModels.alternates(forFilmID: filmID).isEmpty,
                "\(filmID) failed the PTIMER-170 residual policy and must not ship a formula alternate."
            )
        }
    }

    func testRestoreResolvesAcceptedAlternatesByID() throws {
        for entry in accepted {
            let restored = try XCTUnwrap(
                AlternateReciprocityModels.profile(withID: entry.profileID),
                "\(entry.stock) app formula must resolve by id for session restore."
            )
            XCTAssertEqual(restored.id, entry.profileID)
        }
    }

    // MARK: - Default table model stays default

    func testDefaultProfileRemainsTableInterpolation() throws {
        for entry in accepted {
            let film = try XCTUnwrap(
                LaunchPresetFilmCatalogV2.films.first { $0.id == entry.filmID }
            )
            let defaultProfile = try XCTUnwrap(film.profiles.first)
            XCTAssertTrue(
                defaultProfile.usesTableInterpolation,
                "\(entry.stock) default must remain the official table model."
            )
            // Default still reproduces a published anchor exactly.
            let anchor = entry.anchors[1]
            let result = evaluator.evaluate(
                profile: defaultProfile,
                meteredExposureSeconds: anchor.metered
            )
            XCTAssertEqual(result.metadata.basis, .tableLogLogDerived)
            XCTAssertEqual(
                try XCTUnwrap(result.correctedExposureSeconds),
                anchor.corrected,
                accuracy: 1e-4,
                "\(entry.stock) default table must keep reproducing the published anchors exactly."
            )
        }
    }

    // MARK: - Formula behavior

    func testAppFormulaStaysWithinEvaluatedResidualAtEveryAnchor() throws {
        for entry in accepted {
            let profile = try alternateProfile(entry)
            for anchor in entry.anchors {
                let result = evaluator.evaluate(
                    profile: profile,
                    meteredExposureSeconds: anchor.metered
                )
                XCTAssertEqual(
                    result.metadata.basis, .formulaDerived,
                    "\(entry.stock) app formula at \(anchor.metered) s must be formula-derived."
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                XCTAssertLessThanOrEqual(
                    abs(log2(corrected / anchor.corrected)),
                    entry.worstStopError,
                    "\(entry.stock) app formula at \(anchor.metered) s must stay within the evaluated residual."
                )
            }
        }
    }

    func testAppFormulaKeepsTableBoundaries() throws {
        for entry in accepted {
            let profile = try alternateProfile(entry)
            let formula = try XCTUnwrap(
                profile.rules.compactMap { rule -> ReciprocityFormula? in
                    if case let .formula(formulaRule) = rule { return formulaRule.formula }
                    return nil
                }.first
            )
            XCTAssertEqual(formula.coefficientSeconds, entry.coefficient, accuracy: 1e-9)
            XCTAssertEqual(formula.exponent, entry.exponent, accuracy: 1e-9)
            XCTAssertEqual(
                formula.noCorrectionThroughSeconds,
                entry.noCorrectionThroughSeconds,
                accuracy: 1e-9,
                "\(entry.stock) app formula must keep the table's no-correction band."
            )
            XCTAssertEqual(
                formula.sourceRangeThroughSeconds ?? -1,
                entry.sourceRangeThroughSeconds,
                accuracy: 1e-9,
                "\(entry.stock) app formula must keep the table's published source range."
            )

            // Inside the no-correction band: identity.
            let below = evaluator.evaluate(
                profile: profile,
                meteredExposureSeconds: entry.noCorrectionThroughSeconds / 2
            )
            XCTAssertEqual(below.metadata.basis, .officialThresholdNoCorrection)

            // Beyond the published range: numeric continuation
            // classified beyond source range.
            let beyond = evaluator.evaluate(
                profile: profile,
                meteredExposureSeconds: entry.sourceRangeThroughSeconds * 2
            )
            guard case let .unsupported(payload) = beyond else {
                XCTFail("\(entry.stock) app formula past the source range must classify as unsupported.")
                continue
            }
            XCTAssertNotNil(
                payload.correctedExposureSeconds,
                "\(entry.stock) app formula keeps a numeric continuation past the source range."
            )
        }
    }

    // MARK: - Cannot be mistaken for manufacturer source data

    func testAppFormulaIsLabeledAppDerivedNotManufacturer() throws {
        for entry in accepted {
            let profile = try alternateProfile(entry)
            XCTAssertFalse(
                profile.name.hasPrefix("Official"),
                "\(entry.stock) app formula name must not read as official; got '\(profile.name)'."
            )
            XCTAssertTrue(
                profile.name.contains("App"),
                "\(entry.stock) app formula name must read as app-derived; got '\(profile.name)'."
            )
            let basis = try XCTUnwrap(profile.modelBasis)
            XCTAssertEqual(
                basis.sourceModel, .manufacturerTable,
                "\(entry.stock) app formula's source stays the manufacturer table it was fitted against."
            )
            XCTAssertEqual(
                basis.calculationModel, .guardedFormula,
                "\(entry.stock) app formula's calculation is the app's guarded formula."
            )
        }
    }

    @MainActor
    func testAppFormulaSurfacesAppDerivedComparisonAgainstPublishedRows() throws {
        let presenter = ReciprocityModelComparisonPresenter()
        for entry in accepted {
            let profile = try alternateProfile(entry)
            let section = try XCTUnwrap(
                presenter.comparisonSection(
                    for: profile,
                    formatDuration: { String(format: "%.2fs", $0) }
                ),
                "\(entry.stock) app formula must surface the app-derived comparison."
            )
            let table = try XCTUnwrap(section.rows.first?.value)
            for anchor in entry.anchors {
                XCTAssertTrue(
                    table.contains(String(format: "%.2fs", anchor.metered)),
                    "\(entry.stock) comparison must include the \(anchor.metered) s published row. Got:\n\(table)"
                )
            }
            XCTAssertTrue(
                section.rows.contains { $0.value.contains("Not manufacturer-published guidance.") },
                "\(entry.stock) comparison must carry the non-source disclaimer."
            )
        }
    }

    /// The comparison's Source column must anchor on the row's
    /// EXPLICIT published corrected time, even when the row lists a
    /// stop delta or multiplier first. T-MAX 100's "10 s → +1/2 stop,
    /// corrected 15 s" row regressed to the 2^0.5-derived 14.14 s
    /// before the presenter applied its documented priority — which
    /// inflated the displayed error to +0.139 stop and contradicted
    /// the evaluated 0.054 stop residual.
    @MainActor
    func testComparisonSourceColumnPrefersExplicitCorrectedTime() throws {
        let presenter = ReciprocityModelComparisonPresenter()

        let tmax = try XCTUnwrap(accepted.first { $0.stock == "T-MAX 100" })
        let tmaxTable = try XCTUnwrap(
            presenter.comparisonSection(
                for: try alternateProfile(tmax),
                formatDuration: { String(format: "%.2fs", $0) }
            )?.rows.first?.value
        )
        XCTAssertTrue(
            tmaxTable.contains("15.00s"),
            "T-MAX 100's 10 s row must anchor on the published corrected 15 s. Got:\n\(tmaxTable)"
        )
        XCTAssertTrue(
            tmaxTable.contains("15.58s"),
            "T-MAX 100's 10 s row must show the ≈15.58 s app value. Got:\n\(tmaxTable)"
        )
        XCTAssertTrue(
            tmaxTable.contains("+0.054 stop"),
            "T-MAX 100's 10 s row error must match the evaluated residual. Got:\n\(tmaxTable)"
        )
        XCTAssertFalse(
            tmaxTable.contains("14.14s"),
            "T-MAX 100's 10 s row must not fall back to the stop-delta-derived 14.14 s. Got:\n\(tmaxTable)"
        )

        let chs = try XCTUnwrap(accepted.first { $0.stock == "CHS 100 II" })
        let chsTable = try XCTUnwrap(
            presenter.comparisonSection(
                for: try alternateProfile(chs),
                formatDuration: { String(format: "%.2fs", $0) }
            )?.rows.first?.value
        )
        XCTAssertTrue(
            chsTable.contains("20.00s") && chsTable.contains("19.73s"),
            "CHS 100 II's 8 s row must read published 20 s vs app ≈19.73 s. Got:\n\(chsTable)"
        )
    }

    // MARK: - Helpers

    private func alternateProfile(
        _ entry: AcceptedAlternate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: entry.filmID)
                .first { $0.id == entry.profileID },
            "\(entry.stock) app formula must be registered as an alternate.",
            file: file,
            line: line
        )
    }
}
