import Foundation
import XCTest
@testable import PTimer

final class LaunchPresetFilmCatalogTests: XCTestCase {

    // MARK: - Bundle loading

    func testBundledLaunchPresetFilmCatalogLoadsSuccessfully() throws {
        let films = try LaunchPresetFilmCatalogLoader().loadBundledCatalog()
        XCTAssertEqual(films.count, LaunchPresetFilmCatalogTests.expectedLaunchScopeCount)
        XCTAssertEqual(films.map(\.canonicalStockName), LaunchPresetFilmCatalogTests.expectedCanonicalStockOrder)
    }

    func testBundledLaunchPresetFilmCatalogPreservesExpectedSelectorOrdering() {
        XCTAssertEqual(LaunchPresetFilmCatalog.films.count, LaunchPresetFilmCatalogTests.expectedLaunchScopeCount)
        XCTAssertEqual(
            LaunchPresetFilmCatalog.films.map(\.canonicalStockName),
            LaunchPresetFilmCatalogTests.expectedCanonicalStockOrder
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
            XCTAssertTrue(
                profile.rules.contains { rule in
                    if case .formula = rule { return true }
                    return false
                },
                "ILFORD/HARMAN films must ship as exponent-formula profiles."
            )
            XCTAssertTrue(
                profile.rules.contains { rule in
                    if case let .threshold(threshold) = rule {
                        return threshold.noCorrectionRange.maximumSeconds == 1
                    }
                    return false
                },
                "ILFORD/HARMAN films must preserve the 1-second no-compensation threshold."
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
            XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
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
        let exemplars: [(canonical: String, publisherFragment: String, citationContains: String?)] = [
            ("HP5 Plus", "Ilford", "Technical information sheet"),
            ("Tri-X 400", "Kodak", "F-4017"),
            ("T-MAX 100", "Kodak", "F-4016"),
            ("Portra 400", "Kodak", "E-4050"),
            ("Velvia 50", "Fujifilm", nil),
            ("Acros II", "Fujifilm", nil),
            ("Fomapan 100 Classic", "FOMA", nil),
            ("RPX 100", "Rollei", "RPX 100 data sheet"),
            ("CHS 100 II", "ADOX", nil),
            ("Ektachrome E100", "Kodak", "E-4000"),
        ]

        for exemplar in exemplars {
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

    func testKodakTMax100FormulaProfileQuantifiesInsidePublishedRange() throws {
        // T-MAX 100 is now formula-based; inputs inside the source-
        // backed long-exposure range stay quantified with
        // basis = .formulaDerived and the formula curve passes near
        // Kodak's published rows.
        let tmax100 = try XCTUnwrap(film(named: "T-MAX 100"))
        let evaluator = ReciprocityCalculationPolicyEvaluator()

        let result = evaluator.evaluate(profile: tmax100.profiles[0], meteredExposureSeconds: 4)
        guard case let .quantified(payload) = result else {
            return XCTFail("T-MAX 100 at 4 sec must produce a quantified result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        // Threshold-anchored log-log fit through Kodak's published
        // 10 sec / 100 sec corrected times predicts ≈ 5.7 sec at
        // metered = 4 sec.
        XCTAssertEqual(payload.correctedExposureSeconds, 5.7, accuracy: 0.2)
    }

    func testKodakBlackAndWhiteFilmsPreserveNoCorrectionThresholdBand() throws {
        // Every Kodak B/W formula profile must keep its published
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
                thresholdMetered = 0.05
            default:
                thresholdMetered = 0.25
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

    func testKodakTriX400FormulaExtrapolatesBeyond100SecondsAsUnsupportedNumeric() throws {
        // Tri-X 400 is now formula-based; inputs above the published
        // 100 sec upper anchor land on the same curve as a numeric
        // continuation outside the published source range
        // (basis = .unsupportedOutOfPolicyRange with a non-nil
        // corrected exposure).
        let trix = try XCTUnwrap(film(named: "Tri-X 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: trix.profiles[0], meteredExposureSeconds: 1500)

        guard case let .unsupported(payload) = result else {
            return XCTFail("Expected unsupported (formula-extrapolated) result past Tri-X 400's published range, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNotNil(payload.correctedExposureSeconds)
    }

    func testLaunchCatalogTableAnchorsAreFamilyConsistent() throws {
        // Structural invariant guarding against the T-MAX 100 class of
        // mapping bug. A table profile whose quantified anchors disagree
        // on estimation family makes
        // ReciprocityCalculationPolicyEvaluator.Estimation.estimate return
        // nil for any bracketed metered value, silently routing
        // user-visible exposures into the unsupported branch even though
        // the source data sheet covers them. Catch that at fixture-load
        // time so future catalog edits cannot reintroduce it.
        for film in LaunchPresetFilmCatalog.films {
            for profile in film.profiles {
                for rule in profile.rules {
                    guard case let .table(table) = rule else { continue }
                    let families: Set<ReciprocityTableEstimationFamily> = Set(
                        table.entries.compactMap(estimationFamily(for:))
                    )
                    XCTAssertLessThanOrEqual(
                        families.count,
                        1,
                        "\(film.canonicalStockName): table mixes estimation families \(families). Add correctedTime (or the matching family) to every quantified row so the policy can interpolate."
                    )
                }
            }
        }
    }

    private func estimationFamily(for entry: ReciprocityTableEntry) -> ReciprocityTableEstimationFamily? {
        // Mirrors TableSelector.quantifiedPoint's family selection without
        // depending on the private type: stop-signal rows are excluded;
        // a row with correctedTime is logLog; a row with only stopDelta /
        // multiplier is stopSpace; everything else is non-quantified.
        var hasCorrectedTime = false
        var hasStopOrMultiplier = false
        var isStopSignal = false
        for adjustment in entry.adjustments {
            switch adjustment {
            case let .exposure(exposureAdjustment):
                switch exposureAdjustment {
                case .correctedTime: hasCorrectedTime = true
                case .stopDelta, .multiplier: hasStopOrMultiplier = true
                }
            case let .warning(warning) where warning.severity == .notRecommended:
                isStopSignal = true
            default:
                continue
            }
        }
        if isStopSignal { return nil }
        if hasCorrectedTime { return .logLog }
        if hasStopOrMultiplier { return .stopSpace }
        return nil
    }

    func testKodakTriXFormulaProfileTracksPublished1SecondRow() throws {
        // Tri-X 400 is now formula-based; the published 1 sec row
        // (+1 stop, corrected 2 sec) is preserved as source evidence
        // and the formula's free LSQ fit tracks it within ~0.01 stop.
        let trix = try XCTUnwrap(film(named: "Tri-X 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: trix.profiles[0], meteredExposureSeconds: 1)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified formula result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        XCTAssertEqual(payload.correctedExposureSeconds, 2, accuracy: 0.05)
    }

    func testKodakColorNegativeAdvisoryBeyondThreshold() throws {
        let portra = try XCTUnwrap(film(named: "Portra 400"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: portra.profiles[0], meteredExposureSeconds: 30)

        guard case let .advisoryOnly(payload) = result else {
            return XCTFail("Expected advisory-only result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .advisoryOnlyBeyondOfficialRange)
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

    func testFujifilmStopSignalRowReturnsUnsupported() throws {
        let velvia = try XCTUnwrap(film(named: "Velvia 50"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: velvia.profiles[0], meteredExposureSeconds: 64)

        guard case let .unsupported(payload) = result else {
            return XCTFail("Expected unsupported stop-signal result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .unsupportedOutOfPolicyRange)
    }

    func testFomapanFormulaPredictionTracksPublishedMultiplierRow() throws {
        // Fomapan 100 Classic is formula-backed; the calculation
        // path no longer returns the published 1 sec multiplier row
        // as an exact-table point. The formula is anchored to a free
        // log-log fit through the published rows so the prediction
        // sits within ~1/6 stop of the 1 sec row.
        let fomapan = try XCTUnwrap(film(named: "Fomapan 100 Classic"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: fomapan.profiles[0], meteredExposureSeconds: 1)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified formula result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .formulaDerived)
        // 2.2457 × 1^1.4515 = 2.2457; published row corrected = 2.
        XCTAssertEqual(payload.correctedExposureSeconds, 2.2457, accuracy: 0.01)
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

    func testAdoxChsTableProfileReturnsExactRow() throws {
        let chs = try XCTUnwrap(film(named: "CHS 100 II"))
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: chs.profiles[0], meteredExposureSeconds: 30)

        guard case let .quantified(payload) = result else {
            return XCTFail("Expected quantified ADOX table result, got \(result).")
        }
        XCTAssertEqual(payload.metadata.basis, .exactTablePoint)
        XCTAssertEqual(payload.correctedExposureSeconds, 120, accuracy: 0.000001)
    }

    func testEktachromeE100PreservesFiltrationGuidance() throws {
        let e100 = try XCTUnwrap(film(named: "Ektachrome E100"))
        let advisoryRule = e100.profiles[0].rules.compactMap { rule -> AdvisoryReciprocityRule? in
            if case let .advisory(advisory) = rule { return advisory }
            return nil
        }.first
        let advisory = try XCTUnwrap(advisoryRule, "Ektachrome E100 should carry an advisory rule for the 120 sec filtration guidance.")

        let preservesFiltration = advisory.adjustments.contains { adjustment in
            if case let .colorFilter(filter) = adjustment {
                return filter.filterName == "CC10R"
            }
            return false
        }
        XCTAssertTrue(preservesFiltration, "Ektachrome E100 advisory must preserve the published CC10R filtration guidance.")
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

    private static let expectedLaunchScopeCount = 34

    private static let expectedCanonicalStockOrder: [String] = [
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
