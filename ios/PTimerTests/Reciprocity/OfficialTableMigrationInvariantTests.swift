import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// PTIMER-168 catalog-wide regression coverage for the official
/// table-origin migration batch.
///
/// Locks the invariants that the eight migrated profiles default to
/// the table log-log model, preserve their official source anchors,
/// reproduce the published rows exactly, and that the films
/// deliberately left out of PTIMER-168 — true manufacturer formula
/// films, limited-guidance Kodak color films, and the PTIMER-169
/// special / range / sparse cases — are unchanged.
final class OfficialTableMigrationInvariantTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// A PTIMER-168 target film and its representative published
    /// source anchors (metered → corrected seconds).
    private struct MigratedFilm {
        let stock: String
        let anchors: [(metered: Double, corrected: Double)]
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double
    }

    private let migratedFilms: [MigratedFilm] = [
        MigratedFilm(stock: "Fomapan 200 Creative", anchors: [(1, 3), (10, 90), (100, 1800)], noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: 100),
        MigratedFilm(stock: "Fomapan 400 Action", anchors: [(1, 1.5), (10, 60), (100, 800)], noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: 100),
        MigratedFilm(stock: "Tri-X 400", anchors: [(1, 2), (2, 5), (3, 10), (5, 20), (7, 32), (10, 50), (20, 120), (30, 200), (50, 420), (70, 720), (100, 1200)], noCorrectionThroughSeconds: 0.1, sourceRangeThroughSeconds: 100),
        MigratedFilm(stock: "T-MAX 100", anchors: [(1, 1.2599210498948732), (10, 15), (100, 200)], noCorrectionThroughSeconds: 0.1, sourceRangeThroughSeconds: 100),
        MigratedFilm(stock: "T-MAX 400", anchors: [(1, 1.2599210498948732), (10, 15), (100, 300)], noCorrectionThroughSeconds: 0.1, sourceRangeThroughSeconds: 100),
        MigratedFilm(stock: "RPX 100", anchors: [(2, 3), (5, 8), (10, 25), (20, 75), (30, 150)], noCorrectionThroughSeconds: 1, sourceRangeThroughSeconds: 30),
        MigratedFilm(stock: "RPX 400", anchors: [(1, 2), (5, 10), (10, 30), (15, 55), (20, 80)], noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: 20),
        MigratedFilm(stock: "CHS 100 II", anchors: [(2, 3), (4, 8), (8, 20), (15, 45)], noCorrectionThroughSeconds: 1, sourceRangeThroughSeconds: 15),
    ]

    // MARK: - 1. Targets default to the table log-log model

    func testMigratedProfilesDefaultToTableLogLogModel() throws {
        for film in migratedFilms {
            let profile = try profile(film.stock)
            let basis = try XCTUnwrap(
                profile.modelBasis,
                "\(film.stock) must declare an explicit table modelBasis."
            )
            XCTAssertEqual(basis.sourceModel, .manufacturerTable, "\(film.stock) source model")
            XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation, "\(film.stock) calculation model")
            XCTAssertTrue(profile.usesTableInterpolation, "\(film.stock) must evaluate through the table model.")
        }
    }

    // MARK: - 2. No target keeps a manufacturer formula default

    func testMigratedProfilesCarryNoFormulaRule() throws {
        for film in migratedFilms {
            let profile = try profile(film.stock)
            XCTAssertFalse(
                profile.rules.contains { if case .formula = $0 { return true }; return false },
                "\(film.stock) must not keep a manufacturer formula default after PTIMER-168."
            )
            XCTAssertFalse(
                profile.isConvertedFormulaProfile,
                "\(film.stock) must no longer surface as a converted formula profile."
            )
        }
    }

    // MARK: - 3. Official source anchors stay present

    func testMigratedProfilesPreserveOfficialSourceEvidence() throws {
        for film in migratedFilms {
            let profile = try profile(film.stock)
            XCTAssertFalse(
                profile.sourceEvidence.isEmpty,
                "\(film.stock) must keep its official source-evidence rows for the Source reference surface."
            )
            XCTAssertEqual(profile.source.authority, .official, "\(film.stock) authority")
            XCTAssertEqual(profile.source.kind, .manufacturerPublished, "\(film.stock) source kind")
        }
    }

    // MARK: - 4. Representative anchors reproduce the published rows exactly

    func testMigratedProfilesReproducePublishedAnchorsExactly() throws {
        for film in migratedFilms {
            let profile = try profile(film.stock)
            for anchor in film.anchors {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: anchor.metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .tableLogLogDerived,
                    "\(film.stock) at \(anchor.metered) s must evaluate as table-derived."
                )
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                XCTAssertEqual(
                    corrected,
                    anchor.corrected,
                    accuracy: 1e-4,
                    "\(film.stock) at \(anchor.metered) s must reproduce the published \(anchor.corrected) s anchor exactly."
                )
            }
        }
    }

    func testMigratedProfilesTableRuleBoundariesMatchSource() throws {
        for film in migratedFilms {
            let profile = try profile(film.stock)
            let rule = try XCTUnwrap(
                profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                    if case let .tableInterpolation(rule) = rule { return rule }
                    return nil
                }.first,
                "\(film.stock) must carry a tableInterpolation rule."
            )
            XCTAssertEqual(
                rule.noCorrectionThroughSeconds,
                film.noCorrectionThroughSeconds,
                accuracy: 1e-9,
                "\(film.stock) no-correction boundary"
            )
            XCTAssertEqual(
                rule.sourceRangeThroughSeconds,
                film.sourceRangeThroughSeconds,
                accuracy: 1e-9,
                "\(film.stock) source range"
            )
            let anchorMap = Dictionary(
                uniqueKeysWithValues: rule.anchors.map { ($0.meteredSeconds, $0.correctedSeconds) }
            )
            XCTAssertEqual(rule.anchors.count, film.anchors.count, "\(film.stock) anchor count")
            for anchor in film.anchors {
                XCTAssertEqual(
                    anchorMap[anchor.metered] ?? -1,
                    anchor.corrected,
                    accuracy: 1e-9,
                    "\(film.stock) anchor at \(anchor.metered) s"
                )
            }
        }
    }

    // MARK: - 5. Non-target single-model manufacturer formula films still work

    func testTrueManufacturerFormulaFilmRemainsFormula() throws {
        // HP5 Plus is an Ilford-style manufacturer formula profile with
        // no source table; PTIMER-168 must leave it untouched.
        let hp5 = try profile("HP5 Plus")
        XCTAssertEqual(hp5.effectiveModelBasis.sourceModel, .manufacturerFormula)
        XCTAssertEqual(hp5.effectiveModelBasis.calculationModel, .guardedFormula)
        XCTAssertFalse(hp5.usesTableInterpolation)

        let result = evaluator.evaluate(profile: hp5, meteredExposureSeconds: 4)
        XCTAssertEqual(result.metadata.basis, .formulaDerived)
    }

    // MARK: - 6. Limited-guidance Kodak color films stay limited guidance

    func testLimitedGuidanceKodakColorFilmsRemainLimitedGuidance() throws {
        let limitedGuidanceStocks = [
            "Ektar 100", "Portra 160", "Portra 400", "Gold 200", "Ultra Max 400", "Ektachrome E100",
        ]
        for stock in limitedGuidanceStocks {
            let profile = try profile(stock)
            XCTAssertEqual(
                profile.effectiveModelBasis.calculationModel,
                .limitedGuidance,
                "\(stock) must remain limited guidance, never quantified prediction."
            )
            XCTAssertFalse(
                profile.usesTableInterpolation,
                "\(stock) must not gain a table model in PTIMER-168."
            )
        }
    }

    // MARK: - 7. PTIMER-169 special / range / sparse cases are not migrated

    func testPtimer169SpecialCasesAreNotMigrated() throws {
        // Range guidance, slide-film table + not-recommended boundary,
        // range-valued rows, and sparse special anchors are deferred to
        // PTIMER-169 and must still carry their formula rule.
        let deferredStocks = [
            "Acros II", "Velvia 50", "Velvia 100", "Provia 100F", "RETRO 80S", "SUPERPAN 200", "CMS 20 II",
        ]
        for stock in deferredStocks {
            let profile = try profile(stock)
            XCTAssertFalse(
                profile.usesTableInterpolation,
                "\(stock) must NOT be migrated to a table model in PTIMER-168 (deferred to PTIMER-169)."
            )
            XCTAssertTrue(
                profile.rules.contains { if case .formula = $0 { return true }; return false },
                "\(stock) must still carry its formula rule pending PTIMER-169."
            )
        }
    }

    // MARK: - Helpers

    private func profile(
        _ stock: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog.",
            file: file,
            line: line
        )
        return try XCTUnwrap(film.profiles.first, file: file, line: line)
    }
}
