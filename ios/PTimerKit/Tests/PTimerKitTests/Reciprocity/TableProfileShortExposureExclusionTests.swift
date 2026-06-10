import XCTest
import PTimerKit
import PTimerCore

/// T-MAX 100 is a table-log-log reciprocity profile. Its archetype-shared
/// behavior — table rule parameters and anchors (1→1.2599, 10→15,
/// 100→200), the 0.1 s no-correction threshold and nominal tolerance,
/// table-derived / beyond-source classification, source-evidence rows,
/// and Details / graph markers — is verified across films in
/// `TableProfileSourceDataContractTests` and
/// `TableLogLogReciprocityContractTests`.
///
/// This suite holds only T-MAX 100's genuinely film-specific behavior:
/// the 1/10,000 sec short-exposure guidance is excluded from the
/// long-exposure table and archived on `profile.notes` rather than
/// emitted as a table point. The film is the `profileUnderTest()` constant,
/// so no film name appears in a test-function name.
final class TableProfileShortExposureExclusionTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    // MARK: - Threshold boundary (0.1 sec, inclusive)
    // IMPORTANT (PTIMER-168): noCorrectionThroughSeconds == 0.1. The no-correction
    // band ends at 1/10 sec; 1 sec is now a corrected anchor (≈1.2599 sec).

    // MARK: - Table range (> 0.1 sec, up to 100 sec)

    // MARK: - Short-exposure guidance is excluded from the long-exposure table

    func testShort1Over10000ExposureIsNotALongExposureTablePoint() throws {
        // 1/10000 sec sits well below noCorrectionThroughSeconds (0.1 sec).
        // The 1/10000 sec +1/3 stop guidance lives only as a profile-level
        // note; it must NOT produce a table correction.
        let profile = try profileUnderTest()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1.0 / 10_000.0)
        XCTAssertEqual(
            result.metadata.basis,
            .officialThresholdNoCorrection,
            "1/10000 sec sits inside the no-correction band; the table rule must not fire."
        )
        XCTAssertEqual(
            result.correctedExposureSeconds ?? -1,
            1.0 / 10_000.0,
            accuracy: 1e-9,
            "1/10000 sec must return the identity corrected exposure."
        )

        let shortExposureMetered = 1.0 / 10_000.0
        for evidence in profile.sourceEvidence {
            if case let .exactSeconds(seconds) = evidence.meteredExposure {
                XCTAssertGreaterThan(
                    seconds,
                    shortExposureMetered * 10,
                    "1/10000 sec short-exposure row must not be added to long-exposure sourceEvidence; got entry at \(seconds) sec."
                )
            }
        }
    }

    func testShortExposureGuidanceIsPreservedAtCatalogLevelOnly() throws {
        // The published 1/10,000 sec +1/3 stop short-exposure guidance
        // is preserved on `profile.notes` for source fidelity. It is not
        // rendered in the Details surface; a future ticket can wire it through.
        let profile = try profileUnderTest()
        let notes = profile.notes.joined(separator: "\n").lowercased()
        XCTAssertTrue(
            notes.contains("1/10,000") || notes.contains("short-exposure"),
            "profile.notes must keep the 1/10000 sec short-exposure +1/3 stop guidance archived; got notes: \(profile.notes)"
        )
    }

    func testProfileNotesDocumentNoCorrectionRangeAndShortExposureExclusion() throws {
        // Two catalog-level notes are required:
        // 1. No adjustment from 1/1,000 to 1/10 sec.
        // 2. The 1/10,000 sec short-exposure +1/3 stop is excluded from
        //    the long-exposure table (the note now says "table", not "formula").
        let profile = try profileUnderTest()
        XCTAssertGreaterThanOrEqual(profile.notes.count, 2,
            "T-MAX 100 must carry at least two profile-level notes.")

        let joined = profile.notes.joined(separator: "\n").lowercased()
        XCTAssertTrue(
            joined.contains("table") || joined.contains("interpolation"),
            "At least one note must reference the table, confirming the long-exposure calculation model."
        )
        XCTAssertTrue(
            joined.contains("1/10,000") || joined.contains("short-exposure"),
            "A note must document the 1/10000 sec short-exposure guidance exclusion."
        )
    }

    // MARK: - Beyond the published source range (> 100 sec)

    // MARK: - Source evidence preservation

    // MARK: - UI surfacing

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "T-MAX 100",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func profileUnderTest() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "T-MAX 100")
    }
}
