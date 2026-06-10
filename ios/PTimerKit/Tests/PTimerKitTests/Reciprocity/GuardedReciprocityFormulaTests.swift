import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-160: shared guarded reciprocity formula contract.
///
/// Locks the behavior the rest of the catalog (PTIMER-84 custom
/// profiles, PTIMER-159 Details verification UI, PTIMER-161 table-
/// converted formula refits) will depend on:
///
/// - legacy power-law profile shape (`Tc = a × Tm^p`) preserves its
///   corrected-exposure output through the migration;
/// - `noCorrectionThroughSeconds` is an inclusive identity guard;
/// - `sourceRangeThroughSeconds` is a confidence boundary, not a
///   calculation stop — the formula keeps producing a numeric value
///   past it;
/// - non-default `referenceMeteredTimeSeconds` and non-zero
///   `offsetSeconds` paths produce the documented `a × (Tm/Tref)^p + b`
///   arithmetic;
/// - failure modes surface as distinct evaluation outcomes —
///   `.invalidInput` for bad metered input, `.invalidFormula` for
///   parameter-contract violations, `.formulaOutputUnusable` for
///   non-finite / non-positive arithmetic output, and
///   `.unsafeShorteningFormula` for runs that would shorten the
///   exposure — so the policy layer can route data errors and the
///   runtime safety handoff to different presentations instead of
///   collapsing them onto a single case;
/// - the formatter renders the new model with neutral-value omission
///   for compact display.
final class GuardedReciprocityFormulaTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Legacy power-law compatibility (Tref = 1, offset = 0)

    /// Ilford-style power-law (`Tc = Tm^p`) — every neutral default
    /// applies; the formula matches the legacy `pow(metered,
    /// exponent)` arithmetic.
    func testLegacyBarePowerLawMatchesLegacyOutput() {
        let formula = ReciprocityFormula(
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        for metered in [1.5, 2.0, 5.0, 30.0, 100.0] {
            switch formula.evaluate(meteredExposureSeconds: metered) {
            case let .withinSourceRange(corrected):
                XCTAssertEqual(corrected, pow(metered, 1.31), accuracy: 1e-9)
            default:
                XCTFail("Expected withinSourceRange at \(metered) s.")
            }
        }
    }

    /// Legacy `Tc = a × Tm^p` (Kodak Tri-X style) preserves the same
    /// arithmetic — coefficient-only migration leaves the corrected
    /// exposure unchanged. Inputs strictly above the no-correction
    /// boundary keep the formula's prediction; the boundary itself is
    /// owned by `noCorrectionThroughSeconds` and is exercised by
    /// `testNoCorrectionGuardIsInclusiveAtTheBoundary`.
    func testLegacyCoefficientFormulaPreservesCorrectedExposure() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 2.013654,
            exponent: 1.3891,
            noCorrectionThroughSeconds: 1
        )
        for metered in [1.0001, 10.0, 50.0, 100.0] {
            switch formula.evaluate(meteredExposureSeconds: metered) {
            case let .withinSourceRange(corrected):
                XCTAssertEqual(corrected, 2.013654 * pow(metered, 1.3891), accuracy: 1e-6)
            default:
                XCTFail("Expected withinSourceRange at \(metered) s.")
            }
        }
    }

    // MARK: - noCorrectionThroughSeconds guard

    func testNoCorrectionGuardIsInclusiveAtTheBoundary() {
        let formula = ReciprocityFormula(
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: 0.001), .noCorrection)
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: 1), .noCorrection)
        if case .noCorrection = formula.evaluate(meteredExposureSeconds: 1.0001) {
            XCTFail("Inputs strictly greater than noCorrectionThroughSeconds must leave the no-correction band.")
        }
    }

    // MARK: - Reference time != 1 path (Tc = a × (Tm / Tref)^p)

    func testNonDefaultReferenceTimeProducesScaledFormula() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 128,
            referenceMeteredTimeSeconds: 128,
            exponent: 1.3676,
            noCorrectionThroughSeconds: 128,
            sourceRangeThroughSeconds: 240
        )
        // At Tm = Tref the power term equals coefficientSeconds; the
        // corrected exposure is `coefficientSeconds + offsetSeconds`
        // (which here equals `coefficientSeconds` because `b = 0`).
        if case let .withinSourceRange(corrected) = formula.evaluate(meteredExposureSeconds: 200) {
            let expected = 128 * pow(200.0 / 128.0, 1.3676)
            XCTAssertEqual(corrected, expected, accuracy: 1e-6)
        } else {
            XCTFail("Expected withinSourceRange at 200 s.")
        }
    }

    // MARK: - Non-zero offset path (Tc = a × (Tm/Tref)^p + b)

    func testNonZeroOffsetIsAddedAfterPowerTerm() {
        // Coefficients chosen so the formula produces a corrected
        // exposure longer than the metered input across the entire
        // sampled range — otherwise the unsafe-formula safety net
        // would clamp the result to no-correction.
        let formula = ReciprocityFormula(
            coefficientSeconds: 10,
            referenceMeteredTimeSeconds: 10,
            exponent: 1.45,
            offsetSeconds: 0.3,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 100
        )
        switch formula.evaluate(meteredExposureSeconds: 20) {
        case let .withinSourceRange(corrected):
            let expected = 10 * pow(20.0 / 10.0, 1.45) + 0.3
            XCTAssertEqual(corrected, expected, accuracy: 1e-6)
        default:
            XCTFail("Expected withinSourceRange at 20 s.")
        }
    }

    // MARK: - sourceRangeThroughSeconds is not a hard calculation stop

    func testSourceRangeThroughSecondsIsConfidenceBoundaryNotCalculationStop() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 2,
            exponent: 1.45,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 100
        )
        if case let .beyondSourceRange(corrected) = formula.evaluate(meteredExposureSeconds: 500) {
            XCTAssertEqual(corrected, 2 * pow(500.0, 1.45), accuracy: 1e-6)
        } else {
            XCTFail("sourceRangeThroughSeconds must not gate the formula's arithmetic.")
        }
    }

    /// Profiles without a `sourceRangeThroughSeconds` classify every
    /// in-formula input as within the source range — there is no
    /// boundary to compare against.
    func testNilSourceRangeAlwaysClassifiesAsWithinSourceRange() {
        let formula = ReciprocityFormula(
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        for metered in [2.0, 100.0, 8_192.0] {
            if case .withinSourceRange = formula.evaluate(meteredExposureSeconds: metered) {
                continue
            }
            XCTFail("Profiles without a source range must classify \(metered) s as within source range.")
        }
    }

    // MARK: - Beyond-source classification surfaces through the evaluator

    func testEvaluatorClassifiesBeyondSourceFormulaAsUnsupportedWithPrediction() {
        let profile = ReciprocityProfile(
            id: "synthetic-bounded",
            name: "Synthetic bounded",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                publisher: "Test"
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        coefficientSeconds: 2,
                        exponent: 1.45,
                        noCorrectionThroughSeconds: 1,
                        sourceRangeThroughSeconds: 100
                    )
                )),
            ]
        )
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 500)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertEqual(
            result.correctedExposureSeconds ?? 0,
            2 * pow(500.0, 1.45),
            accuracy: 1e-6
        )
    }

    // MARK: - Invalid parameter handling (safe failure)

    func testInvalidFormulaParametersAreRejectedAsInvalidFormula() {
        // PTIMER-160 distinguishes formula-parameter errors from
        // input errors and runtime safety. Each malformed formula
        // returns `.invalidFormula` so PTIMER-84's editor / catalog
        // validation can surface a data error rather than a silent
        // no-correction handoff.
        let nonPositiveCoefficient = ReciprocityFormula(
            coefficientSeconds: 0,
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(nonPositiveCoefficient.evaluate(meteredExposureSeconds: 2), .invalidFormula)

        let nonPositiveReference = ReciprocityFormula(
            referenceMeteredTimeSeconds: 0,
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(nonPositiveReference.evaluate(meteredExposureSeconds: 2), .invalidFormula)

        let sourceBelowNoCorrection = ReciprocityFormula(
            exponent: 1.31,
            noCorrectionThroughSeconds: 10,
            sourceRangeThroughSeconds: 5
        )
        XCTAssertEqual(sourceBelowNoCorrection.evaluate(meteredExposureSeconds: 20), .invalidFormula)

        let nonFiniteCoefficient = ReciprocityFormula(
            coefficientSeconds: .infinity,
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(nonFiniteCoefficient.evaluate(meteredExposureSeconds: 2), .invalidFormula)
    }

    func testNonPositiveMeteredInputIsInvalidInput() {
        let formula = ReciprocityFormula(
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: 0), .invalidInput)
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: -1), .invalidInput)
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: .nan), .invalidInput)
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: .infinity), .invalidInput)
    }

    // MARK: - Unsafe-shortening runtime safety

    /// A formula whose parameters individually satisfy the contract
    /// (positive coefficient, sane reference) can still produce a
    /// corrected exposure shorter than the metered input at some
    /// inputs. This is NOT a formula-data error — it's a runtime
    /// safety case that the policy hands off to no-correction.
    func testFormulaThatWouldShortenExposureSurfacesAsUnsafeShortening() {
        // `Tc = Tm^0.5` produces corrected < metered for Tm > 1 s
        // (e.g. 4 → 2). Parameters are individually valid; the
        // unsafe-shortening case fires at runtime only.
        let formula = ReciprocityFormula(
            exponent: 0.5,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(formula.evaluate(meteredExposureSeconds: 4), .unsafeShorteningFormula)
    }

    /// PTIMER-160 routing: `.invalidFormula` surfaces as
    /// `.unsupportedOutOfPolicyRange` (a data error) — distinct
    /// from `.unsafeShorteningFormula`, which the safety net hands
    /// off to no-correction. A custom formula with bad parameters
    /// must NOT silently appear as "no correction needed".
    func testEvaluatorSurfacesInvalidFormulaAsUnsupported() {
        let profile = ReciprocityProfile(
            id: "synthetic-invalid-formula",
            name: "Synthetic invalid",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                publisher: "User"
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        coefficientSeconds: 0,
                        exponent: 1.31,
                        noCorrectionThroughSeconds: 1
                    )
                )),
            ]
        )
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 4)
        XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange)
        XCTAssertNil(
            result.correctedExposureSeconds,
            "Invalid formula must NOT surface a corrected exposure value."
        )
    }

    /// The policy evaluator wraps the safety failure in a
    /// no-correction handoff so the public guarantee stays intact:
    /// `corrected >= adjusted shutter` for every rule path.
    func testEvaluatorClampsUnsafeFormulaToNoCorrection() {
        let profile = ReciprocityProfile(
            id: "synthetic-shortening-formula",
            name: "Synthetic shortening",
            source: ReciprocitySourceProvenance(
                kind: .manufacturerPublished,
                authority: .official,
                publisher: "Test"
            ),
            rules: [
                .formula(FormulaReciprocityRule(
                    formula: ReciprocityFormula(
                        exponent: 0.5,
                        noCorrectionThroughSeconds: 1
                    )
                )),
            ]
        )
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 4)
        XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection)
        XCTAssertEqual(result.correctedExposureSeconds ?? -1, 4, accuracy: 1e-6)
    }

    // MARK: - Formula formatter (display rules)

    func testFormatterOmitsNeutralValuesForPlainPowerLaw() {
        let formula = ReciprocityFormula(
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(FormulaEquationFormatter.userFacingText(for: formula), "Tc = Tm^1.31")
    }

    func testFormatterRendersCoefficientWhenNonNeutral() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 2.2457,
            exponent: 1.4515,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(FormulaEquationFormatter.userFacingText(for: formula), "Tc = 2.2457 × Tm^1.4515")
    }

    func testFormatterRendersReferenceTimeWhenNonNeutral() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 2,
            referenceMeteredTimeSeconds: 10,
            exponent: 1.45,
            noCorrectionThroughSeconds: 1
        )
        // In the anchored shape the coefficient is the corrected
        // exposure at the reference time, so the formatter
        // renders it with seconds units.
        XCTAssertEqual(FormulaEquationFormatter.userFacingText(for: formula), "Tc = 2s × (Tm / 10s)^1.45")
    }

    func testFormatterRendersOffsetWhenNonZero() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 2,
            referenceMeteredTimeSeconds: 10,
            exponent: 1.45,
            offsetSeconds: 0.3,
            noCorrectionThroughSeconds: 1
        )
        XCTAssertEqual(FormulaEquationFormatter.userFacingText(for: formula), "Tc = 2s × (Tm / 10s)^1.45 + 0.3s")
    }

    func testFormatterDropsExponentOneForConstantMultiplierForm() {
        let formula = ReciprocityFormula(
            coefficientSeconds: 1.4142136,
            exponent: 1,
            noCorrectionThroughSeconds: 119.999_999
        )
        XCTAssertEqual(FormulaEquationFormatter.userFacingText(for: formula), "Tc = 1.4142 × Tm")
    }

    // MARK: - Existing Details formula display does not regress

    func testShippedFormulaProfilesRenderThroughTheNewFormatter() throws {
        let panF = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Pan F Plus" }
        )
        let panFFormula = try XCTUnwrap(formulaRule(in: panF)?.formula)
        XCTAssertEqual(FormulaEquationFormatter.userFacingText(for: panFFormula), "Tc = Tm^1.33")

        let provia = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Provia 100F" }
        )
        let proviaFormula = try XCTUnwrap(formulaRule(in: provia)?.formula)
        XCTAssertEqual(
            FormulaEquationFormatter.userFacingText(for: proviaFormula),
            "Tc = 128s × (Tm / 128s)^1.3676"
        )
    }

    private func formulaRule(in film: FilmIdentity) -> FormulaReciprocityRule? {
        for profile in film.profiles {
            for rule in profile.rules {
                if case let .formula(formulaRule) = rule {
                    return formulaRule
                }
            }
        }
        return nil
    }

    // MARK: - Open-boundary wording in policy notes

    /// PTIMER-168 migrated Tri-X 400 (the former
    /// `noCorrectionThroughSeconds = 0.999999` open-boundary formula
    /// case) to the table model, so the epsilon-encoded open-boundary
    /// formula wording is now exercised on Acros II below.
    ///
    /// Acros II's `noCorrectionThroughSeconds = 119.999999` is the
    /// open-boundary case at 120 s: the note must read "< 120 sec",
    /// never the rounded inclusive "≤ 120 sec".
    func testOpenBoundaryNoCorrectionNoteUsesStrictlyBelowWording() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Acros II" }
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 60)
        let noteText = result.metadata.notes
            .first(where: { $0.text.lowercased().contains("no-correction range") })?.text
        let resolved = try XCTUnwrap(noteText, "Acros II must surface a no-correction range note.")
        XCTAssertTrue(
            resolved.contains("< 120 sec"),
            "Acros II no-correction note must use open-boundary wording '< 120 sec'; got: \(resolved)"
        )
        XCTAssertFalse(
            resolved.contains("≤ 120 sec"),
            "Acros II note must NOT use the inclusive '≤ 120 sec' wording; got: \(resolved)"
        )
    }

    /// Inclusive-boundary profiles (Ilford HP5 Plus's 1 s, Provia
    /// 100F's 128 s) keep the rounded "≤ X sec" form so the user
    /// reads the boundary value itself as part of the no-correction
    /// band.
    func testInclusiveNoCorrectionBoundaryNoteUsesLeqWording() throws {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" }
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.5)
        let noteText = result.metadata.notes
            .first(where: { $0.text.lowercased().contains("no-correction range") })?.text
        let resolved = try XCTUnwrap(noteText, "HP5 Plus must surface a no-correction range note.")
        XCTAssertTrue(
            resolved.contains("≤ 1 sec"),
            "Inclusive 1 s boundary must render as '≤ 1 sec'; got: \(resolved)"
        )
    }

    // MARK: - Formula family discriminator

    /// PTIMER-160 introduces `FormulaFamily` so PTIMER-162's
    /// Kron-Halm continuous family can be added without changing
    /// the rest of the domain. PTIMER-160 itself ships exactly one
    /// family — `.modifiedSchwarzschild` — and every shipped formula
    /// profile must declare it explicitly so the discriminator is
    /// load-bearing rather than nominal.
    func testEveryShippedFormulaProfileDeclaresModifiedSchwarzschildFamily() throws {
        for film in LaunchPresetFilmCatalog.films {
            for profile in film.profiles {
                for rule in profile.rules {
                    guard case let .formula(formulaRule) = rule else { continue }
                    XCTAssertEqual(
                        formulaRule.formula.formulaFamily,
                        .modifiedSchwarzschild,
                        "\(film.canonicalStockName) must declare formulaFamily = .modifiedSchwarzschild."
                    )
                }
            }
        }
    }

    func testFormulaFamilyRoundTripsThroughCodable() throws {
        let formula = ReciprocityFormula(
            formulaFamily: .modifiedSchwarzschild,
            exponent: 1.31,
            noCorrectionThroughSeconds: 1
        )
        let data = try JSONEncoder().encode(formula)
        let decoded = try JSONDecoder().decode(ReciprocityFormula.self, from: data)
        XCTAssertEqual(decoded.formulaFamily, .modifiedSchwarzschild)
    }

    /// JSON missing the `formulaFamily` discriminator must fail to
    /// decode rather than silently defaulting — PTIMER-162 will add
    /// a new family value and the load-time guard makes sure no
    /// profile slips through without declaring which family it
    /// belongs to.
    func testDecoderRejectsFormulaJSONWithoutFormulaFamilyDiscriminator() {
        let json = #"""
        {
          "exponent": 1.31,
          "noCorrectionThroughSeconds": 1
        }
        """#
        XCTAssertThrowsError(
            try JSONDecoder().decode(ReciprocityFormula.self, from: Data(json.utf8))
        )
    }

    // MARK: - Shipped catalog safety regression

    /// Policy-level safety regression. The policy evaluator can
    /// rewrite an `.unsafeShorteningFormula` arithmetic result to a
    /// no-correction handoff, so this test does NOT inspect the
    /// formula curve directly — it only verifies the user-facing
    /// `Tc ≥ Tm` safety guarantee after that runtime handoff at
    /// representative formula-domain points (just above the
    /// no-correction boundary, at the source-range top when
    /// present, and one beyond-source point). `.invalidInput` /
    /// `.invalidFormula` / `.formulaOutputUnusable` are catalog data
    /// errors and must never fire for shipped profiles. Formula
    /// arithmetic safety is checked separately by the direct
    /// formula-level catalog test below.
    func testEveryShippedFormulaProfilePassesSafetyAtRepresentativePoints() throws {
        for film in LaunchPresetFilmCatalog.films {
            for profile in film.profiles {
                for rule in profile.rules {
                    guard case let .formula(formulaRule) = rule else { continue }
                    let formula = formulaRule.formula
                    let samples = catalogSafetySamples(for: formula)

                    for metered in samples {
                        let result = evaluator.evaluate(
                            profile: profile,
                            meteredExposureSeconds: metered
                        )
                        switch result.metadata.basis {
                        case .officialThresholdNoCorrection,
                             .formulaDerived,
                             .tableLogLogDerived,
                             .unsupportedOutOfPolicyRange:
                            break  // expected
                        case .limitedGuidanceNoQuantifiedPrediction:
                            XCTFail(
                                "\(film.canonicalStockName) at \(metered) s surfaced limited-guidance basis from a formula profile."
                            )
                        }
                        // Either a corrected value exists and
                        // satisfies Tc ≥ Tm, or the result is
                        // limited-guidance / value-less unsupported
                        // (no value to validate). Shipped formula
                        // profiles never use limited-guidance, and
                        // beyond-source still carries a numeric
                        // value, so the `nil` branch only fires for
                        // catalog data errors — which would have
                        // tripped the basis check above.
                        if let corrected = result.correctedExposureSeconds {
                            XCTAssertTrue(
                                corrected.isFinite && corrected > 0,
                                "\(film.canonicalStockName) at \(metered) s produced non-finite/non-positive corrected exposure \(corrected)."
                            )
                            XCTAssertGreaterThanOrEqual(
                                corrected,
                                metered - 1e-6,
                                "\(film.canonicalStockName) at \(metered) s produced corrected \(corrected) < metered \(metered); the universal safety guarantee Tc ≥ Tm is broken."
                            )
                        }
                    }
                }
            }
        }
    }

    /// Catalog-level safety check that bypasses the policy
    /// evaluator's runtime handoff and validates the FORMULA CURVE
    /// itself. The policy-level test above also verifies that the
    /// runtime safety net keeps `Tc ≥ Tm`, but the safety net
    /// rewrites `.unsafeShorteningFormula` to a no-correction
    /// result — that masks formulas whose arithmetic would have
    /// shortened the exposure. This test asserts that no shipped
    /// formula ever needs the safety handoff in the first place:
    /// `formula.evaluate(...)` at representative formula-domain
    /// points must never return `.invalidInput`,
    /// `.invalidFormula`, `.formulaOutputUnusable`, or
    /// `.unsafeShorteningFormula`. The shipped catalog must be
    /// well-behaved on its own; future profile changes that would
    /// rely on the safety net trip this test.
    ///
    /// A small exemption set
    /// (`knownFormulaFitGapsRequiringRuntimeHandoff`) records films
    /// whose published source markers sit below the formula's
    /// natural Tc = Tm crossover — those formulas DO need the
    /// runtime handoff for inputs in (source marker, crossover].
    /// Listing them here keeps the regression visible without
    /// silently masquerading the data-sheet boundary as an app-
    /// derived value; the user-observable corrected exposure is
    /// already protected by the policy-level safety test above.
    /// PTIMER-160 ships the existing fits unchanged; refitting is
    /// out of scope and is tracked separately.
    func testEveryShippedFormulaArithmeticIsSelfSafeAtRepresentativePoints() throws {
        for film in LaunchPresetFilmCatalog.films {
            for profile in film.profiles {
                for rule in profile.rules {
                    guard case let .formula(formulaRule) = rule else { continue }
                    let formula = formulaRule.formula
                    let samples = catalogSafetySamples(for: formula)
                    let exemptJustAbove = Self.knownFormulaFitGapsRequiringRuntimeHandoff
                        .contains(film.canonicalStockName)

                    for (index, metered) in samples.enumerated() {
                        let outcome = formula.evaluate(meteredExposureSeconds: metered)
                        // Index 0 is the just-above-noCorrection
                        // sample. Films whose fitted formula's natural
                        // crossover lies above the source marker rely
                        // on the runtime safety net there — surface
                        // the gap but accept it for those films only.
                        if index == 0,
                           exemptJustAbove,
                           outcome == .unsafeShorteningFormula {
                            continue
                        }
                        switch outcome {
                        case .noCorrection:
                            // Hitting the no-correction guard at a
                            // representative formula-domain sample
                            // means the sample lands on / below the
                            // boundary, which is acceptable —
                            // identity satisfies Tc = Tm by
                            // construction.
                            continue
                        case let .withinSourceRange(corrected),
                             let .beyondSourceRange(corrected):
                            XCTAssertTrue(
                                corrected.isFinite && corrected > 0,
                                "\(film.canonicalStockName) at \(metered) s produced non-finite/non-positive corrected exposure \(corrected)."
                            )
                            XCTAssertGreaterThanOrEqual(
                                corrected,
                                metered - 1e-6,
                                "\(film.canonicalStockName) at \(metered) s produced corrected \(corrected) < metered \(metered); the formula curve must satisfy Tc ≥ Tm without runtime handoff."
                            )
                        case .invalidInput,
                             .invalidFormula,
                             .formulaOutputUnusable,
                             .unsafeShorteningFormula:
                            XCTFail(
                                "\(film.canonicalStockName) at \(metered) s produced \(outcome) — shipped formula arithmetic must be self-safe unless explicitly listed in `knownFormulaFitGapsRequiringRuntimeHandoff`; runtime handoff is reserved for user-defined / custom formulas."
                            )
                        }
                    }
                }
            }
        }
    }

    /// Rollei profiles whose fitted formulas' natural Tc = Tm
    /// crossover sits above the manufacturer's published no-
    /// correction marker. Inputs in (source marker, crossover]
    /// produce `Tc < Tm` from the formula alone and therefore go
    /// through the policy evaluator's runtime safety handoff. The
    /// source markers stay accurate (they ARE the published
    /// values); the fit-quality gap is documented as a follow-up
    /// refit candidate rather than masked by changing
    /// `noCorrectionThroughSeconds` away from the source marker.
    private static let knownFormulaFitGapsRequiringRuntimeHandoff: Set<String> = [
        "RPX 100",
        "RETRO 80S",
        "SUPERPAN 200",
    ]

    /// Representative formula-domain samples shared by the policy-
    /// level and formula-level catalog safety tests. Sample ordering
    /// matters: index 0 is the just-above-noCorrection probe used by
    /// the exemption logic above.
    ///
    /// - index 0: just above the no-correction boundary,
    /// - index 1: at the source-range top (when published),
    /// - index 2: one beyond-source point (when the source range is
    ///   bounded) or a long-exposure sample for open-ended profiles.
    private func catalogSafetySamples(for formula: ReciprocityFormula) -> [Double] {
        var samples: [Double] = []
        samples.append(formula.noCorrectionThroughSeconds * 1.01 + 0.05)
        if let upper = formula.sourceRangeThroughSeconds {
            samples.append(upper)
            samples.append(upper * 2)
        } else {
            samples.append(max(formula.noCorrectionThroughSeconds * 100, 60))
        }
        return samples
    }
}
