import XCTest
@testable import PTimerKit

/// Data-driven golden for the launch catalog's per-film reciprocity
/// profiles (PTIMER-174 consolidation).
///
/// This single suite replaces the engine-path assertions that were
/// duplicated across ~12 per-film files (Velvia 50/100, Acros II,
/// Rollei, Adox, Adox CHS 100, Tri-X 400, T-MAX 100/400, Foma,
/// Provia 100F, HP5+). Each film's genuine data-regression guards —
/// profile identity, rule parameters (formula exponent/coefficient or
/// table anchors), no-correction / source-range boundaries, model
/// basis, and the published source-evidence rows — live as one
/// `FilmExpectation` row. The universal evaluator contract (threshold
/// → no-correction, in-range → derived, beyond-source → unsupported
/// but still numeric) is asserted once, per film, in a loop.
///
/// Runs in PTimerKitTests (no simulator). Film-specific UI surfacing
/// (Details sections, graph markers) stays in the app-hosted
/// invariant suites; this golden locks the domain values only.
///
/// Failure messages always name the film so a single-row regression
/// is immediately identifiable.
final class FilmReciprocityGoldenTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    enum Kind { case formula, table }

    struct FilmExpectation {
        let stock: String
        // Identity / model-basis are asserted only when the original
        // per-film test asserted them (left nil otherwise — the golden
        // mirrors each film's existing guards, it does not invent new ones).
        var profileID: String? = nil
        var profileName: String? = nil
        let kind: Kind
        var sourceModel: ReciprocitySourceModel? = nil
        var calculationModel: ReciprocityCalculationModel? = nil
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double
        // formula only:
        var formulaExponent: Double? = nil
        var formulaCoefficientSeconds: Double? = nil
        // table only:
        var tableAnchors: [(metered: Double, corrected: Double)] = []
        // a metered value strictly above the source range:
        let beyondSourceMetered: Double
        // exact metered values that must remain as source evidence:
        var sourceEvidenceMetered: [Double] = []
    }

    // MARK: - Expectations

    private let expectations: [FilmExpectation] = [
        FilmExpectation(
            stock: "Velvia 50",
            kind: .formula,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 32,
            formulaExponent: 1.1821,
            formulaCoefficientSeconds: 1,
            beyondSourceMetered: 64,
            sourceEvidenceMetered: [4, 8, 16, 32, 64]
        ),
        FilmExpectation(
            stock: "Tri-X 400",
            profileID: "kodak-tri-x-official-graph-table",
            profileName: "Official Kodak graph/table",
            kind: .table,
            sourceModel: .manufacturerTable,
            calculationModel: .tableLogLogInterpolation,
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            tableAnchors: [
                (1, 2), (2, 5), (3, 10), (5, 20), (7, 32),
                (10, 50), (20, 120), (30, 200), (50, 420), (70, 720), (100, 1200),
            ],
            beyondSourceMetered: 200,
            sourceEvidenceMetered: [1, 10, 100]
        ),
        FilmExpectation(
            stock: "Velvia 100",
            kind: .formula,
            noCorrectionThroughSeconds: 60,
            sourceRangeThroughSeconds: 240,
            formulaExponent: 1.2667,
            formulaCoefficientSeconds: 60,
            beyondSourceMetered: 300,
            sourceEvidenceMetered: [120, 240]
        ),
        FilmExpectation(
            stock: "CMS 20 II",
            kind: .formula,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 10,
            formulaExponent: 1.150515,
            formulaCoefficientSeconds: 1.4142136,
            beyondSourceMetered: 14,
            sourceEvidenceMetered: [0.001, 1, 10, 100]
        ),
        FilmExpectation(
            stock: "Provia 100F",
            kind: .formula,
            noCorrectionThroughSeconds: 128,
            sourceRangeThroughSeconds: 240,
            formulaExponent: 1.3676,
            formulaCoefficientSeconds: 128,
            beyondSourceMetered: 360,
            sourceEvidenceMetered: [240, 480]
        ),
        FilmExpectation(
            stock: "CHS 100 II",
            profileID: "adox-chs-100-ii-official-table",
            profileName: "Official ADOX table",
            kind: .table,
            sourceModel: .manufacturerTable,
            calculationModel: .tableLogLogInterpolation,
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 15,
            tableAnchors: [(2, 3), (4, 8), (8, 20), (15, 45)],
            beyondSourceMetered: 16,
            sourceEvidenceMetered: [2, 4, 8, 15]
        ),
        FilmExpectation(
            stock: "Fomapan 200 Creative",
            profileName: "Official FOMA table",
            kind: .table,
            sourceModel: .manufacturerTable,
            calculationModel: .tableLogLogInterpolation,
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 100,
            tableAnchors: [(1, 3), (10, 90), (100, 1800)],
            beyondSourceMetered: 150,
            sourceEvidenceMetered: [1, 10, 100]
        ),
        FilmExpectation(
            stock: "Fomapan 400 Action",
            profileName: "Official FOMA table",
            kind: .table,
            sourceModel: .manufacturerTable,
            calculationModel: .tableLogLogInterpolation,
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 100,
            tableAnchors: [(1, 1.5), (10, 60), (100, 800)],
            beyondSourceMetered: 150,
            sourceEvidenceMetered: [1, 10, 100]
        ),
        FilmExpectation(
            stock: "T-MAX 100",
            kind: .table,
            sourceModel: .manufacturerTable,
            calculationModel: .tableLogLogInterpolation,
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            tableAnchors: [(1, 1.2599210498948732), (10, 15), (100, 200)],
            beyondSourceMetered: 150,
            sourceEvidenceMetered: [1, 10, 100]
        ),
        FilmExpectation(
            stock: "T-MAX 400",
            kind: .table,
            sourceModel: .manufacturerTable,
            calculationModel: .tableLogLogInterpolation,
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            tableAnchors: [(1, 1.2599210498948732), (10, 15), (100, 300)],
            beyondSourceMetered: 150,
            sourceEvidenceMetered: [1, 10, 100]
        ),
    ]

    // MARK: - Coverage guard

    func testEveryExpectationResolvesToACatalogFilm() throws {
        for e in expectations {
            XCTAssertNoThrow(try profile(e.stock), "\(e.stock): expected film missing from launch catalog.")
        }
    }

    // MARK: - Profile identity & model basis

    func testProfileIdentityAndModelBasisMatch() throws {
        for e in expectations {
            let p = try profile(e.stock)
            if let id = e.profileID { XCTAssertEqual(p.id, id, "\(e.stock): profile id.") }
            if let name = e.profileName { XCTAssertEqual(p.name, name, "\(e.stock): profile name.") }
            if e.sourceModel != nil || e.calculationModel != nil {
                let basis = try XCTUnwrap(p.modelBasis, "\(e.stock): missing modelBasis.")
                if let sm = e.sourceModel { XCTAssertEqual(basis.sourceModel, sm, "\(e.stock): sourceModel.") }
                if let cm = e.calculationModel { XCTAssertEqual(basis.calculationModel, cm, "\(e.stock): calculationModel.") }
            }
        }
    }

    // MARK: - Rule parameters (formula exponent / table anchors)

    func testRuleParametersMatchPublishedData() throws {
        for e in expectations {
            let p = try profile(e.stock)
            switch e.kind {
            case .formula:
                let rule = try XCTUnwrap(formulaRule(p), "\(e.stock): expected a .formula rule.")
                XCTAssertNil(tableRule(p), "\(e.stock): formula film must not carry a table rule.")
                XCTAssertEqual(rule.formula.noCorrectionThroughSeconds, e.noCorrectionThroughSeconds, accuracy: 1e-9, "\(e.stock): noCorrection.")
                XCTAssertEqual(rule.formula.sourceRangeThroughSeconds ?? -1, e.sourceRangeThroughSeconds, accuracy: 1e-6, "\(e.stock): sourceRange.")
                if let exp = e.formulaExponent {
                    XCTAssertEqual(rule.formula.exponent, exp, accuracy: 1e-4, "\(e.stock): exponent.")
                }
                if let coef = e.formulaCoefficientSeconds {
                    XCTAssertEqual(rule.formula.coefficientSeconds, coef, accuracy: 1e-4, "\(e.stock): coefficient.")
                }
            case .table:
                let rule = try XCTUnwrap(tableRule(p), "\(e.stock): expected a .tableInterpolation rule.")
                XCTAssertNil(formulaRule(p), "\(e.stock): table film must not carry a formula rule.")
                XCTAssertEqual(rule.noCorrectionThroughSeconds, e.noCorrectionThroughSeconds, accuracy: 1e-9, "\(e.stock): noCorrection.")
                XCTAssertEqual(rule.sourceRangeThroughSeconds, e.sourceRangeThroughSeconds, accuracy: 1e-6, "\(e.stock): sourceRange.")
                let anchors = Dictionary(uniqueKeysWithValues: rule.anchors.map { ($0.meteredSeconds, $0.correctedSeconds) })
                XCTAssertEqual(anchors.count, e.tableAnchors.count, "\(e.stock): anchor count.")
                for a in e.tableAnchors {
                    XCTAssertEqual(anchors[a.metered] ?? -1, a.corrected, accuracy: 1e-4, "\(e.stock): anchor \(a.metered)s → \(a.corrected)s.")
                }
            }
        }
    }

    // MARK: - Universal evaluator contract

    func testEvaluatorContractPerFilm() throws {
        for e in expectations {
            let p = try profile(e.stock)

            // (1) At the no-correction boundary: official no-correction, Tc == Tm.
            let atBoundary = evaluator.evaluate(profile: p, meteredExposureSeconds: e.noCorrectionThroughSeconds)
            XCTAssertEqual(atBoundary.metadata.basis, .officialThresholdNoCorrection, "\(e.stock): boundary basis.")
            XCTAssertEqual(try XCTUnwrap(atBoundary.correctedExposureSeconds), e.noCorrectionThroughSeconds, accuracy: 1e-6, "\(e.stock): boundary Tc==Tm.")

            // (2) In the source-backed range: derived (formula vs table).
            let inRange = (e.noCorrectionThroughSeconds + e.sourceRangeThroughSeconds) / 2
            let derived = evaluator.evaluate(profile: p, meteredExposureSeconds: inRange)
            let expectedBasis: ReciprocityCalculationBasis = (e.kind == .formula) ? .formulaDerived : .tableLogLogDerived
            XCTAssertEqual(derived.metadata.basis, expectedBasis, "\(e.stock): in-range basis at \(inRange)s.")
            XCTAssertNotNil(derived.correctedExposureSeconds, "\(e.stock): in-range corrected non-nil.")

            // (3) Beyond the source range: unsupported, but still a numeric prediction.
            let beyond = evaluator.evaluate(profile: p, meteredExposureSeconds: e.beyondSourceMetered)
            XCTAssertEqual(beyond.metadata.basis, .unsupportedOutOfPolicyRange, "\(e.stock): beyond-source basis at \(e.beyondSourceMetered)s.")
            XCTAssertNotNil(beyond.correctedExposureSeconds, "\(e.stock): beyond-source still numeric.")
        }
    }

    // MARK: - Source-evidence preservation

    func testSourceEvidencePreservesPublishedRows() throws {
        for e in expectations where !e.sourceEvidenceMetered.isEmpty {
            let p = try profile(e.stock)
            let evidenceMetered = p.sourceEvidence.compactMap { row -> Double? in
                if case let .exactSeconds(s) = row.meteredExposure { return s } else { return nil }
            }
            for m in e.sourceEvidenceMetered {
                XCTAssertTrue(
                    evidenceMetered.contains(where: { abs($0 - m) < 1e-6 }),
                    "\(e.stock): source evidence must preserve published metered row \(m)s (got \(evidenceMetered))."
                )
            }
        }
    }

    // MARK: - Helpers

    private func profile(_ stock: String) throws -> ReciprocityProfile {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog."
        )
        return try XCTUnwrap(film.profiles.first, "\(stock): no primary profile.")
    }

    private func formulaRule(_ p: ReciprocityProfile) -> FormulaReciprocityRule? {
        p.rules.compactMap { if case let .formula(r) = $0 { return r } else { return nil } }.first
    }

    private func tableRule(_ p: ReciprocityProfile) -> TableInterpolationReciprocityRule? {
        p.rules.compactMap { if case let .tableInterpolation(r) = $0 { return r } else { return nil } }.first
    }
}
