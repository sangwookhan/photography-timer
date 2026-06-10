import XCTest
import PTimerKit
import PTimerCore

/// Source-data contract for the **table-log-log reciprocity archetype**.
/// `TableLogLogReciprocityContractTests` pins the shared rule-kind /
/// model-basis / summary / graph-wording invariants; this suite pins the
/// per-film *source data* that those tests deliberately leave out: the
/// published table anchors and the corrected times they reproduce, the
/// no-correction threshold (and its nominal tolerance), the table-derived
/// and beyond-source classification, the published source-evidence rows
/// with their corrected times / stop deltas / development adjustments,
/// and the Details / graph markers.
///
/// Every exact value stays film-specific case data; the assertion shape
/// is shared, so no film name appears in a test-function name. Films
/// whose mid-region behavior is genuinely unique (T-MAX 100's short-
/// exposure exclusion, Tri-X 400's sub-1 s interpolation and three-model
/// alternates) keep those in their own suites with the film as a constant.
final class TableProfileSourceDataContractTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    private struct Anchor {
        let metered: Double
        let corrected: Double
    }

    /// A published source-evidence row's expected attributes.
    private struct EvidenceRow {
        let metered: Double
        var correctedSeconds: Double?
        var stopDelta: Double?
        var multiplier: Double?
        var approximateCorrected = false
        var developmentInstruction: String?
    }

    private struct TableFilmCase {
        let film: String
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double
        let anchors: [Anchor]
        let belowThresholdSamples: [Double]
        /// `nil` skips the nominal-tolerance check (only the 1/10 s
        /// Kodak films drift to ~0.102 s; the FOMA films use a 1/2 s band).
        let nominalToleranceSample: Double?
        let clearlyCorrectedSamples: [Double]
        let insideSamples: [Double]
        let aboveSourceSamples: [Double]
        let evidenceMetereds: [Double]
        let evidenceRows: [EvidenceRow]
        let detailTokens: [String]
        let markers: [Anchor]
        let beyondSourceStartSeconds: Double
        // Provenance / identity — asserted only when set.
        var sourceKind: ReciprocitySourceKind?
        var authority: ReciprocityAuthority?
        var publisher: String?
        var profileName: String?
        var profileIdSuffix: String?
        var modelSourceModel: ReciprocitySourceModel?
        var modelCalculationModel: ReciprocityCalculationModel?
        /// Published source citation title (asserted when set).
        var sourceTitle: String?
        /// Legend chips the table graph must / must not surface (asserted
        /// when non-empty).
        var requiredLegendChips: [String] = []
        var forbiddenLegendChips: [String] = []
        /// A sub-threshold sample whose graph current point reads
        /// `.noCorrection` with the "No correction" status (when set).
        var noCorrectionStatusSample: Double?
        /// A beyond-source sample whose graph current point reads
        /// `.beyondSourceRange` with the "Beyond source range" status
        /// (when set).
        var beyondSourceStatusSample: Double?
        /// Non-default profile lookup (e.g. a community/app-derived
        /// alternate). `nil` uses the film's default catalog profile.
        var profileProvider: (() throws -> ReciprocityProfile)?
        /// Whether the Details / graph display-state surfaces are
        /// exercised for this case. `false` for profiles whose only
        /// published source-data is the evaluator path (e.g. alternates
        /// selected through the view model elsewhere).
        var exercisesDisplayState = true

        var lastAnchorCorrected: Double { anchors.last?.corrected ?? 0 }
    }

    private func profile(for c: TableFilmCase) throws -> ReciprocityProfile {
        if let provider = c.profileProvider { return try provider() }
        return try FormulaProfileTestSupport.profile(for: c.film)
    }

    private let cases: [TableFilmCase] = [
        TableFilmCase(
            film: "T-MAX 100",
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            anchors: [Anchor(metered: 1, corrected: 1.2599210498948732), Anchor(metered: 10, corrected: 15), Anchor(metered: 100, corrected: 200)],
            belowThresholdSamples: [0.01, 0.05, 0.1],
            nominalToleranceSample: 0.102,
            clearlyCorrectedSamples: [0.12, 0.15],
            insideSamples: [1, 2, 5, 10, 50, 100],
            aboveSourceSamples: [150, 300, 1000],
            evidenceMetereds: [1, 10, 100],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 1.2599210498948732, stopDelta: 1.0 / 3.0, approximateCorrected: true),
                EvidenceRow(metered: 10, correctedSeconds: 15),
                EvidenceRow(metered: 100, correctedSeconds: 200),
            ],
            detailTokens: ["1.0s", "10.0s", "100.0s", "15", "200"],
            markers: [Anchor(metered: 1, corrected: 1.2599210498948732), Anchor(metered: 10, corrected: 15), Anchor(metered: 100, corrected: 200)],
            beyondSourceStartSeconds: 100.000001
        ),
        TableFilmCase(
            film: "T-MAX 400",
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            anchors: [Anchor(metered: 1, corrected: 1.2599210498948732), Anchor(metered: 10, corrected: 15), Anchor(metered: 100, corrected: 300)],
            belowThresholdSamples: [0.0001, 0.05, 0.1],
            nominalToleranceSample: 0.102,
            clearlyCorrectedSamples: [0.12, 0.15],
            insideSamples: [1, 2, 5, 10, 30, 100],
            aboveSourceSamples: [150, 400, 2000],
            evidenceMetereds: [1, 10, 100],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 1.2599210498948732, stopDelta: 1.0 / 3.0, approximateCorrected: true),
                EvidenceRow(metered: 10, correctedSeconds: 15, stopDelta: 0.5),
                EvidenceRow(metered: 100, correctedSeconds: 300, stopDelta: 1.5),
            ],
            detailTokens: ["1.0s", "10.0s", "100.0s", "15", "300"],
            markers: [Anchor(metered: 1, corrected: 1.2599210498948732), Anchor(metered: 10, corrected: 15), Anchor(metered: 100, corrected: 300)],
            beyondSourceStartSeconds: 100.000001
        ),
        TableFilmCase(
            film: "Tri-X 400",
            noCorrectionThroughSeconds: 0.1,
            sourceRangeThroughSeconds: 100,
            anchors: [
                Anchor(metered: 1, corrected: 2), Anchor(metered: 2, corrected: 5), Anchor(metered: 3, corrected: 10),
                Anchor(metered: 5, corrected: 20), Anchor(metered: 7, corrected: 32), Anchor(metered: 10, corrected: 50),
                Anchor(metered: 20, corrected: 120), Anchor(metered: 30, corrected: 200), Anchor(metered: 50, corrected: 420),
                Anchor(metered: 70, corrected: 720), Anchor(metered: 100, corrected: 1200),
            ],
            belowThresholdSamples: [0.01, 0.05, 0.1],
            nominalToleranceSample: 0.102,
            clearlyCorrectedSamples: [0.12, 0.15],
            insideSamples: [1, 5, 10, 25, 50, 100],
            aboveSourceSamples: [150, 300, 1000],
            evidenceMetereds: [1, 10, 100],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 2, stopDelta: 1, developmentInstruction: "-10% development"),
                EvidenceRow(metered: 10, correctedSeconds: 50, stopDelta: 2, developmentInstruction: "-20% development"),
                EvidenceRow(metered: 100, correctedSeconds: 1200, stopDelta: 3, developmentInstruction: "-30% development"),
            ],
            detailTokens: ["-10%", "-20%", "-30%"],
            markers: [Anchor(metered: 1, corrected: 2), Anchor(metered: 10, corrected: 50), Anchor(metered: 100, corrected: 1200)],
            beyondSourceStartSeconds: 100.000001
        ),
        TableFilmCase(
            film: "Fomapan 200 Creative",
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 100,
            anchors: [Anchor(metered: 1, corrected: 3), Anchor(metered: 10, corrected: 90), Anchor(metered: 100, corrected: 1800)],
            belowThresholdSamples: [0.5],
            nominalToleranceSample: nil,
            clearlyCorrectedSamples: [],
            insideSamples: [1, 10, 100],
            aboveSourceSamples: [150, 300, 1000],
            evidenceMetereds: [1, 10, 100],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 3, multiplier: 3),
                EvidenceRow(metered: 10, correctedSeconds: 90, multiplier: 9),
                EvidenceRow(metered: 100, correctedSeconds: 1800, multiplier: 18),
            ],
            detailTokens: ["3x", "9x", "18x"],
            markers: [Anchor(metered: 1, corrected: 3), Anchor(metered: 10, corrected: 90), Anchor(metered: 100, corrected: 1800)],
            beyondSourceStartSeconds: 100.000001,
            sourceKind: .manufacturerPublished, authority: .official, publisher: "FOMA BOHEMIA",
            profileName: "Official FOMA table", profileIdSuffix: "-official-table"
        ),
        TableFilmCase(
            film: "Fomapan 400 Action",
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 100,
            anchors: [Anchor(metered: 1, corrected: 1.5), Anchor(metered: 10, corrected: 60), Anchor(metered: 100, corrected: 800)],
            belowThresholdSamples: [0.5],
            nominalToleranceSample: nil,
            clearlyCorrectedSamples: [],
            insideSamples: [1, 10, 100],
            aboveSourceSamples: [150, 300, 1000],
            evidenceMetereds: [1, 10, 100],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 1.5, multiplier: 1.5),
                EvidenceRow(metered: 10, correctedSeconds: 60, multiplier: 6),
                EvidenceRow(metered: 100, correctedSeconds: 800, multiplier: 8),
            ],
            detailTokens: ["1.5x", "6x", "8x"],
            markers: [Anchor(metered: 1, corrected: 1.5), Anchor(metered: 10, corrected: 60), Anchor(metered: 100, corrected: 800)],
            beyondSourceStartSeconds: 100.000001,
            sourceKind: .manufacturerPublished, authority: .official, publisher: "FOMA BOHEMIA",
            profileName: "Official FOMA table", profileIdSuffix: "-official-table"
        ),
        // Fomapan 100 Classic — official FOMA table (default profile).
        TableFilmCase(
            film: "Fomapan 100 Classic",
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 100,
            anchors: [Anchor(metered: 1, corrected: 2), Anchor(metered: 10, corrected: 80), Anchor(metered: 100, corrected: 1600)],
            belowThresholdSamples: [0.5],
            nominalToleranceSample: nil,
            clearlyCorrectedSamples: [],
            insideSamples: [1, 10, 100],
            aboveSourceSamples: [1000],
            evidenceMetereds: [1, 10, 100],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 2),
                EvidenceRow(metered: 10, correctedSeconds: 80),
                EvidenceRow(metered: 100, correctedSeconds: 1600),
            ],
            detailTokens: [],
            markers: [],
            beyondSourceStartSeconds: 100.000001,
            sourceKind: .manufacturerPublished, authority: .official, publisher: "FOMA BOHEMIA",
            modelSourceModel: .manufacturerTable, modelCalculationModel: .tableLogLogInterpolation,
            exercisesDisplayState: false
        ),
        // Fomapan 100 Classic — Ohzart community practical table
        // (non-default alternate). Same table-log-log archetype; differs
        // only by provenance (community) and its published anchors.
        TableFilmCase(
            film: "Fomapan 100 Classic",
            noCorrectionThroughSeconds: 0.5,
            sourceRangeThroughSeconds: 60,
            anchors: [
                Anchor(metered: 1, corrected: 1.9), Anchor(metered: 2, corrected: 5), Anchor(metered: 4, corrected: 13),
                Anchor(metered: 8, corrected: 35), Anchor(metered: 15, corrected: 90), Anchor(metered: 30, corrected: 265),
                Anchor(metered: 60, corrected: 795),
            ],
            belowThresholdSamples: [0.4, 0.5],
            nominalToleranceSample: nil,
            clearlyCorrectedSamples: [],
            insideSamples: [2, 8, 30],
            aboveSourceSamples: [120],
            evidenceMetereds: [1, 2, 4, 8, 15, 30, 60],
            evidenceRows: [
                EvidenceRow(metered: 1, correctedSeconds: 1.9),
                EvidenceRow(metered: 2, correctedSeconds: 5),
                EvidenceRow(metered: 4, correctedSeconds: 13),
                EvidenceRow(metered: 8, correctedSeconds: 35),
                EvidenceRow(metered: 15, correctedSeconds: 90),
                EvidenceRow(metered: 30, correctedSeconds: 265),
                EvidenceRow(metered: 60, correctedSeconds: 795),
            ],
            detailTokens: [],
            markers: [],
            beyondSourceStartSeconds: 60.000001,
            authority: .unofficial,
            modelSourceModel: .practicalCommunityGuidance, modelCalculationModel: .tableLogLogInterpolation,
            profileProvider: { try XCTUnwrap(AlternateReciprocityModels.alternates(forFilmID: "foma-fomapan-100").first { $0.id == "foma-fomapan-100-ohzart-community-table" }) },
            exercisesDisplayState: false
        ),
        // ADOX CHS 100 II — official ADOX 2024 table (default profile).
        TableFilmCase(
            film: "CHS 100 II",
            noCorrectionThroughSeconds: 1,
            sourceRangeThroughSeconds: 15,
            anchors: [Anchor(metered: 2, corrected: 3), Anchor(metered: 4, corrected: 8), Anchor(metered: 8, corrected: 20), Anchor(metered: 15, corrected: 45)],
            belowThresholdSamples: [1],
            nominalToleranceSample: nil,
            clearlyCorrectedSamples: [],
            insideSamples: [2, 4, 8, 15],
            aboveSourceSamples: [16, 30, 60, 200],
            evidenceMetereds: [2, 4, 8, 15],
            evidenceRows: [
                EvidenceRow(metered: 2, correctedSeconds: 3, multiplier: 1.5),
                EvidenceRow(metered: 4, correctedSeconds: 8, multiplier: 2),
                EvidenceRow(metered: 8, correctedSeconds: 20, multiplier: 2.5),
                EvidenceRow(metered: 15, correctedSeconds: 45, multiplier: 3),
            ],
            detailTokens: ["1.5x", "2x", "2.5x", "3x"],
            markers: [Anchor(metered: 2, corrected: 3), Anchor(metered: 4, corrected: 8), Anchor(metered: 8, corrected: 20), Anchor(metered: 15, corrected: 45)],
            beyondSourceStartSeconds: 15.000001,
            publisher: "ADOX",
            profileName: "Official ADOX table", profileIdSuffix: "-official-table",
            modelSourceModel: .manufacturerTable, modelCalculationModel: .tableLogLogInterpolation,
            sourceTitle: "ADOX CHS 100 II S/W Film — Technische Beschreibung, 11. Juli 2024",
            requiredLegendChips: ["Calculation curve", "Current result", "Source reference", "No-correction range"],
            forbiddenLegendChips: ["Estimated", "Extrapolated", "Not-recommended boundary"],
            noCorrectionStatusSample: 0.25,
            beyondSourceStatusSample: 30
        ),
    ]

    private func tableRule(in profile: ReciprocityProfile) throws -> TableInterpolationReciprocityRule {
        try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r }
                return nil
            }.first
        )
    }

    private func exactRows(in profile: ReciprocityProfile) -> [(Double, ReciprocitySourceEvidenceRow)] {
        profile.sourceEvidence.compactMap { row in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
    }

    // MARK: - Rule parameters and stored anchors

    func testTableRuleParametersAndStoredAnchorsMatchPublished() throws {
        for c in cases {
            let rule = try tableRule(in: try profile(for: c))
            XCTAssertEqual(rule.noCorrectionThroughSeconds, c.noCorrectionThroughSeconds, accuracy: 1e-6, "\(c.film): noCorrectionThroughSeconds")
            XCTAssertEqual(rule.sourceRangeThroughSeconds, c.sourceRangeThroughSeconds, accuracy: 1e-6, "\(c.film): sourceRangeThroughSeconds")
            XCTAssertEqual(rule.anchors.map { $0.meteredSeconds }, c.anchors.map { $0.metered }, "\(c.film): anchor metered seconds")
            let stored = Dictionary(uniqueKeysWithValues: rule.anchors.map { ($0.meteredSeconds, $0.correctedSeconds) })
            for anchor in c.anchors {
                XCTAssertEqual(stored[anchor.metered] ?? .nan, anchor.corrected, accuracy: 1e-4, "\(c.film): anchor \(anchor.metered)s corrected")
            }
        }
    }

    // MARK: - No-correction threshold (inclusive) and nominal tolerance

    func testAtAndBelowThresholdReturnsOfficialNoCorrection() throws {
        for c in cases {
            let profile = try profile(for: c)
            for metered in c.belowThresholdSamples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(result.metadata.basis, .officialThresholdNoCorrection, "\(c.film) @ \(metered)s: at/below threshold must be no-correction.")
                XCTAssertEqual(try XCTUnwrap(result.correctedExposureSeconds), metered, accuracy: 1e-6, "\(c.film) @ \(metered)s: corrected == metered.")
            }
        }
    }

    func testNominalThresholdToleranceClassifiesNoCorrection() throws {
        for c in cases {
            guard let nominalSample = c.nominalToleranceSample else { continue }
            let profile = try profile(for: c)
            let nominal = evaluator.evaluate(profile: profile, meteredExposureSeconds: nominalSample)
            XCTAssertEqual(nominal.metadata.basis, .officialThresholdNoCorrection, "\(c.film): nominal 1/10 s (~\(nominalSample)s) must read as no-correction.")
            XCTAssertEqual(try XCTUnwrap(nominal.correctedExposureSeconds), nominalSample, accuracy: 1e-6, "\(c.film): nominal corrected == metered.")
            for metered in c.clearlyCorrectedSamples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(result.metadata.basis, .tableLogLogDerived, "\(c.film) @ \(metered)s: clearly above the band must stay table-derived.")
                XCTAssertGreaterThan(try XCTUnwrap(result.correctedExposureSeconds), metered, "\(c.film) @ \(metered)s: corrected > metered.")
            }
        }
    }

    // MARK: - Table range and exact anchor reproduction

    func testInsideSourceRangeIsTableLogLogDerived() throws {
        for c in cases {
            let profile = try profile(for: c)
            for metered in c.insideSamples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(result.metadata.basis, .tableLogLogDerived, "\(c.film) @ \(metered)s: inside the source-backed table range.")
            }
        }
    }

    func testAnchorsReproducePublishedCorrectedTimesExactly() throws {
        for c in cases {
            let profile = try profile(for: c)
            for anchor in c.anchors {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: anchor.metered)
                XCTAssertEqual(try XCTUnwrap(result.correctedExposureSeconds), anchor.corrected, accuracy: 1e-4, "\(c.film) @ \(anchor.metered)s: must reproduce \(anchor.corrected)s exactly.")
            }
        }
    }

    // MARK: - Beyond the published source range

    func testAboveSourceRangeIsBeyondSourceWithExtrapolation() throws {
        for c in cases {
            let profile = try profile(for: c)
            for metered in c.aboveSourceSamples {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
                XCTAssertEqual(result.metadata.basis, .unsupportedOutOfPolicyRange, "\(c.film) @ \(metered)s: above the published upper anchor.")
                let corrected = try XCTUnwrap(result.correctedExposureSeconds, "\(c.film) @ \(metered)s: must keep an extrapolation value.")
                XCTAssertGreaterThan(corrected, c.lastAnchorCorrected, "\(c.film) @ \(metered)s: extrapolation must exceed the last anchor (\(c.lastAnchorCorrected)s).")
            }
        }
    }

    // MARK: - Source-evidence preservation

    func testSourceEvidencePreservesPublishedRows() throws {
        for c in cases {
            let profile = try profile(for: c)
            let exact = exactRows(in: profile)
            XCTAssertEqual(exact.map { $0.0 }, c.evidenceMetereds, "\(c.film): published source-evidence rows")
            for expected in c.evidenceRows {
                let row = try XCTUnwrap(exact.first(where: { abs($0.0 - expected.metered) < 1e-6 })?.1, "\(c.film): must preserve the \(expected.metered)s row.")
                assertEvidenceRow(expected, row, film: c.film)
            }
        }
    }

    private func assertEvidenceRow(_ expected: EvidenceRow, _ row: ReciprocitySourceEvidenceRow, film: String) {
        if let corrected = expected.correctedSeconds {
            let mapping = row.adjustments.compactMap { adjustment -> CorrectedTimeMapping? in
                guard case let .exposure(.correctedTime(value)) = adjustment else { return nil }
                return value
            }.first
            XCTAssertEqual(mapping?.correctedSeconds ?? .nan, corrected, accuracy: 1e-4, "\(film) @ \(expected.metered)s: published corrected time")
            if expected.approximateCorrected {
                XCTAssertTrue(mapping?.isApproximate ?? false, "\(film) @ \(expected.metered)s: corrected time must be flagged isApproximate.")
            }
        }
        if let stopDelta = expected.stopDelta {
            let actual = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
                return value.stopDelta
            }.first
            XCTAssertEqual(actual ?? .nan, stopDelta, accuracy: 0.01, "\(film) @ \(expected.metered)s: published stop delta")
        }
        if let development = expected.developmentInstruction {
            let actual = row.adjustments.compactMap { adjustment -> String? in
                guard case let .development(value) = adjustment else { return nil }
                return value.instruction
            }.first
            XCTAssertEqual(actual, development, "\(film) @ \(expected.metered)s: published development adjustment")
        }
        if let multiplier = expected.multiplier {
            let actual = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.multiplier(value)) = adjustment else { return nil }
                return value.factor
            }.first
            XCTAssertEqual(actual ?? .nan, multiplier, accuracy: 1e-6, "\(film) @ \(expected.metered)s: published multiplier factor")
        }
    }

    // MARK: - Source provenance and profile identity

    func testSourceProvenanceMatchesPublished() throws {
        for c in cases {
            guard c.sourceKind != nil || c.authority != nil || c.publisher != nil || c.sourceTitle != nil else { continue }
            let profile = try profile(for: c)
            if let kind = c.sourceKind { XCTAssertEqual(profile.source.kind, kind, "\(c.film): source kind") }
            if let authority = c.authority { XCTAssertEqual(profile.source.authority, authority, "\(c.film): source authority") }
            if let publisher = c.publisher { XCTAssertEqual(profile.source.publisher, publisher, "\(c.film): publisher") }
            if let title = c.sourceTitle { XCTAssertEqual(profile.source.title, title, "\(c.film): source citation title") }
        }
    }

    func testProfileIdentityMatchesPublished() throws {
        for c in cases {
            guard c.profileName != nil || c.profileIdSuffix != nil else { continue }
            let profile = try profile(for: c)
            if let name = c.profileName { XCTAssertEqual(profile.name, name, "\(c.film): profile name") }
            if let suffix = c.profileIdSuffix {
                XCTAssertTrue(profile.id.hasSuffix(suffix), "\(c.film): profile id must end with '\(suffix)'; got \(profile.id)")
            }
        }
    }

    /// The declared model basis (source model + calculation model) is
    /// case data — `.manufacturerTable` for official films, the
    /// `.practicalCommunityGuidance` source for the community alternate —
    /// so provenance is an axis, not a separate suite.
    func testModelBasisMatchesPublished() throws {
        for c in cases {
            guard c.modelSourceModel != nil || c.modelCalculationModel != nil else { continue }
            let basis = try XCTUnwrap(try profile(for: c).modelBasis, "\(c.film): must declare a modelBasis.")
            if let sourceModel = c.modelSourceModel { XCTAssertEqual(basis.sourceModel, sourceModel, "\(c.film): modelBasis.sourceModel") }
            if let calculationModel = c.modelCalculationModel { XCTAssertEqual(basis.calculationModel, calculationModel, "\(c.film): modelBasis.calculationModel") }
        }
    }

    // MARK: - Details and graph surfaces

    @MainActor
    func testDetailsSurfaceShowsSourceReferenceRows() throws {
        for c in cases where c.exercisesDisplayState {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: 10)
            let section = try XCTUnwrap(displayState.sections.first(where: { $0.title == "Source reference" }), "\(c.film): must surface a Source reference section.")
            let block = try XCTUnwrap(section.rows.first?.value)
            for token in c.detailTokens {
                XCTAssertTrue(block.contains(token), "\(c.film): Source reference must contain '\(token)'. Got:\n\(block)")
            }
            XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Reference" }), "\(c.film): must not surface the legacy Reference section.")
            XCTAssertFalse(displayState.sections.contains(where: { $0.title == "Guidance boundary" }), "\(c.film): no published not-recommended row; Guidance boundary must be absent.")
        }
    }

    @MainActor
    func testGraphCarriesSourceReferenceMarkers() throws {
        for c in cases where c.exercisesDisplayState {
            let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: 10)
            let graph = try XCTUnwrap(displayState.graph, "\(c.film): must surface a graph.")
            XCTAssertEqual(graph.kind, .formula, "\(c.film): table models render as the .formula graph kind.")

            let markerByMetered = Dictionary(uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) })
            XCTAssertEqual(Set(markerByMetered.keys), Set(c.markers.map { $0.metered }), "\(c.film): graph source markers")
            for marker in c.markers {
                XCTAssertEqual(markerByMetered[marker.metered] ?? .nan, marker.corrected, accuracy: max(0.01, marker.corrected * 1e-4), "\(c.film) @ \(marker.metered)s: marker corrected exposure")
            }
            XCTAssertNil(graph.notRecommendedBoundarySeconds, "\(c.film): no published not-recommended boundary.")
            XCTAssertEqual(graph.beyondSourceRangeStartSeconds ?? .nan, c.beyondSourceStartSeconds, accuracy: 1e-3, "\(c.film): beyond-source region start")
        }
    }

    @MainActor
    func testTableGraphLegendChipsMatchExpected() throws {
        for c in cases where !c.requiredLegendChips.isEmpty || !c.forbiddenLegendChips.isEmpty {
            let requiredSample = c.insideSamples.first ?? c.anchors.first?.metered ?? 1
            let requiredLabels = try XCTUnwrap(FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: requiredSample).graph, "\(c.film): must surface a graph.").legendChipLabels
            for chip in c.requiredLegendChips {
                XCTAssertTrue(requiredLabels.contains(chip), "\(c.film): legend must contain '\(chip)'; got \(requiredLabels).")
            }
            // Forbidden chips must be absent across sub-threshold, in-range, and beyond-source inputs.
            let forbiddenSamples = [c.noCorrectionStatusSample, requiredSample, c.beyondSourceStatusSample].compactMap { $0 }
            for sample in forbiddenSamples {
                let labels = try XCTUnwrap(FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: sample).graph).legendChipLabels
                for chip in c.forbiddenLegendChips {
                    XCTAssertFalse(labels.contains(chip), "\(c.film) @ \(sample)s: legend must not contain '\(chip)'; got \(labels).")
                }
            }
        }
    }

    @MainActor
    func testGraphCurrentPointStyleAndStatusReflectRegion() throws {
        for c in cases {
            if let sample = c.noCorrectionStatusSample {
                let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: sample)
                XCTAssertEqual(try XCTUnwrap(displayState.graph?.currentPoint).style, .noCorrection, "\(c.film) @ \(sample)s: current point style")
                XCTAssertEqual(displayState.currentResult.statusText, "No correction", "\(c.film) @ \(sample)s: status text")
            }
            if let sample = c.beyondSourceStatusSample {
                let displayState = try FormulaProfileTestSupport.makeDisplayState(film: c.film, meteredExposureSeconds: sample)
                XCTAssertEqual(try XCTUnwrap(displayState.graph?.currentPoint).style, .beyondSourceRange, "\(c.film) @ \(sample)s: current point style")
                XCTAssertEqual(displayState.currentResult.statusText, "Beyond source range", "\(c.film) @ \(sample)s: status text")
            }
        }
    }
}
