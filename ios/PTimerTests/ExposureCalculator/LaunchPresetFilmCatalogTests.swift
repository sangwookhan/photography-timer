import Foundation
import PTimerCore
import XCTest
@testable import PTimer

final class LaunchPresetFilmCatalogTests: XCTestCase {

    // MARK: - Bundle loading

    func testBundledLaunchPresetFilmCatalogLoadsSuccessfully() throws {
        let films = try LaunchPresetFilmCatalogLoader().loadBundledCatalog()
        XCTAssertEqual(films.count, LaunchCatalogExpectations.scopeCount)
        XCTAssertEqual(films.map(\.canonicalStockName), LaunchCatalogExpectations.canonicalStockOrder)
    }

    func testBundledLaunchPresetFilmCatalogPreservesExpectedSelectorOrdering() {
        XCTAssertEqual(LaunchPresetFilmCatalog.films.count, LaunchCatalogExpectations.scopeCount)
        XCTAssertEqual(
            LaunchPresetFilmCatalog.films.map(\.canonicalStockName),
            LaunchCatalogExpectations.canonicalStockOrder
        )
    }

    // MARK: - PTIMER-86 launch-policy invariants

    func testLaunchPresetFilmCatalogRespectsPTIMER86LaunchPolicyConstraints() {
        XCTAssertFalse(LaunchPresetFilmCatalog.films.isEmpty)

        for film in LaunchPresetFilmCatalog.films {
            XCTAssertEqual(film.kind, .preset)
            XCTAssertEqual(film.productionStatus, .current)
            XCTAssertEqual(film.profiles.count, 1, "Launch flow should use one primary profile per film identity.")
            XCTAssertFalse(film.canonicalStockName.isEmpty)

            let profile = film.profiles[0]
            XCTAssertEqual(profile.source.kind, .manufacturerPublished)
            XCTAssertEqual(profile.source.authority, .official)
            XCTAssertEqual(profile.source.confidence, .high)
            XCTAssertFalse(profile.source.publisher.isEmpty)
            XCTAssertNil(film.userMetadata)
            XCTAssertNil(profile.userMetadata)
        }
    }

    // MARK: - Manufacturer-batch completeness

