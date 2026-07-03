// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit
import PTimerCore
import XCTest

final class LaunchPresetFilmCatalogTests: XCTestCase {

    // MARK: - Bundle loading

    func testBundledLaunchPresetFilmCatalogLoadsSuccessfully() throws {
        let films = try LaunchPresetFilmCatalogV2Loader().loadBundledCatalog()
        XCTAssertEqual(films.count, LaunchCatalogExpectations.scopeCount)
        XCTAssertEqual(films.map(\.canonicalStockName), LaunchCatalogExpectations.canonicalStockOrder)
    }

    func testBundledLaunchPresetFilmCatalogPreservesExpectedSelectorOrdering() {
        XCTAssertEqual(LaunchPresetFilmCatalogV2.films.count, LaunchCatalogExpectations.scopeCount)
        XCTAssertEqual(
            LaunchPresetFilmCatalogV2.films.map(\.canonicalStockName),
            LaunchCatalogExpectations.canonicalStockOrder
        )
    }

    // MARK: - PTIMER-86 launch-policy invariants

    func testLaunchPresetFilmCatalogRespectsPTIMER86LaunchPolicyConstraints() {
        XCTAssertFalse(LaunchPresetFilmCatalogV2.films.isEmpty)

        for film in LaunchPresetFilmCatalogV2.films {
            XCTAssertEqual(film.kind, .preset)
            XCTAssertEqual(film.productionStatus, .current)
            XCTAssertEqual(film.profiles.count, 1, "Launch flow should use one primary profile per film identity.")
            XCTAssertFalse(film.canonicalStockName.isEmpty)

            let profile = film.profiles[0]
            if film.id == "rollei-retro-400s" {
                XCTAssertEqual(profile.source.kind, .thirdPartyPublication)
                XCTAssertEqual(profile.source.authority, .unofficial)
                XCTAssertEqual(profile.source.confidence, .medium)
                XCTAssertTrue(profile.source.publisher.contains("Lafitte"))
            } else {
                XCTAssertEqual(profile.source.kind, .manufacturerPublished)
                XCTAssertEqual(profile.source.authority, .official)
                XCTAssertEqual(profile.source.confidence, .high)
                XCTAssertFalse(profile.source.publisher.isEmpty)
            }
            XCTAssertNil(film.userMetadata)
            XCTAssertNil(profile.userMetadata)
        }
    }

    // MARK: - Manufacturer-batch completeness

    // MARK: - Catalog membership per manufacturer

    private struct ManufacturerMembershipCase {
        let manufacturer: String
        let expectedCount: Int
        let expectedStockNames: Set<String>
    }

    private let manufacturerMembershipCases: [ManufacturerMembershipCase] = [
        ManufacturerMembershipCase(
            manufacturer: "ILFORD / HARMAN", expectedCount: 14,
            expectedStockNames: [
                "Pan F Plus", "FP4 Plus", "Delta 100", "Delta 400", "Delta 3200",
                "HP5 Plus", "XP2 Super", "SFX 200", "Ortho Plus",
                "Kentmere 100", "Kentmere 200", "Kentmere 400",
                "Phoenix 200", "Phoenix II",
            ]),
        ManufacturerMembershipCase(
            manufacturer: "Kodak", expectedCount: 9,
            expectedStockNames: [
                "Tri-X 400", "T-MAX 100", "T-MAX 400",
                "Ektar 100", "Portra 160", "Portra 400",
                "Gold 200", "Ultra Max 400", "Ektachrome E100",
            ]),
        ManufacturerMembershipCase(
            manufacturer: "Fujifilm", expectedCount: 4,
            expectedStockNames: ["Acros II", "Velvia 50", "Velvia 100", "Provia 100F"]),
        ManufacturerMembershipCase(
            manufacturer: "FOMA BOHEMIA", expectedCount: 3,
            expectedStockNames: ["Fomapan 100 Classic", "Fomapan 200 Creative", "Fomapan 400 Action"]),
        ManufacturerMembershipCase(
            manufacturer: "Rollei", expectedCount: 7,
            expectedStockNames: ["RPX 25", "RPX 100", "RPX 400", "ORTHO 25 plus", "RETRO 80S", "RETRO 400S", "SUPERPAN 200"]),
        ManufacturerMembershipCase(
            manufacturer: "ADOX", expectedCount: 2,
            expectedStockNames: ["CHS 100 II", "CMS 20 II"]),
        ManufacturerMembershipCase(
            manufacturer: "BERGGER", expectedCount: 1,
            expectedStockNames: ["Pancro 400"]),
    ]

