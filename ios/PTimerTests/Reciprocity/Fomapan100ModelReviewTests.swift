import Foundation
import PTimerCore
import XCTest
@testable import PTimer

/// PTIMER-161: review fixture that pins the data used by
/// `docs/tasks/PTIMER-161/fomapan-100-multi-profile-review.md`.
///
/// These tests do not change production behavior. They:
///
/// - lock the official FOMA BOHEMIA Fomapan 100 Classic table
///   (1 sec / 10 sec / 100 sec → 2× / 8× / 16×) used as the
///   review's source-of-truth anchors,
/// - lock the Ohzart / community practical table referenced in the
///   review,
/// - lock the current shipped guarded-formula outputs and their
///   per-anchor residuals (stop + percent) against the official
///   table,
/// - lock that the community formula image
///   `Te = tm × ((log10 tm)² + 5 log10 tm + 2)` passes the three
///   official anchors exactly,
/// - lock that the community formula image and the Ohzart table are
///   NOT the same model: at 2 / 4 / 8 / 15 / 30 / 60 sec they
///   disagree by enough that a future UI must keep them visibly
///   separated.
///
/// The review document quotes these numbers; if the catalog drift or
/// the formula constants ever silently change, this file fails first.
final class Fomapan100ModelReviewTests: XCTestCase {

    // MARK: - Fixtures (mirror the review document, §2 and §3)

    /// Official FOMA BOHEMIA Fomapan 100 Classic published rows.
    /// Reproduced verbatim from the technical sheet via the
    /// PTIMER-128 source snapshot (`LaunchPresetFilmCatalog_ori.json`)
    /// and the Confluence "FOMA BOHEMIA Reciprocity Data" page.
    private struct OfficialAnchor {
        let metered: Double
        let multiplier: Double
        let corrected: Double
    }

    private let officialAnchors: [OfficialAnchor] = [
        OfficialAnchor(metered: 1, multiplier: 2, corrected: 2),
        OfficialAnchor(metered: 10, multiplier: 8, corrected: 80),
        OfficialAnchor(metered: 100, multiplier: 16, corrected: 1600),
    ]

    /// Ohzart / community practical table, from
    /// `https://ohzart1.tistory.com/78` (mirrored on the Confluence
    /// "Communitity Sources Data" page). Treated as unofficial
    /// community guidance only — not FOMA-published data.
    private struct OhzartRow {
        let metered: Double
        let corrected: Double
    }

    private let ohzartRows: [OhzartRow] = [
        OhzartRow(metered: 1, corrected: 1.9),
        OhzartRow(metered: 2, corrected: 5),
        OhzartRow(metered: 4, corrected: 13),
        OhzartRow(metered: 8, corrected: 35),
        OhzartRow(metered: 15, corrected: 90),
        OhzartRow(metered: 30, corrected: 265),
        OhzartRow(metered: 60, corrected: 795),
    ]

    /// Current app guarded-formula constants for the Fomapan 100
    /// Classic catalog profile (`foma-fomapan-100-official-formula`).
    /// These values are duplicated here as the *review reference*
    /// values; one of the tests below verifies the live catalog
    /// constants still match, so a drift would fail loud.
    private let currentAppCoefficient = 2.2457
    private let currentAppExponent = 1.4515

    // MARK: - Official FOMA table — fixture integrity

    func testOfficialFomapan100TableMatchesPublishedRows() {
        XCTAssertEqual(officialAnchors.count, 3)

        XCTAssertEqual(officialAnchors[0].metered, 1, accuracy: 1e-9)
        XCTAssertEqual(officialAnchors[0].multiplier, 2, accuracy: 1e-9)
        XCTAssertEqual(officialAnchors[0].corrected, 2, accuracy: 1e-9)

        XCTAssertEqual(officialAnchors[1].metered, 10, accuracy: 1e-9)
        XCTAssertEqual(officialAnchors[1].multiplier, 8, accuracy: 1e-9)
        XCTAssertEqual(officialAnchors[1].corrected, 80, accuracy: 1e-9)

        XCTAssertEqual(officialAnchors[2].metered, 100, accuracy: 1e-9)
        XCTAssertEqual(officialAnchors[2].multiplier, 16, accuracy: 1e-9)
        XCTAssertEqual(officialAnchors[2].corrected, 1600, accuracy: 1e-9)
    }

    func testOfficialAnchorCorrectedMatchesMeteredTimesMultiplier() {
        for anchor in officialAnchors {
            XCTAssertEqual(
                anchor.corrected,
                anchor.metered * anchor.multiplier,
                accuracy: 1e-9,
                "Official FOMA row \(anchor.metered) s must equal metered × multiplier."
            )
        }
    }

