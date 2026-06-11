import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-169 Phase 1 guard: the thirteen special / range /
/// limited-guidance target profiles declare their source shape
/// explicitly instead of relying on `effectiveModelBasis` inference.
///
/// The inference cannot represent Acros II honestly — a formula rule
/// plus source evidence infers `manufacturerTable`, but Fujifilm
/// publishes a RANGE RULE (120–1000 s +1/2 stop) that the formula
/// merely encodes verbatim. Explicit declarations keep the source
/// shape a catalog fact rather than a derivation, and this suite
/// keeps the declarations from regressing to nil.
///
/// Deliberately narrow: only the PTIMER-169 target list is guarded.
/// A catalog-wide mandatory-modelBasis rule is out of scope for this
/// ticket (deferred metadata consistency pass).
final class SourceShapeModelBasisTests: XCTestCase {

    /// Expected explicit declarations for every PTIMER-169 target.
    private let expectedDeclarations: [(stock: String, source: ReciprocitySourceModel, calculation: ReciprocityCalculationModel)] = [
        // Published range rule encoded verbatim as a guarded formula —
        // NOT an app-derived table fit.
        ("Acros II", .manufacturerRangeGuidance, .guardedFormula),
        // Fujifilm slide films: table + color/warning guidance source,
        // fitted guarded formula calculation (Phase 1 keeps the fit).
        ("Velvia 50", .manufacturerTable, .guardedFormula),
        ("Velvia 100", .manufacturerTable, .guardedFormula),
        ("Provia 100F", .manufacturerTable, .guardedFormula),
        // Rollei tables with range-valued rows.
        ("RETRO 80S", .manufacturerTable, .guardedFormula),
        ("SUPERPAN 200", .manufacturerTable, .guardedFormula),
        // ADOX sparse/special anchors.
        ("CMS 20 II", .manufacturerTable, .guardedFormula),
        // Kodak limited guidance: qualitative only, never quantified.
        ("Ektar 100", .manufacturerLimitedGuidance, .limitedGuidance),
        ("Portra 160", .manufacturerLimitedGuidance, .limitedGuidance),
        ("Portra 400", .manufacturerLimitedGuidance, .limitedGuidance),
        ("Gold 200", .manufacturerLimitedGuidance, .limitedGuidance),
        ("Ultra Max 400", .manufacturerLimitedGuidance, .limitedGuidance),
        ("Ektachrome E100", .manufacturerLimitedGuidance, .limitedGuidance),
    ]

    func testTargetProfilesDeclareExplicitModelBasis() throws {
        for expected in expectedDeclarations {
            let profile = try profile(expected.stock)
            let basis = try XCTUnwrap(
                profile.modelBasis,
                "\(expected.stock) must declare an explicit modelBasis (PTIMER-169)."
            )
            XCTAssertEqual(basis.sourceModel, expected.source, "\(expected.stock) source model")
            XCTAssertEqual(
                basis.calculationModel,
                expected.calculation,
                "\(expected.stock) calculation model"
            )
        }
    }

    /// The explicit declaration is what `effectiveModelBasis` now
    /// returns — downstream presentation reads the declared shape, not
    /// the inference.
    func testEffectiveModelBasisHonorsExplicitDeclarations() throws {
        for expected in expectedDeclarations {
            let profile = try profile(expected.stock)
            XCTAssertEqual(profile.effectiveModelBasis.sourceModel, expected.source, expected.stock)
            XCTAssertEqual(
                profile.effectiveModelBasis.calculationModel,
                expected.calculation,
                expected.stock
            )
        }
    }

    /// Regression guard for the specific dishonesty PTIMER-169 fixes:
    /// without the explicit declaration, inference mislabels Acros II
    /// as a manufacturer table.
    func testAcrosIIDeclarationOverridesTableInference() throws {
        let profile = try profile("Acros II")
        XCTAssertEqual(
            profile.effectiveModelBasis.sourceModel,
            .manufacturerRangeGuidance,
            "Acros II's source is Fujifilm's published range rule, not a table."
        )
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
