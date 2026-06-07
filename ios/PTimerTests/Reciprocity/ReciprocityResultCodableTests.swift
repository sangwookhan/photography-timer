import XCTest
import PTimerCore
@testable import PTimer

/// Covers the `ReciprocityResult` Codable surface for the
/// tagged-union representation. Each case round-trips through
/// `JSONEncoder` / `JSONDecoder` and the decoder enforces the
/// (kind, payload) invariant by rejecting mismatched bases.
final class ReciprocityResultCodableTests: XCTestCase {

    // MARK: - Round-trip

    func testQuantifiedRoundTripsThroughTaggedFormat() throws {
        let original: ReciprocityResult = .quantified(
            ReciprocityResult.QuantifiedPayload(
                meteredExposureSeconds: 100,
                correctedExposureSeconds: 437.4,
                metadata: ReciprocityResultMetadata(
                    basis: .formulaDerived,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .withinStatedRange,
                    warningLevel: .none,
                    notes: []
                )
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: data)

        XCTAssertEqual(decoded, original)
        guard case .quantified = decoded else {
            return XCTFail("Expected quantified case, got \(decoded)")
        }
    }

    func testLimitedGuidanceRoundTripsThroughTaggedFormat() throws {
        let original: ReciprocityResult = .limitedGuidance(
            ReciprocityResult.LimitedGuidancePayload(
                meteredExposureSeconds: 4,
                metadata: ReciprocityResultMetadata(
                    basis: .limitedGuidanceNoQuantifiedPrediction,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .beyondLastRepresentativePoint,
                    warningLevel: .note,
                    notes: [
                        ReciprocityPolicyNote(
                            token: .limitedGuidanceContinuationOnly,
                            text: "Only limited guidance is available for this metered exposure."
                        ),
                    ]
                )
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: data)

        XCTAssertEqual(decoded, original)
        guard case .limitedGuidance = decoded else {
            return XCTFail("Expected limitedGuidance case, got \(decoded)")
        }
    }

    func testUnsupportedRoundTripsThroughTaggedFormat() throws {
        let original: ReciprocityResult = .unsupported(
            ReciprocityResult.UnsupportedPayload(
                meteredExposureSeconds: 2_000,
                correctedExposureSeconds: 50_000,
                metadata: ReciprocityResultMetadata(
                    basis: .unsupportedOutOfPolicyRange,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .beyondPolicyLimit,
                    warningLevel: .strongWarning,
                    notes: [
                        ReciprocityPolicyNote(
                            token: .beyondOfficialQuantifiedRange,
                            text: "Manufacturer guidance ends at 480 sec."
                        ),
                    ]
                )
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: data)

        XCTAssertEqual(decoded, original)
        guard case .unsupported = decoded else {
            return XCTFail("Expected unsupported case, got \(decoded)")
        }
    }

    func testUnsupportedRoundTripsWithoutCorrectedExposure() throws {
        let original: ReciprocityResult = .unsupported(
            ReciprocityResult.UnsupportedPayload(
                meteredExposureSeconds: 2_000,
                correctedExposureSeconds: nil,
                metadata: ReciprocityResultMetadata(
                    basis: .unsupportedOutOfPolicyRange,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .beyondPolicyLimit,
                    warningLevel: .strongWarning,
                    notes: []
                )
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Discriminator enforcement

    func testDecoderRejectsPayloadWithMismatchedBasis() {
        let json = #"""
        {
          "kind": "limitedGuidance",
          "payload": {
            "meteredExposureSeconds": 4,
            "metadata": {
              "basis": "officialThresholdNoCorrection",
              "sourceAuthorityImpact": "currentOfficial",
              "rangeStatus": "withinStatedRange",
              "warningLevel": "none",
              "notes": []
            }
          }
        }
        """#
        let data = Data(json.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ReciprocityResult.self, from: data))
    }

    func testDecoderRejectsQuantifiedPayloadWithThresholdMismatch() {
        let json = #"""
        {
          "kind": "quantified",
          "payload": {
            "meteredExposureSeconds": 1,
            "correctedExposureSeconds": 1.5,
            "metadata": {
              "basis": "officialThresholdNoCorrection",
              "sourceAuthorityImpact": "currentOfficial",
              "rangeStatus": "withinStatedRange",
              "warningLevel": "none",
              "notes": []
            }
          }
        }
        """#
        let data = Data(json.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ReciprocityResult.self, from: data))
    }
}