    func testLaunchCatalogContainsAllILFORDHarmanFormulaProfiles() throws {
        let films = LaunchPresetFilmCatalog.films.filter { $0.manufacturer == "ILFORD / HARMAN" }
        XCTAssertEqual(films.count, 12)
        XCTAssertEqual(
            Set(films.map(\.canonicalStockName)),
            Set([
                "Pan F Plus", "FP4 Plus", "Delta 100", "Delta 400", "Delta 3200",
                "HP5 Plus", "XP2 Super", "SFX 200", "Ortho Plus",
                "Kentmere 100", "Kentmere 200", "Kentmere 400",
            ])
        )

        for film in films {
            let profile = try XCTUnwrap(film.profiles.first)
            let formulaRule = try XCTUnwrap(
                profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                    guard case let .formula(formulaRule) = rule else { return nil }
                    return formulaRule
                }.first,
                "ILFORD/HARMAN films must ship as exponent-formula profiles."
            )
            XCTAssertEqual(
                formulaRule.formula.noCorrectionThroughSeconds,
                1,
                accuracy: 1e-9,
                "ILFORD/HARMAN films must preserve the 1-second no-compensation boundary in the formula."
            )
        }
    }

    func testLaunchCatalogPreservesILFORDFormulaCoefficients() throws {
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
        ]

        for (canonicalName, exponent) in expected {
            let film = try XCTUnwrap(
                LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalName },
                "Missing ILFORD/HARMAN film '\(canonicalName)'."
            )
            let formulaRule = try XCTUnwrap(formulaRule(in: film), "Missing formula rule for \(canonicalName).")
            XCTAssertEqual(formulaRule.formula.exponent, exponent, accuracy: 0.001)
        }
    }

    func testLaunchCatalogContainsAllKodakStillFilmProfiles() throws {
        let films = LaunchPresetFilmCatalog.films.filter { $0.manufacturer == "Kodak" }
        XCTAssertEqual(films.count, 9)
        XCTAssertEqual(
            Set(films.map(\.canonicalStockName)),
            Set([
                "Tri-X 400", "T-MAX 100", "T-MAX 400",
                "Ektar 100", "Portra 160", "Portra 400",
                "Gold 200", "Ultra Max 400", "Ektachrome E100",
            ])
        )
    }

    func testLaunchCatalogContainsAllFujifilmAndFomaProfiles() throws {
        let fujifilm = LaunchPresetFilmCatalog.films.filter { $0.manufacturer == "Fujifilm" }
        XCTAssertEqual(fujifilm.count, 4)
        XCTAssertEqual(
            Set(fujifilm.map(\.canonicalStockName)),
            Set(["Acros II", "Velvia 50", "Velvia 100", "Provia 100F"])
        )

        let foma = LaunchPresetFilmCatalog.films.filter { $0.manufacturer == "FOMA BOHEMIA" }
        XCTAssertEqual(foma.count, 3)
        XCTAssertEqual(
            Set(foma.map(\.canonicalStockName)),
            Set(["Fomapan 100 Classic", "Fomapan 200 Creative", "Fomapan 400 Action"])
        )
    }

    func testLaunchCatalogContainsAllRolleiAndAdoxProfiles() throws {
        let rollei = LaunchPresetFilmCatalog.films.filter { $0.manufacturer == "Rollei" }
        XCTAssertEqual(rollei.count, 4)
        XCTAssertEqual(
            Set(rollei.map(\.canonicalStockName)),
            Set(["RPX 100", "RPX 400", "RETRO 80S", "SUPERPAN 200"])
        )

        let adox = LaunchPresetFilmCatalog.films.filter { $0.manufacturer == "ADOX" }
        XCTAssertEqual(adox.count, 2)
        XCTAssertEqual(Set(adox.map(\.canonicalStockName)), Set(["CHS 100 II", "CMS 20 II"]))
    }

    // MARK: - Exclusions

    func testLaunchCatalogExcludesNonLaunchReadyFilms() {
        let canonical = Set(LaunchPresetFilmCatalog.films.map(\.canonicalStockName))
        let manufacturers = Set(LaunchPresetFilmCatalog.films.compactMap(\.manufacturer))

        // Kodak Motion Picture Film
        for stock in ["Vision3 50D", "Vision3 250D", "Vision3 200T", "Vision3 500T", "Double-X", "Ektachrome 100D"] {
            XCTAssertFalse(canonical.contains(stock), "Kodak motion picture film '\(stock)' must not ship in the launch catalog.")
        }

        // Deferred / weak-source manufacturers
        for excluded in ["AgfaPhoto", "ORWO", "Bergger", "Film Ferrania"] {
            XCTAssertFalse(manufacturers.contains(excluded), "'\(excluded)' is not launch-ready and must not ship.")
        }

        // Archival-only Kodak entries
        for stock in ["Ektachrome E100G", "Ektachrome E100GX", "Plus-X", "Verichrome Pan", "Kodachrome"] {
            XCTAssertFalse(canonical.contains(stock), "Archival entry '\(stock)' must not ship in the launch catalog.")
        }

        // Non-launch-ready Rollei / FOMA / ADOX members
        for stock in [
            "RPX 25", "RETRO 400S", "INFRARED", "ORTHO 25 plus",
            "PAUL & REINHOLD", "BLACKBIRD", "CROSSBIRD", "REDBIRD",
            "Fomapan R100", "Fomapan Cine 100", "Fomapan Cine 400", "FOMA Cine Ortho 400",
            "HR-50", "Scala 50",
        ] {
            XCTAssertFalse(canonical.contains(stock), "Non-launch-ready stock '\(stock)' must not ship in the launch catalog.")
        }
    }

    func testLaunchCatalogDoesNotShipUnofficialPortraPracticalAsPrimary() throws {
        let portra400 = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first(where: { $0.id == "kodak-portra-400" }),
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

    // MARK: - Source provenance preservation

    func testLaunchCatalogPreservesPublisherAndCitationsForBatchExemplars() throws {
        for exemplar in SourceExemplarExpectation.batchExemplars {
            let film = try XCTUnwrap(
                LaunchPresetFilmCatalog.films.first(where: { $0.canonicalStockName == exemplar.canonical }),
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

    func testILFORDFormulaProfileEvaluatesPastThreshold() throws {
        let hp5 = try XCTUnwrap(film(named: "HP5 Plus"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: hp5.profiles[0], meteredExposureSeconds: 4)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, pow(4.0, 1.31), accuracy: 0.0001)
    }

    func testILFORDFormulaProfileReturnsNoCorrectionAtThreshold() throws {
        let hp5 = try XCTUnwrap(film(named: "HP5 Plus"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: hp5.profiles[0], meteredExposureSeconds: 0.5)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified threshold result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(payload.correctedExposureSeconds, 0.5, accuracy: 0.000001)
    }

    func testKodakTMax100TableProfileQuantifiesInsidePublishedRange() throws {
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

    func testKodakBlackAndWhiteFilmsPreserveNoCorrectionThresholdBand() throws {
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

    func testKodakTriX400TableContinuesBeyondPublishedSourceRangeAsUnsupportedNumeric() throws {
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

    func testKodakTriXTableProfileReproducesPublished1SecondRow() throws {
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

    func testKodakColorNegativeLimitedGuidanceBeyondThreshold() throws {
        let portra = try XCTUnwrap(film(named: "Portra 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: portra.profiles[0], meteredExposureSeconds: 30)

        guard case let .limitedGuidance(payload) = result else {
            return XCTFail("Expected limited-guidance result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .limitedGuidanceNoQuantifiedPrediction)
    }

    func testKodakColorNegativeNoCorrectionInOfficialRange() throws {
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
    func testFujifilmAbove32SecondsIsBeyondSourceWithFormulaPrediction() throws {
        let velvia = try XCTUnwrap(film(named: "Velvia 50"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: velvia.profiles[0], meteredExposureSeconds: 80)

        guard case let .unsupported(payload) = result else {
            return XCTFail("Expected unsupported beyond-source result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNotNil(payload.correctedExposureSeconds)
    }

    func testFomapanTableReproducesPublishedMultiplierRowExactly() throws {
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

    func testRolleiRangeRowsArePreservedAsSourceEvidenceNotesRatherThanInvented() throws {
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

    func testEktachromeE100PreservesFiltrationGuidance() throws {
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

    // MARK: - Loader failure paths (existing coverage retained)

    func testLaunchPresetFilmCatalogRejectsDuplicateFilmIdentifiers() throws {
        let originalFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let duplicatedFilm = copyFilm(originalFilm)
        let duplicatedData = try encodeCatalog([originalFilm, duplicatedFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: duplicatedData)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(error, .duplicateFilmIdentifier(originalFilm.id))
        XCTAssertEqual(
            error.errorDescription,
            "Bundled launch preset film catalog contains a duplicate film identifier '\(originalFilm.id)'."
        )
    }

    func testLaunchPresetFilmCatalogRejectsInvalidCanonicalStockNames() throws {
        let originalFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let invalidFilm = copyFilm(originalFilm, canonicalStockName: "  ")
        let invalidData = try encodeCatalog([invalidFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: invalidData)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(error, .invalidCanonicalStockName(originalFilm.id))
    }

    func testLaunchPresetFilmCatalogRejectsDuplicateCanonicalStockNames() throws {
        let firstFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let secondFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.dropFirst().first)
        let duplicateNameFilm = copyFilm(secondFilm, canonicalStockName: firstFilm.canonicalStockName)
        let duplicatedData = try encodeCatalog([firstFilm, duplicateNameFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(try LaunchPresetFilmCatalogLoader().loadCatalog(from: duplicatedData))
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(error, .duplicateCanonicalStockName(firstFilm.canonicalStockName))
    }

    func testLaunchPresetFilmCatalogMissingResourceFailsSafely() {
        let error = XCTAssertThrowsErrorAndReturn(
            try LaunchPresetFilmCatalogLoader().loadBundledCatalog(
                resourceName: "MissingLaunchPresetFilmCatalog",
                bundleCandidates: [Bundle(for: Self.self)]
            )
        ) as? LaunchPresetFilmCatalogLoaderError

        XCTAssertEqual(
            error,
            .missingBundledResource(name: "MissingLaunchPresetFilmCatalog", fileExtension: "json")
        )
    }

    func testLaunchPresetFilmCatalogMalformedResourceFailsSafely() {
        let malformedData = Data("{".utf8)

        let error = XCTAssertThrowsErrorAndReturn(
            try LaunchPresetFilmCatalogLoader().loadCatalog(from: malformedData)
        ) as? LaunchPresetFilmCatalogLoaderError

        guard case .malformedResource? = error else {
            return XCTFail("Expected malformed resource error, got \(String(describing: error)).")
        }
    }

    func testLaunchPresetFilmCatalogDecodeFailureReportsMissingKeyAndCodingPath() {
        // Missing both `iso` and `profiles`. The decoder reports the first
        // required key it cannot find; the contract under test is that a
        // missing-key error includes the offending entry index in the
        // coding path so the developer can locate the bad entry.
        let invalidJSON = Data(
            """
            [
              {
                "id": "kodak-tri-x-400",
                "kind": "preset",
                "canonicalStockName": "Tri-X 400",
                "manufacturer": "Kodak",
                "brandLabel": "KODAK PROFESSIONAL TRI-X 400",
                "aliases": ["TRI-X", "TX 400"],
                "productionStatus": "current"
              }
            ]
            """.utf8
        )

        let error = XCTAssertThrowsErrorAndReturn(
            try LaunchPresetFilmCatalogLoader().loadCatalog(from: invalidJSON)
        ) as? LaunchPresetFilmCatalogLoaderError

        guard case let .malformedResource(reason)? = error else {
            return XCTFail("Expected malformed resource error, got \(String(describing: error)).")
        }

        XCTAssertTrue(reason.contains("Missing key"))
        XCTAssertTrue(reason.contains("[0]"))
    }

    func testLaunchPresetFilmCatalogValidationFailureDescriptionsNameOffendingEntry() throws {
        let firstFilm = try XCTUnwrap(LaunchPresetFilmCatalog.films.first)
        let invalidFilm = copyFilm(firstFilm, profiles: [])
        let invalidData = try encodeCatalog([invalidFilm])

        let error = try XCTUnwrap(
            XCTAssertThrowsErrorAndReturn(
                try LaunchPresetFilmCatalogLoader().loadCatalog(from: invalidData)
            ) as? LaunchPresetFilmCatalogLoaderError
        )

        XCTAssertEqual(error, .invalidPrimaryProfileCount(filmID: firstFilm.id, count: 0))
        XCTAssertEqual(
            error.errorDescription,
            "Bundled launch preset film catalog film '\(firstFilm.id)' has 0 profiles; launch scope requires exactly one primary profile."
        )
    }

    // MARK: - Helpers

    private func film(named canonicalStockName: String) -> FilmIdentity? {
        LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName }
    }

    private func formulaRule(in film: FilmIdentity) -> FormulaReciprocityRule? {
        for rule in film.profiles.first?.rules ?? [] {
            if case let .formula(formulaRule) = rule {
                return formulaRule
            }
        }
        return nil
    }

    private func encodeCatalog(_ films: [FilmIdentity]) throws -> Data {
        try JSONEncoder().encode(films)
    }

    private func copyFilm(
        _ film: FilmIdentity,
        id: String? = nil,
        canonicalStockName: String? = nil,
        kind: FilmIdentityKind? = nil,
        iso: Int? = nil,
        productionStatus: FilmProductionStatus? = nil,
        profiles: [ReciprocityProfile]? = nil
    ) -> FilmIdentity {
        FilmIdentity(
            id: id ?? film.id,
            kind: kind ?? film.kind,
            canonicalStockName: canonicalStockName ?? film.canonicalStockName,
            manufacturer: film.manufacturer,
            brandLabel: film.brandLabel,
            aliases: film.aliases,
            iso: iso ?? film.iso,
            productionStatus: productionStatus ?? film.productionStatus,
            profiles: profiles ?? film.profiles,
            userMetadata: film.userMetadata
        )
    }
}

private func XCTAssertThrowsErrorAndReturn<T>(
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

/// Static expectations for the bundled launch catalog. Lives at file
/// scope so the test class body stays under the SwiftLint
/// `type_body_length` threshold.
private enum LaunchCatalogExpectations {
    static let scopeCount = 34

    static let canonicalStockOrder: [String] = [
        // Batch 1 — ILFORD / HARMAN
        "Pan F Plus", "FP4 Plus", "Delta 100", "Delta 400", "Delta 3200",
        "HP5 Plus", "XP2 Super", "SFX 200", "Ortho Plus",
        "Kentmere 100", "Kentmere 200", "Kentmere 400",
        // Batch 2 — Kodak
        "Tri-X 400", "T-MAX 100", "T-MAX 400",
        "Ektar 100", "Portra 160", "Portra 400",
        "Gold 200", "Ultra Max 400", "Ektachrome E100",
        // Batch 3 — Fujifilm + FOMA
        "Acros II", "Velvia 50", "Velvia 100", "Provia 100F",
        "Fomapan 100 Classic", "Fomapan 200 Creative", "Fomapan 400 Action",
        // Batch 4 — Rollei + ADOX
        "RPX 100", "RPX 400", "RETRO 80S", "SUPERPAN 200",
        "CHS 100 II", "CMS 20 II",
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
        .init(canonical: "RPX 100", publisherFragment: "Rollei", citationContains: "RPX 100 data sheet"),
        .init(canonical: "CHS 100 II", publisherFragment: "ADOX", citationContains: nil),
        .init(canonical: "Ektachrome E100", publisherFragment: "Kodak", citationContains: "E-4000"),
    ]
}
