import XCTest
@testable import PTimer

/// PTIMER-159: Fomapan 100 Classic's default official model is the
/// log-log table (not the old p-formula), reproduces the official
/// anchors exactly, keeps computing past the published range, and the
/// app-derived formula survives only as a non-default alternate.
final class Fomapan100TableModelTests: XCTestCase {

    private func fomapanProfile() throws -> ReciprocityProfile {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Fomapan 100 Classic" }
        )
        return film.profiles[0]
    }

    private func corrected(_ profile: ReciprocityProfile, at metered: Double) -> Double? {
        ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: profile, meteredExposureSeconds: metered)
            .correctedExposureSeconds
    }

    func testCatalogLoadsTableModelProfile() throws {
        let profile = try fomapanProfile()
        let basis = try XCTUnwrap(profile.modelBasis)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
    }

    func testDefaultModelReproducesOfficialAnchorsExactly() throws {
        let profile = try fomapanProfile()
        XCTAssertEqual(try XCTUnwrap(corrected(profile, at: 1)), 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(corrected(profile, at: 10)), 80, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(corrected(profile, at: 100)), 1600, accuracy: 0.0001)
    }

    func testDefaultModelIsNotTheOldPFormula() throws {
        let profile = try fomapanProfile()
        // The retired p-formula (Tc = 2.2457·Tm^1.4515) gives ≈ 63.5 s
        // at 10 s; the official table gives exactly 80 s.
        let value = try XCTUnwrap(corrected(profile, at: 10))
        XCTAssertEqual(value, 80, accuracy: 0.0001)
        XCTAssertGreaterThan(abs(value - 63.5), 10, "Default must be the official table, not the p-formula fit.")
    }

    func testBeyondSourceRangeStillComputesAValue() throws {
        let profile = try fomapanProfile()
        // 1000 s is past the 100 s table; it must still return a value
        // (extrapolated, beyond source range), never a value-less result.
        let result = ReciprocityCalculationPolicyEvaluator()
            .evaluate(profile: profile, meteredExposureSeconds: 1000)
        XCTAssertNotNil(
            result.correctedExposureSeconds,
            "Inputs past the published table must still compute a value."
        )
        XCTAssertGreaterThan(try XCTUnwrap(result.correctedExposureSeconds), 1600)
    }

    func testAppDerivedFormulaAlternateUsesPFormulaNotTheTable() throws {
        let alternates = AlternateReciprocityModels.alternates(forFilmID: "foma-fomapan-100")
        let appFormula = try XCTUnwrap(alternates.first { $0.id == "foma-fomapan-100-app-formula" })
        XCTAssertEqual(appFormula.name, "App-derived formula")
        // The alternate is the p-formula: ≈ 63.5 s at 10 s, distinct from
        // the official table's 80 s.
        let value = try XCTUnwrap(corrected(appFormula, at: 10))
        XCTAssertEqual(value, pow(10.0, 1.4515) * 2.2457, accuracy: 0.5)
        XCTAssertNotEqual(value, 80, accuracy: 5)
    }
}
