import XCTest
@testable import PTimer

/// Locks the pre-enum JSON shape of every reciprocity policy result
/// produced by the evaluator across the expanded golden fixture.
/// `ReciprocityResult` writes a tagged-union format by default; this
/// harness exercises `legacyShapeEncoded(using:)` to keep proving
/// compatibility with the original 7-field JSON layout.
///
/// Why a single concatenated trace?
/// - One snapshot file = one diff.
/// - Cases are stable in fixture order; the harness emits explicit
///   `=== case N ===` separators so a regression localizes cleanly.
///
/// Why `.sortedKeys + .prettyPrinted`?
/// - `.sortedKeys` is required for cross-platform determinism;
///   without it `JSONEncoder` may emit different key orders on
///   different OS versions.
/// - `.prettyPrinted` makes the recorded baseline diff-friendly.
/// - The adapter emits the legacy 7-field layout:
///   `correctedExposureSeconds` (nullable, omitted when nil via
///   `encodeIfPresent`), `hasCalculatedExposureTime`, and the nested
///   `metadata` block. The adapter must continue to reproduce these
///   bytes exactly.
@MainActor
final class ReciprocityResultLegacyShapeBaselineTests: XCTestCase {

    func testReciprocityPolicyLegacyShapeBaseline() throws {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        let cases = try Self.loadFixtureCases()

        XCTAssertGreaterThanOrEqual(
            cases.count,
            70,
            "Expected at least 70 fixture cases. Found \(cases.count)."
        )

        let encoder = Self.makeBaselineEncoder()
        var trace = ""

        for (index, fixtureCase) in cases.enumerated() {
            let profile = try Self.profile(for: fixtureCase)
            let result = evaluator.evaluate(
                profile: profile,
                meteredExposureSeconds: fixtureCase.meteredSeconds
            )

            let encoded = try result.legacyShapeEncoded(using: encoder)
            guard let json = String(data: encoded, encoding: .utf8) else {
                XCTFail("Result encode produced non-UTF8 bytes for case \(index)")
                return
            }

            trace.append("=== case \(index): \(fixtureCase.profileId) | metered=\(fixtureCase.meteredSeconds) | \(fixtureCase.description) ===\n")
            trace.append(json)
            trace.append("\n\n")
        }

        DisplayStateSnapshot.assertText(
            trace,
            named: "reciprocity-policy-legacy-shape-baseline"
        )
    }

    // MARK: - Fixture loading

    private struct FixtureRoot: Decodable {
        let cases: [FixtureCase]
    }

    private struct FixtureCase: Decodable {
        let filmName: String
        let filmId: String
        let profileId: String
        let description: String
        let meteredSeconds: Double
    }

    private static func loadFixtureCases() throws -> [FixtureCase] {
        let url = fixtureURL()
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureRoot.self, from: data).cases
    }

    /// Resolves `shared/test-fixtures/reciprocity-golden.json` from
    /// the repository root by walking up from this file's directory.
    /// Mirrors `DisplayStateSnapshot.locateSnapshotsRoot`'s strategy
    /// so the harness works regardless of build directory layout.
    private static func fixtureURL(file: StaticString = #filePath) -> URL {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        var current = testFileURL.deletingLastPathComponent()
        while current.pathComponents.count > 1 {
            if current.lastPathComponent == "PTimerTests" {
                return current
                    .deletingLastPathComponent()
                    .appendingPathComponent("shared", isDirectory: true)
                    .appendingPathComponent("test-fixtures", isDirectory: true)
                    .appendingPathComponent("reciprocity-golden.json")
            }
            current = current.deletingLastPathComponent()
        }
        // Fallback: relative to test file's directory.
        return testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("../../shared/test-fixtures/reciprocity-golden.json")
    }

    // MARK: - Profile resolution

    /// Maps each fixture case's `profileId` to a concrete
    /// `ReciprocityProfile` from `ReciprocityPolicyScenarioFactory`.
    /// All synthetic profiles (`synthetic-*`, archival/secondary
    /// variants) live alongside the canonical ones in the factory so
    /// the harness has a single source of truth for inputs.
    private static func profile(for fixtureCase: FixtureCase) throws -> ReciprocityProfile {
        switch fixtureCase.profileId {
        case "kodak-tri-x-official-table":
            return ReciprocityPolicyScenarioFactory.triXProfile()
        case "fujifilm-velvia-official-table":
            return ReciprocityPolicyScenarioFactory.velviaProfile()
        case "kodak-portra-official-threshold":
            return ReciprocityPolicyScenarioFactory.portraOfficialProfile()
        case "ilford-hp5-plus-official-formula":
            return ReciprocityPolicyScenarioFactory.hp5FormulaProfile()
        case "kodak-portra-secondary-table":
            return ReciprocityPolicyScenarioFactory.portraSecondaryProfile()
        case "agfa-archival-official":
            return ReciprocityPolicyScenarioFactory.agfaArchivalProfile()
        case "custom-user-profile":
            return ReciprocityPolicyScenarioFactory.customUserDefinedProfile()
        case "synthetic-formula-bounded-30s":
            return ReciprocityPolicyScenarioFactory.formulaBoundedProfile()
        case "synthetic-tri-x-archival":
            return ReciprocityPolicyScenarioFactory.triXArchivalProfile()
        case "synthetic-tri-x-secondary":
            return ReciprocityPolicyScenarioFactory.triXSecondaryProfile()
        case "synthetic-tri-x-user-defined":
            return ReciprocityPolicyScenarioFactory.triXUserDefinedProfile()
        case "synthetic-hp5-archival":
            return ReciprocityPolicyScenarioFactory.hp5ArchivalFormulaProfile()
        case "synthetic-hp5-user-defined":
            return ReciprocityPolicyScenarioFactory.hp5UserDefinedFormulaProfile()
        case "synthetic-velvia-archival":
            return ReciprocityPolicyScenarioFactory.velviaArchivalProfile()
        case "synthetic-portra-archival-advisory":
            return ReciprocityPolicyScenarioFactory.portraArchivalAdvisoryProfile()
        case "synthetic-portra-secondary-advisory":
            return ReciprocityPolicyScenarioFactory.portraSecondaryAdvisoryProfile()
        case "synthetic-portra-user-defined-advisory":
            return ReciprocityPolicyScenarioFactory.portraUserDefinedAdvisoryProfile()
        default:
            throw FixtureError.unknownProfileId(fixtureCase.profileId)
        }
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case unknownProfileId(String)

        var description: String {
            switch self {
            case let .unknownProfileId(profileId):
                return "Unknown profileId in fixture: \(profileId). " +
                    "Add a corresponding factory in ReciprocityPolicyScenarioFactory."
            }
        }
    }

    // MARK: - Encoder

    /// Deterministic JSON encoder shared across the baseline. Sorted
    /// keys + pretty printing make the snapshot stable across OS
    /// versions and trivially diffable.
    private static func makeBaselineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
}