    // MARK: - Ohzart / community table — fixture integrity

    func testOhzartCommunityTableMatchesBlogRows() {
        XCTAssertEqual(ohzartRows.count, 7)

        let expected: [(Double, Double)] = [
            (1, 1.9),
            (2, 5),
            (4, 13),
            (8, 35),
            (15, 90),
            (30, 265),
            (60, 795),
        ]
        for (row, expected) in zip(ohzartRows, expected) {
            XCTAssertEqual(row.metered, expected.0, accuracy: 1e-9)
            XCTAssertEqual(row.corrected, expected.1, accuracy: 1e-9)
        }
    }

    // MARK: - Current app formula — outputs match the review numbers

    /// Catalog drift guard: the shipped profile must still carry the
    /// `2.2457 × Tm^1.4515` fit. If a later ticket changes the
    /// constants, the review document and these residual tables go
    /// stale together — this test fails first so the drift is
    /// surfaced loudly.
    func testAppDerivedFormulaStillCarriesReviewedFomapan100FormulaConstants() throws {
        // PTIMER-159: the reviewed p-formula is no longer Fomapan's
        // default (the official log-log table is). It survives as the
        // non-default app-derived formula model, which this fixture pins.
        let profile = AlternateReciprocityModels.fomapan100AppDerivedFormula
        let formulaRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first,
            "The app-derived Fomapan 100 model must keep a formula rule for the review fixture to make sense."
        )

        XCTAssertEqual(
            formulaRule.formula.coefficientSeconds,
            currentAppCoefficient,
            accuracy: 1e-4,
            "Review document assumes a=2.2457; the shipped catalog has drifted."
        )
        XCTAssertEqual(
            formulaRule.formula.exponent,
            currentAppExponent,
            accuracy: 1e-4,
            "Review document assumes p=1.4515; the shipped catalog has drifted."
        )

