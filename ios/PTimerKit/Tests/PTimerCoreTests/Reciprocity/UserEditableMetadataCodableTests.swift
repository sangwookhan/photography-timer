import XCTest
@testable import PTimerCore

/// PTIMER-180: the optional film-level `referenceTableFilmID` link
/// must round-trip and must decode as `nil` for legacy payloads that
/// predate the field.
final class UserEditableMetadataCodableTests: XCTestCase {

    func testReferenceTableFilmIDRoundTrips() throws {
        let metadata = UserEditableMetadata(
            customSourceType: .personalTest,
            customManufacturer: "Acme",
            referenceURL: "https://example.com",
            referenceTableFilmID: "custom-table-123"
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(UserEditableMetadata.self, from: data)
        XCTAssertEqual(decoded.referenceTableFilmID, "custom-table-123")
        XCTAssertEqual(decoded, metadata)
    }

    func testLegacyPayloadWithoutLinkDecodesNil() throws {
        let legacyJSON = """
        {
          "tags": [],
          "notes": ["practical test"],
          "customSourceType": "personalTest",
          "referenceURL": "https://example.com"
        }
        """
        let decoded = try JSONDecoder().decode(
            UserEditableMetadata.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(decoded.referenceTableFilmID, "Pre-PTIMER-180 metadata must decode unchanged.")
        XCTAssertEqual(decoded.referenceURL, "https://example.com")
    }
}
