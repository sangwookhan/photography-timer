import XCTest
import PTimerCore
@testable import PTimer

/// Cross-film behavior contract for every **converted formula**
/// reciprocity film shipped in the launch catalog.
///
/// Each per-film test file (`AcrosIIFormulaProfileTests`,
/// `Velvia50FormulaProfileTests`, …) pins the *film-specific*
/// contract: the fitted exponent / multiplier, the published source
/// evidence rows, threshold and not-recommended boundary values,
/// and any profile-specific policy branches.
///
/// This file pins the *engine-and-presenter* behaviors that should
/// be identical across every converted formula film, with one
/// `ConvertedFormulaProfileCase` row per film (the launch catalog
/// currently ships one converted formula profile per film, and the
/// catalog-coverage guard below pins that mapping). A regression in
/// converted-profile defaults (e.g. `isConvertedFormulaProfile`,
/// the formula-derived summary wording inside the source range, or
/// "Beyond source range" wording above the upper bound) therefore
/// fails once with a clear "X is the offending film" message
/// instead of producing N nearly-identical failures across per-film
/// files.
final class ConvertedFormulaProfileTemplateTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    /// One row per converted-formula film in the launch catalog
    /// (the catalog ships exactly one converted formula profile per
    /// film; the `testTemplateCaseListCoversEveryConvertedFormulaProfileInCatalog`
    /// guard below fails if that mapping breaks).
    ///
    /// - `belowThresholdSample` sits strictly inside the
    ///   no-correction band.
    /// - `insideFormulaRangeSample` sits inside the source-backed
    ///   formula range.
    /// - `aboveSourceRangeSample` sits strictly past the published
    ///   upper bound.
    private struct ConvertedFormulaProfileCase {
        let canonicalStockName: String
        let belowThresholdSample: Double
        let insideFormulaRangeSample: Double
        let aboveSourceRangeSample: Double
    }

    private static let allCases: [ConvertedFormulaProfileCase] = [
        ConvertedFormulaProfileCase(
            canonicalStockName: "Acros II",
            belowThresholdSample: 60,
            insideFormulaRangeSample: 500,
            aboveSourceRangeSample: 2000
        ),
        ConvertedFormulaProfileCase(
            canonicalStockName: "CMS 20 II",
            belowThresholdSample: 0.5,
            insideFormulaRangeSample: 5,
            aboveSourceRangeSample: 200
        ),
        // PTIMER-159: Fomapan 100 Classic migrated to the official
        // log-log table model. PTIMER-168 migrated the remaining
        // straightforward official table-origin profiles — Fomapan 200
        // Creative, Fomapan 400 Action, Tri-X 400, T-MAX 100, T-MAX 400,
        // RPX 100, RPX 400, and CHS 100 II — to the same table model, so
        // none of them are converted-formula profiles any more. Their
        // table-origin contract lives in their per-film test files and in
        // the PTIMER-168 catalog migration invariant test. The rows that
        // remain here are the films still awaiting follow-up (PTIMER-169)
        // plus CMS 20 II.
        ConvertedFormulaProfileCase(
            canonicalStockName: "Provia 100F",
            belowThresholdSample: 60,
            insideFormulaRangeSample: 240,
            aboveSourceRangeSample: 600
        ),
        ConvertedFormulaProfileCase(
            canonicalStockName: "RETRO 80S",
            belowThresholdSample: 0.25,
            insideFormulaRangeSample: 15,
            aboveSourceRangeSample: 90
        ),
        ConvertedFormulaProfileCase(
            canonicalStockName: "SUPERPAN 200",
            belowThresholdSample: 0.25,
            insideFormulaRangeSample: 15,
            aboveSourceRangeSample: 90
        ),
        ConvertedFormulaProfileCase(
            canonicalStockName: "Velvia 100",
            belowThresholdSample: 30,
            insideFormulaRangeSample: 120,
            aboveSourceRangeSample: 300
        ),
        ConvertedFormulaProfileCase(
            canonicalStockName: "Velvia 50",
            belowThresholdSample: 0.5,
            insideFormulaRangeSample: 8,
            aboveSourceRangeSample: 100
        ),
    ]

    // MARK: - Catalog coverage guard

    /// Every converted-formula film in the launch catalog must appear
    /// in `allCases` above, and every catalog film must ship exactly
    /// one converted formula profile so the parameter table's
    /// "one row per film" key remains unambiguous. If a new film is
    /// added to the catalog with `isConvertedFormulaProfile == true`,
    /// an existing one is removed, or any film grows a second
    /// converted profile, this test fails with a diff that names the
    /// affected film so the template parameter table can be updated
    /// in the same change.
    func testTemplateCaseListCoversEveryConvertedFormulaProfileInCatalog() {
        let convertedFilms = LaunchPresetFilmCatalog.films.filter {
            $0.profiles.contains(where: { $0.isConvertedFormulaProfile })
        }

        let filmsWithMultipleConvertedProfiles = convertedFilms
            .filter { $0.profiles.filter(\.isConvertedFormulaProfile).count > 1 }
            .map(\.canonicalStockName)
            .sorted()
        XCTAssertTrue(
            filmsWithMultipleConvertedProfiles.isEmpty,
            "ConvertedFormulaProfileTemplateTests.allCases keys on canonicalStockName, but these films ship more than one converted formula profile: \(filmsWithMultipleConvertedProfiles). Either consolidate to one converted profile per film or rekey the parameter table on a (film, profile) pair."
        )

        let cataloged = Set(convertedFilms.map(\.canonicalStockName))
        let exercised = Set(Self.allCases.map(\.canonicalStockName))

        let missingFromTable = cataloged.subtracting(exercised).sorted()
        let staleInTable = exercised.subtracting(cataloged).sorted()

        XCTAssertTrue(
            missingFromTable.isEmpty,
            "ConvertedFormulaProfileTemplateTests.allCases is missing converted-formula films that exist in the launch catalog: \(missingFromTable). Add a row for each missing film."
        )
        XCTAssertTrue(
            staleInTable.isEmpty,
            "ConvertedFormulaProfileTemplateTests.allCases references films that are no longer converted-formula in the launch catalog: \(staleInTable). Remove the stale row(s)."
        )
    }

    // MARK: - Profile-shape templates

    /// Every converted formula profile carries a formula rule plus
    /// source evidence and must surface as a converted formula
    /// profile so the presenter routes it through the converted
    /// formula presentation branch.
    func testEveryConvertedProfileIsFlaggedAsConvertedFormula() throws {
        for testCase in Self.allCases {
            let profile = try FormulaProfileTestSupport.profile(for: testCase.canonicalStockName)
            XCTAssertTrue(
                profile.isConvertedFormulaProfile,
                "\(testCase.canonicalStockName) must surface as a converted formula profile (formula rule + source evidence)."
            )
        }
    }

    /// After conversion the published rows live as `sourceEvidence`
    /// only — the catalog ships with formula + threshold rules only.
    /// `LaunchPresetFilmCatalogShapeTests` enforces the no-table-rule
    /// invariant at the structural level for every launch preset; this
    /// per-profile check is folded in there.
    func testEveryConvertedProfileCarriesAFormulaRule() throws {
        for testCase in Self.allCases {
            let profile = try FormulaProfileTestSupport.profile(for: testCase.canonicalStockName)
            let hasFormula = profile.rules.contains { rule in
                if case .formula = rule { return true }
                return false
            }
            XCTAssertTrue(
                hasFormula,
                "\(testCase.canonicalStockName) must carry a formula rule after the PTIMER-128 conversion."
            )
        }
    }

    // MARK: - Engine basis templates

    /// At an input strictly below each profile's threshold, the
    /// evaluator returns the no-correction basis with corrected
    /// equal to the metered value.
    func testEveryConvertedProfileBelowThresholdSampleIsOfficialNoCorrection() throws {
        for testCase in Self.allCases {
            let profile = try FormulaProfileTestSupport.profile(for: testCase.canonicalStockName)
            let result = evaluator.evaluate(
                profile: profile,
                meteredExposureSeconds: testCase.belowThresholdSample
            )
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(testCase.canonicalStockName) at \(testCase.belowThresholdSample) s must sit inside the no-correction band."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "\(testCase.canonicalStockName) below threshold must report a corrected exposure equal to the metered value."
            )
            XCTAssertEqual(
                corrected,
                testCase.belowThresholdSample,
                accuracy: 1e-6,
                "\(testCase.canonicalStockName) below threshold must keep corrected == metered."
            )
        }
    }

    // MARK: - Presenter wording templates

    /// Inside the source-backed formula range every converted
    /// profile reads as a formula-derived correction — never the
    /// "Beyond source range" wording reserved for past-upper-bound
    /// inputs.
    @MainActor
    func testEveryConvertedProfileInsideRangeSummaryReadsAsFormulaDerived() throws {
        for testCase in Self.allCases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: testCase.canonicalStockName,
                meteredExposureSeconds: testCase.insideFormulaRangeSample
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Formula-based correction on the active curve",
                "\(testCase.canonicalStockName) inside the source-backed range must surface the formula-derived summary."
            )
        }
    }

    /// Above the published upper bound the summary surface reads as
    /// "Beyond source range" so the user never reads the value as
    /// manufacturer-supported. The `summary.summaryText` invariant
    /// holds for every converted profile including CMS 20 II, whose
    /// detail / explanation copy differs (no numeric continuation).
    @MainActor
    func testEveryConvertedProfileAboveSourceRangeSummaryIsBeyondSourceRange() throws {
        for testCase in Self.allCases {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(
                film: testCase.canonicalStockName,
                meteredExposureSeconds: testCase.aboveSourceRangeSample
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Beyond source range",
                "\(testCase.canonicalStockName) above the published upper bound must surface the beyond-source-range summary."
            )
        }
    }
}