        let basis = try XCTUnwrap(
            profile.modelBasis,
            "Fomapan 100 Classic must declare a modelBasis after PTIMER-163."
        )
        XCTAssertEqual(
            basis.sourceModel,
            .manufacturerTable,
            "Review document treats Fomapan 100's source as a manufacturer table."
        )
        XCTAssertEqual(
            basis.calculationModel,
            .guardedFormula,
            "Review document treats Fomapan 100's calculation as the app's derived guarded formula."
        )
    }

    func testCurrentAppFormulaOutputsMatchReviewNumbers() throws {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let profile = AlternateReciprocityModels.fomapan100AppDerivedFormula

        let oneSecond = try XCTUnwrap(
            evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)
                .correctedExposureSeconds
        )
        XCTAssertEqual(oneSecond, 2.2457, accuracy: 1e-4)

        let tenSeconds = try XCTUnwrap(
            evaluator.evaluate(profile: profile, meteredExposureSeconds: 10)
                .correctedExposureSeconds
        )
        // 2.2457 × 10^1.4515 ≈ 63.5114 s — review document rounds to ~63.51 s.
        XCTAssertEqual(tenSeconds, 63.5114, accuracy: 0.01)

        let hundredSeconds = try XCTUnwrap(
            evaluator.evaluate(profile: profile, meteredExposureSeconds: 100)
                .correctedExposureSeconds
        )
        // 2.2457 × 100^1.4515 ≈ 1796.1878 s — review document rounds to ~1796.19 s.
        XCTAssertEqual(hundredSeconds, 1796.1878, accuracy: 0.5)
    }

    // MARK: - Current app formula — residuals against official anchors

    /// Pins the per-anchor residual table reproduced in §3.1 of the
    /// review document. Failing here means the review's "+12.3% /
    /// +0.167 stop" et al. are no longer accurate and the document
    /// needs to be regenerated.
    func testCurrentAppFormulaResidualsAgainstOfficialTableMatchReviewSummary() throws {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let profile = AlternateReciprocityModels.fomapan100AppDerivedFormula

        struct ExpectedResidual {
            let metered: Double
            let percentDelta: Double
            let stopDelta: Double
        }
        let expected: [ExpectedResidual] = [
            ExpectedResidual(metered: 1, percentDelta: 12.3, stopDelta: 0.167),
            ExpectedResidual(metered: 10, percentDelta: -20.6, stopDelta: -0.333),
            ExpectedResidual(metered: 100, percentDelta: 12.3, stopDelta: 0.167),
        ]

        for row in expected {
            let anchor = try XCTUnwrap(
                officialAnchors.first(where: { $0.metered == row.metered })
            )
            let predicted = try XCTUnwrap(
                evaluator.evaluate(profile: profile, meteredExposureSeconds: row.metered)
                    .correctedExposureSeconds
            )

            let ratio = predicted / anchor.corrected
            let percent = (ratio - 1) * 100
            let stops = log2(ratio)

            XCTAssertEqual(
                percent,
                row.percentDelta,
                accuracy: 0.1,
                "App-formula vs official at \(row.metered) s: review says \(row.percentDelta)%, got \(percent)%."
            )
            XCTAssertEqual(
                stops,
                row.stopDelta,
                accuracy: 0.005,
                "App-formula vs official at \(row.metered) s: review says \(row.stopDelta) stop, got \(stops) stop."
            )
        }
    }

    // MARK: - Community formula — passes official anchors

    func testCommunityFormulaImagePassesOfficialFomapan100Anchors() {
        for anchor in officialAnchors {
            let predicted = communityFormula(metered: anchor.metered)
            XCTAssertEqual(
                predicted,
                anchor.corrected,
                accuracy: 1e-9,
                "Te = tm[(log10 tm)^2 + 5 log10 tm + 2] must hit FOMA's anchor at \(anchor.metered) s exactly."
            )
        }
    }

    // MARK: - Community formula ≠ Ohzart table

    /// Pins §3.3 of the review document: the community formula image
    /// and the Ohzart practical table do NOT describe the same
    /// correction curve. Forcing a meaningful tolerance per row makes
    /// it impossible for a future change to silently equate the two.
    func testCommunityFormulaImageIsNotEquivalentToOhzartTable() throws {
        struct ExpectedGap {
            let metered: Double
            /// Lower bound (inclusive) on log2(formula / ohzart) the
            /// review found at this input. Values are conservative
            /// rounded-down forms of the computed stop deltas
            /// (+0.524, +0.725, +0.745, +0.627, +0.389, +0.085).
            let minimumStopGap: Double
        }
        let expected: [ExpectedGap] = [
            ExpectedGap(metered: 2, minimumStopGap: 0.40),
            ExpectedGap(metered: 4, minimumStopGap: 0.60),
            ExpectedGap(metered: 8, minimumStopGap: 0.60),
            ExpectedGap(metered: 15, minimumStopGap: 0.50),
            ExpectedGap(metered: 30, minimumStopGap: 0.30),
            ExpectedGap(metered: 60, minimumStopGap: 0.05),
        ]

        for row in expected {
            let ohzart = try XCTUnwrap(
                ohzartRows.first(where: { $0.metered == row.metered })?.corrected
            )
            let formulaPrediction = communityFormula(metered: row.metered)
            let stopGap = log2(formulaPrediction / ohzart)

            XCTAssertGreaterThanOrEqual(
                stopGap,
                row.minimumStopGap,
                "Community formula at \(row.metered) s predicts \(formulaPrediction) s; Ohzart row says \(ohzart) s. Review document records a gap of at least \(row.minimumStopGap) stop — getting \(stopGap) stop."
            )
        }
    }

    /// Inverse direction: the review needs to assert *not equal*, not
    /// just "formula is longer". Even at the closest checked input
    /// (60 sec) the formula sits more than 5% above the Ohzart row.
    /// Locking the minimum percent gap keeps the document accurate
    /// even if future regenerations tighten the stop tolerances.
    func testCommunityFormulaImagePercentGapAgainstOhzartTableStaysAboveFivePercent() throws {
        for sample in [2.0, 4.0, 8.0, 15.0, 30.0, 60.0] {
            let ohzart = try XCTUnwrap(
                ohzartRows.first(where: { $0.metered == sample })?.corrected
            )
            let formulaPrediction = communityFormula(metered: sample)
            let percentGap = (formulaPrediction / ohzart - 1) * 100
            XCTAssertGreaterThan(
                percentGap,
                5,
                "Community formula at \(sample) s must sit measurably longer than Ohzart's \(ohzart) s; got \(percentGap)%."
            )
        }
    }

    // MARK: - Helpers

    /// Closed-form community formula image (Confluence
    /// "Communitity Sources Data"): `Te = tm × ((log10 tm)^2 +
    /// 5 log10 tm + 2)`. Defined locally so the test is
    /// independent of any production code path — the formula is a
    /// review candidate, not a shipped calculation model.
    private func communityFormula(metered tm: Double) -> Double {
        let logTm = log10(tm)
        return tm * (logTm * logTm + 5 * logTm + 2)
    }

    private func profile(for canonicalStockName: String) throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: canonicalStockName)
    }
}
