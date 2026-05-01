import XCTest
@testable import PTimer

/// Covers the `ReciprocityResult` Codable surface for the tagged-union
/// representation.
///
/// Two responsibilities:
/// 1. **Round-trip the new tagged format.** `JSONEncoder().encode(...)`
///    now writes `{ "kind": ..., "payload": { ... } }`. Decoding the
///    same bytes must reproduce the original value (one case per
///    enum branch).
/// 2. **Backward-compat decoding.** Persisted snapshots from before
///    the migration use the legacy 7-field layout
///    (`meteredExposureSeconds` / `correctedExposureSeconds` /
///    `hasCalculatedExposureTime` / `metadata`). The decoder must
///    accept these and reconstruct the matching enum case so timer
///    snapshots persisted by older builds keep loading.
final class ReciprocityResultCodableTests: XCTestCase {

    // MARK: - New tagged-format round-trip

    func testQuantifiedRoundTripsThroughTaggedFormat() throws {
        let original: ReciprocityResult = .quantified(
            ReciprocityResult.QuantifiedPayload(
                meteredExposureSeconds: 10,
                correctedExposureSeconds: 50,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .exactTablePoint,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .withinStatedRange,
                    warningLevel: .none,
                    notes: [
                        ReciprocityPolicyNote(
                            token: .exactManufacturerTablePoint,
                            text: "Returned from an explicit representative table point."
                        )
                    ]
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

    func testAdvisoryOnlyRoundTripsThroughTaggedFormat() throws {
        let original: ReciprocityResult = .advisoryOnly(
            ReciprocityResult.AdvisoryOnlyPayload(
                meteredExposureSeconds: 4,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .advisoryOnlyBeyondOfficialRange,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .beyondLastRepresentativePoint,
                    warningLevel: .note,
                    notes: [
                        ReciprocityPolicyNote(
                            token: .advisoryContinuationOnly,
                            text: "Only advisory continuation is available for this metered exposure."
                        )
                    ]
                )
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: data)

        XCTAssertEqual(decoded, original)
        guard case .advisoryOnly = decoded else {
            return XCTFail("Expected advisoryOnly case, got \(decoded)")
        }
    }

    func testUnsupportedRoundTripsThroughTaggedFormat() throws {
        let original: ReciprocityResult = .unsupported(
            ReciprocityResult.UnsupportedPayload(
                meteredExposureSeconds: 1_000,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .unsupportedOutOfPolicyRange,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .beyondPolicyLimit,
                    warningLevel: .strongWarning,
                    notes: [
                        ReciprocityPolicyNote(
                            token: .unsupportedByPolicy,
                            text: "No supported reciprocity policy path matched this metered exposure."
                        )
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

    func testNewTaggedEncoderEmitsKindAndPayloadDiscriminator() throws {
        let result: ReciprocityResult = .quantified(
            ReciprocityResult.QuantifiedPayload(
                meteredExposureSeconds: 10,
                correctedExposureSeconds: 50,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .exactTablePoint,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .withinStatedRange,
                    warningLevel: .none,
                    notes: []
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(result)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(
            json.contains("\"kind\":\"quantified\""),
            "Expected new tagged format with kind discriminator. Got: \(json)"
        )
        XCTAssertTrue(
            json.contains("\"payload\""),
            "Expected new tagged format with payload key. Got: \(json)"
        )
    }

    // MARK: - Backward-compat decoding (legacy 7-field shape)

    func testDecodesLegacyQuantifiedShapeAsQuantifiedCase() throws {
        let legacyJSON = """
        {
          "meteredExposureSeconds": 10,
          "correctedExposureSeconds": 50,
          "hasCalculatedExposureTime": true,
          "metadata": {
            "basis": "exactTablePoint",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "withinStatedRange",
            "warningLevel": "none",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: Data(legacyJSON.utf8))

        guard case let .quantified(payload) = decoded else {
            return XCTFail("Expected quantified case, got \(decoded)")
        }
        XCTAssertEqual(payload.meteredExposureSeconds, 10)
        XCTAssertEqual(payload.correctedExposureSeconds, 50)
        XCTAssertEqual(payload.metadata.basis, .exactTablePoint)
    }

    func testDecodesLegacyAdvisoryOnlyShapeAsAdvisoryOnlyCase() throws {
        let legacyJSON = """
        {
          "meteredExposureSeconds": 4,
          "hasCalculatedExposureTime": false,
          "metadata": {
            "basis": "advisoryOnlyBeyondOfficialRange",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "beyondLastRepresentativePoint",
            "warningLevel": "note",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: Data(legacyJSON.utf8))

        guard case let .advisoryOnly(payload) = decoded else {
            return XCTFail("Expected advisoryOnly case, got \(decoded)")
        }
        XCTAssertEqual(payload.meteredExposureSeconds, 4)
        XCTAssertEqual(payload.metadata.basis, .advisoryOnlyBeyondOfficialRange)
    }

    func testDecodesLegacyUnsupportedShapeAsUnsupportedCase() throws {
        let legacyJSON = """
        {
          "meteredExposureSeconds": 1000,
          "hasCalculatedExposureTime": false,
          "metadata": {
            "basis": "unsupportedOutOfPolicyRange",
            "sourceAuthorityImpact": "currentOfficial",
            "rangeStatus": "beyondPolicyLimit",
            "warningLevel": "strongWarning",
            "notes": [],
            "referencedRows": null
          }
        }
        """

        let decoded = try JSONDecoder().decode(ReciprocityResult.self, from: Data(legacyJSON.utf8))

        guard case let .unsupported(payload) = decoded else {
            return XCTFail("Expected unsupported case, got \(decoded)")
        }
        XCTAssertEqual(payload.meteredExposureSeconds, 1_000)
        XCTAssertEqual(payload.metadata.basis, .unsupportedOutOfPolicyRange)
    }

    // MARK: - Legacy-shape encoder adapter

    func testLegacyShapeAdapterReproducesPreMigrationLayout() throws {
        let result: ReciprocityResult = .quantified(
            ReciprocityResult.QuantifiedPayload(
                meteredExposureSeconds: 10,
                correctedExposureSeconds: 50,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .exactTablePoint,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .withinStatedRange,
                    warningLevel: .none,
                    notes: []
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try result.legacyShapeEncoded(using: encoder)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"hasCalculatedExposureTime\":true"))
        XCTAssertTrue(json.contains("\"meteredExposureSeconds\":10"))
        XCTAssertTrue(json.contains("\"correctedExposureSeconds\":50"))
        XCTAssertFalse(json.contains("\"kind\""))
        XCTAssertFalse(json.contains("\"payload\""))
    }

    func testLegacyShapeAdapterOmitsCorrectedExposureWhenNil() throws {
        let result: ReciprocityResult = .advisoryOnly(
            ReciprocityResult.AdvisoryOnlyPayload(
                meteredExposureSeconds: 4,
                metadata: ReciprocityCalculationPolicyResultMetadata(
                    basis: .advisoryOnlyBeyondOfficialRange,
                    sourceAuthorityImpact: .currentOfficial,
                    rangeStatus: .beyondLastRepresentativePoint,
                    warningLevel: .note,
                    notes: []
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try result.legacyShapeEncoded(using: encoder)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"hasCalculatedExposureTime\":false"))
        XCTAssertFalse(json.contains("\"correctedExposureSeconds\""))
    }
}