    /// Each manufacturer family contributes exactly its expected member
    /// set to the launch catalog. The manufacturer and its stock names
    /// are case data so no film or brand identity sits in the test name.
    func testLaunchCatalogContainsExpectedProfilesPerManufacturer() {
        for c in manufacturerMembershipCases {
            let films = LaunchPresetFilmCatalogV2.films.filter { $0.manufacturer == c.manufacturer }
            XCTAssertEqual(films.count, c.expectedCount, "\(c.manufacturer): launch catalog member count.")
            XCTAssertEqual(
                Set(films.map(\.canonicalStockName)),
                c.expectedStockNames,
                "\(c.manufacturer): launch catalog membership."
            )
        }
    }

    /// The no-source-range bare power-law family ships every entry as an
    /// exponent-formula profile that preserves its published
    /// no-correction boundary in the formula. Most of the family states
    /// an inclusive 1 s boundary; Pan F Plus, FP4 Plus, Delta 400, and
    /// HP5 Plus publish "no adjustment between 1/2 sec and 1/10,000 sec"
    /// instead, so those four carry 0.5 s (PTIMER-200 follow-up).
    func testBarePowerLawCatalogEntriesPreserveOneSecondNoCorrectionBoundary() throws {
        let halfSecondBoundaryFilms: Set<String> = ["Pan F Plus", "FP4 Plus", "Delta 400", "HP5 Plus"]
        let films = LaunchPresetFilmCatalogV2.films.filter { $0.manufacturer == "ILFORD / HARMAN" }
        XCTAssertFalse(films.isEmpty, "Bare power-law family must have catalog members.")
        for film in films {
            let profile = try XCTUnwrap(film.profiles.first)
            let formulaRule = try XCTUnwrap(
                profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                    guard case let .formula(formulaRule) = rule else { return nil }
                    return formulaRule
                }.first,
                "\(film.canonicalStockName): bare power-law family must ship as exponent-formula profiles."
            )
            let expectedThreshold: Double = halfSecondBoundaryFilms.contains(film.canonicalStockName) ? 0.5 : 1
            XCTAssertEqual(
                formulaRule.formula.noCorrectionThroughSeconds,
                expectedThreshold,
                accuracy: 1e-9,
                "\(film.canonicalStockName): must preserve its published no-correction boundary in the formula."
            )
        }
    }

    func testLaunchCatalogPreservesBarePowerLawFormulaExponents() throws {
        let expected: [String: Double] = [
            "Pan F Plus": 1.33,
            "FP4 Plus": 1.26,
            "Delta 100": 1.26,
            "Delta 400": 1.41,
            "Delta 3200": 1.33,
            "HP5 Plus": 1.31,
            "XP2 Super": 1.31,
            "SFX 200": 1.43,
            "Ortho Plus": 1.25,
            "Kentmere 100": 1.26,
            "Kentmere 200": 1.26,
            "Kentmere 400": 1.30,
            "Phoenix 200": 1.31,
            "Phoenix II": 1.31,
        ]

        for (canonicalName, exponent) in expected {
            let film = try XCTUnwrap(
                LaunchPresetFilmCatalogV2.films.first { $0.canonicalStockName == canonicalName },
                "Missing ILFORD/HARMAN film '\(canonicalName)'."
            )
            let formulaRule = try XCTUnwrap(formulaRule(in: film), "Missing formula rule for \(canonicalName).")
            XCTAssertEqual(formulaRule.formula.exponent, exponent, accuracy: 0.001)
        }
    }

    // MARK: - Exclusions

    func testLaunchCatalogExcludesNonLaunchReadyFilms() {
        let canonical = Set(LaunchPresetFilmCatalogV2.films.map(\.canonicalStockName))
        let manufacturers = Set(LaunchPresetFilmCatalogV2.films.compactMap(\.manufacturer))

        // Kodak Motion Picture Film
        for stock in ["Vision3 50D", "Vision3 250D", "Vision3 200T", "Vision3 500T", "Double-X", "Ektachrome 100D"] {
            XCTAssertFalse(canonical.contains(stock), "Kodak motion picture film '\(stock)' must not ship in the launch catalog.")
        }

        // Deferred / weak-source manufacturers (BERGGER shipped as a
        // launch-ready manufacturer in PTIMER-200 and is no longer excluded)
        for excluded in ["AgfaPhoto", "ORWO", "Film Ferrania"] {
            XCTAssertFalse(manufacturers.contains(excluded), "'\(excluded)' is not launch-ready and must not ship.")
        }

        // Archival-only Kodak entries
        for stock in ["Ektachrome E100G", "Ektachrome E100GX", "Plus-X", "Verichrome Pan", "Kodachrome"] {
            XCTAssertFalse(canonical.contains(stock), "Archival entry '\(stock)' must not ship in the launch catalog.")
        }

        // Non-launch-ready Rollei / FOMA / ADOX members
        for stock in [
            "INFRARED", "PAUL & REINHOLD", "BLACKBIRD", "CROSSBIRD", "REDBIRD",
            "Fomapan R100", "Fomapan Cine 100", "Fomapan Cine 400", "FOMA Cine Ortho 400",
            "HR-50", "Scala 50",
        ] {
            XCTAssertFalse(canonical.contains(stock), "Non-launch-ready stock '\(stock)' must not ship in the launch catalog.")
        }
    }

    func testLaunchCatalogDoesNotDuplicateFilmOrProfileIdentifiers() {
        let filmIDs = LaunchPresetFilmCatalogV2.films.map(\.id)
        let profileIDs = LaunchPresetFilmCatalogV2.films.flatMap { film in film.profiles.map(\.id) }

        XCTAssertEqual(filmIDs.count, Set(filmIDs).count)
        XCTAssertEqual(profileIDs.count, Set(profileIDs).count)
    }

    func testLaunchCatalogDoesNotShipUnofficialPracticalProfileAsPrimary() throws {
        let portra400 = try XCTUnwrap(
            LaunchPresetFilmCatalogV2.films.first(where: { $0.id == "kodak-portra-400" }),
            "Portra 400 must remain in the launch catalog."
        )
        XCTAssertEqual(portra400.profiles.count, 1)
        let profile = portra400.profiles[0]
        XCTAssertEqual(profile.source.authority, .official)
        XCTAssertEqual(profile.source.kind, .manufacturerPublished)
        XCTAssertFalse(profile.id.contains("unofficial"), "Portra 400 primary profile must not be the unofficial practical approximation.")

        for rule in profile.rules {
            if case let .formula(formulaRule) = rule {
                XCTAssertNotEqual(
                    formulaRule.formula.exponent,
                    1.34,
                    accuracy: 0.0001,
                    "Unofficial T_c = T_m^1.34 must not appear as Portra 400's official primary profile."
                )
            }
        }
    }

    func testRetro400SShipsPromotedUnofficialPracticalPrimary() throws {
        let retro = try XCTUnwrap(film(named: "RETRO 400S"))
        XCTAssertEqual(retro.id, "rollei-retro-400s")
        XCTAssertEqual(retro.iso, 400)

        let profile = try XCTUnwrap(retro.profiles.first)
        XCTAssertEqual(profile.id, "rollei-retro-400s-unofficial-practical")
        XCTAssertEqual(profile.source.kind, .thirdPartyPublication)
        XCTAssertEqual(profile.source.authority, .unofficial)
        XCTAssertTrue(profile.source.publisher.contains("Lafitte"))
        XCTAssertEqual(profile.modelBasis?.sourceModel, .practicalCommunityGuidance)
        XCTAssertEqual(profile.modelBasis?.calculationModel, .guardedFormula)

        let rule = try XCTUnwrap(formulaRule(in: retro))
        XCTAssertEqual(rule.formula.exponent, 1.62, accuracy: 0.000001)
        XCTAssertEqual(rule.formula.noCorrectionThroughSeconds, 1, accuracy: 0.000001)
        XCTAssertEqual(rule.formula.sourceRangeThroughSeconds ?? .nan, 15, accuracy: 0.000001)
    }

    func testRetro400SFormulaMatchesPublishedPracticalAnchorsApproximately() throws {
        let retro = try XCTUnwrap(film(named: "RETRO 400S"))
        let profile = retro.profiles[0]
        let evaluator = ReciprocityCalculationPolicyEvaluator()

        let threshold = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)
        guard case let .quantified(thresholdPayload) = threshold else {
            return XCTFail("RETRO 400S at 1 sec must remain no-correction, got \(threshold).")
        }
        XCTAssertEqual(thresholdPayload.correctedExposureSeconds, 1, accuracy: 0.000001)

        for sample in [(5.0, 13.5), (10.0, 41.0), (15.0, 80.0)] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: sample.0)
            guard case let .quantified(payload) = result else {
                return XCTFail("RETRO 400S at \(sample.0) sec must produce a quantified practical result, got \(result).")
            }
            XCTAssertEqual(payload.correctedExposureSeconds, sample.1, accuracy: 0.7)
        }
    }

    // MARK: - Source provenance preservation

    func testLaunchCatalogPreservesPublisherAndCitationsForBatchExemplars() throws {
        for exemplar in SourceExemplarExpectation.batchExemplars {
            let film = try XCTUnwrap(
                LaunchPresetFilmCatalogV2.films.first(where: { $0.canonicalStockName == exemplar.canonical }),
                "Missing exemplar film '\(exemplar.canonical)'."
            )
            let source = film.profiles[0].source
            XCTAssertTrue(
                source.publisher.localizedCaseInsensitiveContains(exemplar.publisherFragment),
                "\(exemplar.canonical) publisher '\(source.publisher)' should contain '\(exemplar.publisherFragment)'."
            )
            if let citationContains = exemplar.citationContains {
                let combined = [source.citation, source.title].compactMap { $0 }.joined(separator: " | ")
                XCTAssertTrue(
                    combined.contains(citationContains),
                    "\(exemplar.canonical) citation/title '\(combined)' should contain '\(citationContains)'."
                )
            }
        }
    }

    // MARK: - Representative behavior smoke tests

    func testBarePowerLawProfileEvaluatesPastThreshold() throws {
        let hp5 = try XCTUnwrap(film(named: "HP5 Plus"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: hp5.profiles[0], meteredExposureSeconds: 4)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, pow(4.0, 1.31), accuracy: 0.0001)
    }

    func testBarePowerLawProfileReturnsNoCorrectionAtThreshold() throws {
        let hp5 = try XCTUnwrap(film(named: "HP5 Plus"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: hp5.profiles[0], meteredExposureSeconds: 0.5)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified threshold result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(payload.correctedExposureSeconds, 0.5, accuracy: 0.000001)
    }

    func testTableProfileQuantifiesInsidePublishedRange() throws {
        // PTIMER-168: T-MAX 100 is table-based; inputs inside the
        // source-backed long-exposure range stay quantified with
        // basis = .tableLogLogDerived, interpolated in log-log space
        // between the published 1 sec → 1.2599 sec anchor and the
        // published 10 sec → 15 sec anchor. (noCorrectionThroughSeconds = 0.1)
        let tmax100 = try XCTUnwrap(film(named: "T-MAX 100"))
        let evaluator = ReciprocityCalculationPolicyEvaluator()

        let result = evaluator.evaluate(profile: tmax100.profiles[0], meteredExposureSeconds: 4)
        guard case let .quantified(payload) = result else {
            return XCTFail("T-MAX 100 at 4 sec must produce a quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .tableLogLogDerived)
        // Log-log interpolation between the 1 s → 1.2599 s anchor and the
        // 10 s → 15 s anchor predicts ≈ 5.60 sec at metered = 4 sec.
        XCTAssertEqual(payload.correctedExposureSeconds, 5.60, accuracy: 0.1)
    }

    func testTableProfilesPreserveNoCorrectionThresholdBand() throws {
        // Every Kodak B/W table profile must keep its published
        // no-correction threshold band intact: inside the band the
        // result stays quantified with
        // basis = .officialThresholdNoCorrection and corrected =
        // metered.
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        for stock in ["Tri-X 400", "T-MAX 100", "T-MAX 400"] {
            let film = try XCTUnwrap(self.film(named: stock))
            let thresholdMetered: Double
            switch stock {
            case "T-MAX 100":
                thresholdMetered = 0.05   // band ends at 0.1 s
            case "Tri-X 400":
                thresholdMetered = 0.05   // band ends at 0.1 s (Kodak E-31 graph)
            default:
                thresholdMetered = 0.05   // T-MAX 400 band ends at 0.1 s
            }
            let thresholdResult = evaluator.evaluate(
                profile: film.profiles[0],
                meteredExposureSeconds: thresholdMetered
            )
            guard case let .quantified(thresholdPayload) = thresholdResult else {
                return XCTFail("\(stock) at \(thresholdMetered) sec must remain quantified inside the no-correction band, got \(thresholdResult).")
            }
            XCTAssertEqual(thresholdPayload.metadata.basis, .officialThresholdNoCorrection)
            XCTAssertEqual(thresholdPayload.correctedExposureSeconds, thresholdMetered, accuracy: 1e-6)
        }
    }

    func testTableProfileContinuesBeyondPublishedSourceRangeAsUnsupportedNumeric() throws {
        // PTIMER-168: Tri-X 400 now uses official table interpolation.
        // Inputs above the published 100 sec upper anchor extrapolate the
        // last table segment as a numeric continuation outside the
        // published source range (basis = .unsupportedOutOfPolicyRange
        // with a non-nil corrected exposure).
        let trix = try XCTUnwrap(film(named: "Tri-X 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: trix.profiles[0], meteredExposureSeconds: 1500)

        guard case let .unsupported(payload) = result else {
            return XCTFail("Expected unsupported (table-derived prediction outside the source range) result past Tri-X 400's published range, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNotNil(payload.correctedExposureSeconds)
    }

    func testTableProfileReproducesPublished1SecondRow() throws {
        // PTIMER-168: Tri-X 400 is table-based; the published 1 sec row
        // (+1 stop, corrected 2 sec) is a table anchor, reproduced
        // exactly by the log-log table model.
        let trix = try XCTUnwrap(film(named: "Tri-X 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: trix.profiles[0], meteredExposureSeconds: 1)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified table result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .tableLogLogDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, 2, accuracy: 1e-4)
    }

    func testLimitedGuidanceProfileReturnsNoQuantifiedPredictionBeyondThreshold() throws {
        let portra = try XCTUnwrap(film(named: "Portra 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: portra.profiles[0], meteredExposureSeconds: 30)

        guard case let .limitedGuidance(payload) = result else {
            return XCTFail("Expected limited-guidance result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .limitedGuidanceNoQuantifiedPrediction)
    }

    func testLimitedGuidanceProfileNoCorrectionInOfficialRange() throws {
        let portra = try XCTUnwrap(film(named: "Portra 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: portra.profiles[0], meteredExposureSeconds: 0.5)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified threshold result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(payload.correctedExposureSeconds, 0.5, accuracy: 0.000001)
    }

    /// PTIMER-160 sets Velvia 50's `sourceRangeThroughSeconds` to
    /// the 32 s last-quantified anchor; the 64 s "Not recommended"
    /// row is a published warning marker and is NOT part of the
    /// source-backed range. Inputs strictly above 32 s become
    /// beyond-source-range with a numeric formula-derived
    /// continuation; the 80 s sample exercises that path.
    func testConvertedFormulaProfileAboveSourceRangeIsBeyondSourceWithFormulaPrediction() throws {
        let velvia = try XCTUnwrap(film(named: "Velvia 50"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: velvia.profiles[0], meteredExposureSeconds: 80)

        guard case let .unsupported(payload) = result else {
            return XCTFail("Expected unsupported beyond-source result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNotNil(payload.correctedExposureSeconds)
    }

    func testTableProfileReproducesPublishedMultiplierRowExactly() throws {
        // PTIMER-159: Fomapan 100 Classic is the official log-log table
        // model. Interpolation passes through the published anchors, so
        // the 1 sec row reproduces the published 2 sec corrected time
        // exactly (no fitting error).
        let fomapan = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: fomapan.profiles[0], meteredExposureSeconds: 1)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified table result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .tableLogLogDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, 2, accuracy: 1e-4)
    }

    func testGuardedFormulaRangeRowsArePreservedAsSourceEvidenceNotesRatherThanInvented() throws {
        let retro = try XCTUnwrap(film(named: "RETRO 80S"))
        let profile = retro.profiles[0]

        // After PTIMER-138 the published rows live as source
        // evidence, not as table entries — but the range-valued
        // 1 sec row must still preserve the "1 to 2 sec" range as
        // a note rather than being flattened into a single value.
        let oneSecondRow = profile.sourceEvidence.first { row in
            if case let .exactSeconds(value) = row.meteredExposure {
                return abs(value - 1) < 0.000001
            }
            return false
        }
        let row = try XCTUnwrap(oneSecondRow, "Expected RETRO 80S to keep the 1 sec source row as evidence even when the published corrected value is a range.")

        let hasQuantifiedExposure = row.adjustments.contains { adjustment in
            if case let .exposure(exposure) = adjustment {
                if case .correctedTime = exposure { return true }
                if case .stopDelta = exposure { return true }
                if case .multiplier = exposure { return true }
            }
            return false
        }
        XCTAssertFalse(
            hasQuantifiedExposure,
            "Range-valued source rows must not be flattened into a single corrected exposure value, even after formula conversion."
        )

        let preservesNote = row.adjustments.contains { adjustment in
            if case let .note(note) = adjustment {
                return note.text.contains("1 to 2 sec")
            }
            return false
        }
        XCTAssertTrue(preservesNote, "Range source value '1 to 2 sec' must be preserved as a note adjustment in source evidence.")
    }

    func testLimitedGuidanceProfilePreservesFiltrationGuidance() throws {
        let e100 = try XCTUnwrap(film(named: "Ektachrome E100"))
        let limitedGuidanceRule = e100.profiles[0].rules.compactMap { rule -> LimitedGuidanceReciprocityRule? in
            if case let .limitedGuidance(rule) = rule { return rule }
            return nil
        }.first
        let rule = try XCTUnwrap(
            limitedGuidanceRule,
            "Ektachrome E100 should carry a limited-guidance rule for the 120 sec filtration guidance."
        )

        let preservesFiltration = rule.adjustments.contains { adjustment in
            if case let .colorFilter(filter) = adjustment {
                return filter.filterName == "CC10R"
            }
            return false
        }
        XCTAssertTrue(
            preservesFiltration,
            "Ektachrome E100 limited-guidance rule must preserve the published CC10R filtration guidance."
        )
    }

    // MARK: - Compact reference info below the graph

    /// Official formula/table profiles without published `sourceEvidence`
    /// (Delta 100 here; the bare power-law family broadly) never surfaced
    /// their no-correction boundary as readable text -- only via the
    /// graph band color. A minimal "Source reference" section now always
    /// carries this boundary, placed directly below the graph/legend --
    /// the same conceptual spot table-model films already use -- read
    /// straight from the same fields the calculation already uses.
    @MainActor
    func testBareFormulaProfileShowsCompactNoCorrectionBoundary() throws {
        let displayState = try FormulaProfileTestSupport.makeDisplayState(film: "Delta 100", meteredExposureSeconds: 8)
        let sourceReference = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Source reference" }))

        let value = try XCTUnwrap(sourceReference.rows.first?.value)
        XCTAssertTrue(value.contains("No correction range"), "Delta 100: got \(value)")
        XCTAssertFalse(value.contains("Source data through"), "Delta 100 has no bounded source range.")
    }

    /// A profile that already publishes `sourceEvidence` (T-MAX 100)
    /// keeps its existing elaborate "Source reference" block unchanged --
    /// it never goes through the new no-evidence fallback.
    @MainActor
    func testTableProfileKeepsElaborateSourceReferenceUnchanged() throws {
        let displayState = try FormulaProfileTestSupport.makeDisplayState(film: "T-MAX 100", meteredExposureSeconds: 10)
        let sourceReference = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Source reference" }))
        XCTAssertTrue(sourceReference.rows.count == 1, "T-MAX 100 keeps its single reference block row.")
        let value = try XCTUnwrap(sourceReference.rows.first?.value)
        XCTAssertTrue(value.contains("No correction range"), "T-MAX 100: got \(value)")
    }

    // MARK: - Compact/elaborate source reference for the five new films

    /// Pancro 400 publishes `sourceEvidence`, so it keeps its existing
    /// elaborate "Source reference" block (anchors + the no-correction
    /// row) unchanged -- it never goes through the compact no-evidence
    /// fallback.
    @MainActor
    func testPancro400KeepsElaborateSourceReference() throws {
        let displayState = try FormulaProfileTestSupport.makeDisplayState(film: "Pancro 400", meteredExposureSeconds: 10)
        let sourceReference = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Source reference" }))
        let value = try XCTUnwrap(sourceReference.rows.first?.value)
        XCTAssertTrue(value.contains("<= 0.5s"), "Pancro 400: got \(value)")
        XCTAssertTrue(value.contains("No correction range"))
    }

    /// Phoenix 200 and Phoenix II have no published `sourceEvidence`, so
    /// they exercise the compact no-evidence fallback for their published
    /// 1-second no-correction threshold.
    @MainActor
    func testPhoenixFilmsShowCompactOneSecondNoCorrectionBoundary() throws {
        for filmName in ["Phoenix 200", "Phoenix II"] {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: filmName, meteredExposureSeconds: 10)
            let sourceReference = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(filmName): must have a Source reference section."
            )
            let value = try XCTUnwrap(sourceReference.rows.first?.value, "\(filmName): must show a compact no-correction row.")
            XCTAssertTrue(value.contains("<= 1s") || value.contains("<= 1.0s"), "\(filmName): no-correction boundary must read <= 1s; got \(value)")
        }
    }

    // MARK: - Source-reference consistency (PTIMER-200 follow-up)

    /// Pancro 400's official table cannot use `noCorrectionThroughSeconds
    /// = 1` (the schema requires the boundary strictly below the first
    /// anchor at 1 sec), so the catalog keeps the calculation-safe 0.5 sec
    /// guard and instead surfaces the true published wording ("no
    /// correction below 1 sec") as a `sourceNote`, per the existing
    /// Sources-section mechanism (already used by SFX 200).
    func testPancro400CalculationGuardStaysAtHalfSecondWithExplanatorySourceNote() throws {
        let pancro = try XCTUnwrap(film(named: "Pancro 400"))
        let profile = pancro.profiles[0]

        XCTAssertEqual(profile.source.authority, .official)
        let sourceNote = try XCTUnwrap(profile.sourceNote, "Pancro 400 must explain the calculation-guard vs source-wording gap.")
        XCTAssertTrue(sourceNote.contains("no correction below 1 sec"), "Pancro 400 sourceNote must state the true published boundary.")
        XCTAssertTrue(sourceNote.contains("1/2 sec"), "Pancro 400 sourceNote must explain the calculation guard used by the app.")

        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let atGuard = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
        guard case let .quantified(atGuardPayload) = atGuard else {
            return XCTFail("Pancro 400 @ 0.5s must be quantified no-correction, got \(atGuard).")
        }
        XCTAssertEqual(atGuardPayload.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(atGuardPayload.correctedExposureSeconds, 0.5, accuracy: 1e-6)

        let atFirstAnchor = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)
        guard case let .quantified(anchorPayload) = atFirstAnchor else {
            return XCTFail("Pancro 400 @ 1s must be quantified table-derived, got \(atFirstAnchor).")
        }
        XCTAssertEqual(anchorPayload.metadata.basis, .tableLogLogDerived, "Pancro 400 @ 1s must be corrected (+1/2 stop), not treated as no correction.")
        XCTAssertEqual(anchorPayload.correctedExposureSeconds, 1.4142136, accuracy: 1e-4)
    }

    /// ILFORD's sheet for Delta 3200 is internally inconsistent (states
    /// "no adjustment through 1/2 sec" then describes correction only for
    /// exposures "longer than 1 sec"). The catalog keeps the existing 1 s
    /// calculation boundary and surfaces the ambiguity via `sourceNote`
    /// rather than silently picking a side.
    func testDelta3200SurfacesSourceWordingAmbiguityNote() throws {
        let delta3200 = try XCTUnwrap(film(named: "Delta 3200"))
        let profile = delta3200.profiles[0]

        let sourceNote = try XCTUnwrap(profile.sourceNote, "Delta 3200 must flag the official sheet's inconsistent threshold wording.")
        XCTAssertTrue(sourceNote.contains("inconsistent"), "Delta 3200 sourceNote must call out the wording inconsistency.")
        XCTAssertTrue(sourceNote.contains("1/2 sec") && sourceNote.contains("1 sec"), "Delta 3200 sourceNote must cite both boundaries the sheet mentions.")

        let formulaRule = try XCTUnwrap(formulaRule(in: delta3200))
        XCTAssertEqual(
            formulaRule.formula.noCorrectionThroughSeconds,
            1,
            accuracy: 1e-9,
            "Delta 3200's calculation boundary must stay unchanged pending product clarification."
        )
    }

    /// FP4 Plus has no published `sourceEvidence`, so its corrected 1/2 sec
    /// no-correction boundary surfaces through the compact fallback.
    @MainActor
    func testFP4PlusShowsCompactHalfSecondNoCorrectionBoundary() throws {
        let displayState = try FormulaProfileTestSupport.makeDisplayState(film: "FP4 Plus", meteredExposureSeconds: 8)
        let sourceReference = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Source reference" }))

        let value = try XCTUnwrap(sourceReference.rows.first?.value)
        XCTAssertTrue(value.contains("<= 0.5s"), "FP4 Plus: got \(value)")
        XCTAssertTrue(value.contains("No correction range"))
        XCTAssertFalse(value.contains("Source data through"), "FP4 Plus has no bounded source range.")
    }

    /// Delta 3200 has no published `sourceEvidence`, so it exercises the
    /// compact fallback for its unchanged 1 sec boundary, alongside its
    /// ambiguity `sourceNote` in the Sources section.
    @MainActor
    func testDelta3200ShowsCompactBoundaryAndAmbiguityNote() throws {
        let displayState = try FormulaProfileTestSupport.makeDisplayState(film: "Delta 3200", meteredExposureSeconds: 10)
        let sourceReference = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Source reference" }))
        let value = try XCTUnwrap(sourceReference.rows.first?.value)
        XCTAssertTrue(value.contains("<= 1s") || value.contains("<= 1.0s"), "Delta 3200: got \(value)")

        let sources = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Sources" }))
        XCTAssertTrue(
            sources.rows.contains { $0.value.contains("inconsistent") },
            "Delta 3200's ambiguity note must still render in Sources."
        )
    }

    /// ILFORD's official SFX 200 datasheet has no reciprocity section at
    /// all (confirmed against the live PDF: no formula, table, or graph).
    /// The catalog's exponent has no verified official origin, so SFX 200
    /// must not be presented as official quantified reciprocity guidance:
    /// it is hidden from `userSelectableFilms` (no source-page link) while
    /// staying in the full catalog, schema-valid, for later restoration if
    /// a verified source is ever found.
    func testSFX200IsHiddenFromSelectionRatherThanPresentedAsFabricatedOfficialData() throws {
        let sfx200 = try XCTUnwrap(film(named: "SFX 200"))
        let profile = sfx200.profiles[0]

        XCTAssertFalse(
            LaunchPresetFilmCatalogV2.userSelectableFilms.contains { $0.id == sfx200.id },
            "SFX 200 must not be user-selectable without a verified official reciprocity source."
        )
        XCTAssertTrue(
            LaunchPresetFilmCatalogV2.films.contains { $0.id == sfx200.id },
            "The full catalog must keep SFX 200 so the data is available for restoration."
        )
        XCTAssertNil(profile.sourcePageUrl, "SFX 200 must have no source-page link, which is what hides it from selection.")

        let sourceNote = try XCTUnwrap(profile.sourceNote, "SFX 200 must explain why it is hidden.")
        XCTAssertTrue(sourceNote.contains("no reciprocity formula, table, or graph"), "SFX 200 sourceNote must state the official sheet has no reciprocity data.")
        XCTAssertTrue(sourceNote.contains("no verified official source"), "SFX 200 sourceNote must not imply the exponent is manufacturer-published.")
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalogV2.films.first { $0.canonicalStockName == canonicalStockName }
    }

    private func formulaRule(in film: FilmIdentity) -> FormulaReciprocityRule? {
        for rule in film.profiles.first?.rules ?? [] {
            if case let .formula(formulaRule) = rule {
                return formulaRule
            }
        }
        return nil
    }

}

/// Static expectations for the bundled launch catalog. Lives at file
/// scope so the test class body stays under the SwiftLint
/// `type_body_length` threshold.
private enum LaunchCatalogExpectations {
    static let scopeCount = 40

    static let canonicalStockOrder: [String] = [
        // Batch 1 — ILFORD / HARMAN
        "Pan F Plus", "FP4 Plus", "Delta 100", "Delta 400", "Delta 3200",
        "HP5 Plus", "XP2 Super", "SFX 200", "Ortho Plus",
        "Kentmere 100", "Kentmere 200", "Kentmere 400",
        "Phoenix 200", "Phoenix II",
        // Batch 2 — Kodak
        "Tri-X 400", "T-MAX 100", "T-MAX 400",
        "Ektar 100", "Portra 160", "Portra 400",
        "Gold 200", "Ultra Max 400", "Ektachrome E100",
        // Batch 3 — Fujifilm + FOMA
        "Acros II", "Velvia 50", "Velvia 100", "Provia 100F",
        "Fomapan 100 Classic", "Fomapan 200 Creative", "Fomapan 400 Action",
        // Batch 4 — Rollei + ADOX
        "RPX 25", "RPX 100", "RPX 400", "ORTHO 25 plus",
        "RETRO 80S", "RETRO 400S", "SUPERPAN 200",
        "CHS 100 II", "CMS 20 II",
        // PTIMER-200 — BERGGER
        "Pancro 400",
    ]
}

/// Source-provenance exemplar pinned by
/// `testLaunchCatalogPreservesPublisherAndCitationsForBatchExemplars`.
/// Replaces a 3-tuple to satisfy SwiftLint's `large_tuple` rule.
private struct SourceExemplarExpectation {
    let canonical: String
    let publisherFragment: String
    let citationContains: String?

    static let batchExemplars: [SourceExemplarExpectation] = [
        .init(canonical: "HP5 Plus", publisherFragment: "Ilford", citationContains: "Technical information sheet"),
        .init(canonical: "Tri-X 400", publisherFragment: "Kodak", citationContains: "F-4017"),
        .init(canonical: "T-MAX 100", publisherFragment: "Kodak", citationContains: "F-4016"),
        .init(canonical: "Portra 400", publisherFragment: "Kodak", citationContains: "E-4050"),
        .init(canonical: "Velvia 50", publisherFragment: "Fujifilm", citationContains: nil),
        .init(canonical: "Acros II", publisherFragment: "Fujifilm", citationContains: nil),
        .init(canonical: "Fomapan 100 Classic", publisherFragment: "FOMA", citationContains: nil),
        .init(canonical: "RPX 25", publisherFragment: "Rollei", citationContains: "RPX 25 data sheet"),
        .init(canonical: "RPX 100", publisherFragment: "Rollei", citationContains: "RPX 100 data sheet"),
        .init(canonical: "ORTHO 25 plus", publisherFragment: "Rollei", citationContains: "ORTHO 25 plus data sheet"),
        .init(canonical: "RETRO 400S", publisherFragment: "Lafitte", citationContains: "Rollei Retro 400S"),
        .init(canonical: "CHS 100 II", publisherFragment: "ADOX", citationContains: nil),
        .init(canonical: "Ektachrome E100", publisherFragment: "Kodak", citationContains: "E-4000"),
        .init(canonical: "Phoenix 200", publisherFragment: "HARMAN", citationContains: "Sep 2024"),
        .init(canonical: "Phoenix II", publisherFragment: "HARMAN", citationContains: "Jul 2025"),
        .init(canonical: "Pancro 400", publisherFragment: "Bergger", citationContains: "Jan 2017"),
    ]
}
