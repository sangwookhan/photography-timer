// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// PTIMER-212 follow-up: focused coverage for
/// `DisplayStateSnapshot.canonicalize(_:)`'s catalog-provenance-URL
/// redaction, exercised directly on `Swift.dump`-shaped fixture text
/// rather than through a real recorded baseline. Baseline-backed
/// coverage of the same behavior already exists via
/// `DisplayStateSnapshotTests.testLaunchPresetFilmCatalogSnapshot` and
/// `ViewModelDisplayStateBaselineTests`; this suite pins the
/// canonicalization rule itself so a future regression fails here
/// with a direct cause instead of only as a baseline diff.
@MainActor
final class DisplayStateSnapshotCanonicalizationTests: XCTestCase {

    // MARK: - Multi-line `Swift.dump` Optional form

    func testMultilineSourcePageUrlIsRedacted() {
        let original = "https://example.com/original-kodak-source-page"
        let fixture = """
                  ▿ sourcePageUrl: Optional("\(original)")
                    - some: "\(original)"
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertFalse(canonicalized.contains(original))
        XCTAssertTrue(canonicalized.contains("sourcePageUrl"))
    }

    func testMultilineDownloadUrlIsRedacted() {
        let original = "https://example.com/original-kodak-datasheet.pdf"
        let fixture = """
                  ▿ downloadUrl: Optional("\(original)")
                    - some: "\(original)"
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertFalse(canonicalized.contains(original))
        XCTAssertTrue(canonicalized.contains("downloadUrl"))
    }

    // MARK: - Inline Optional form

    func testInlineOptionalFormIsRedacted() {
        let sourceURL = "https://example.com/inline-source-page"
        let downloadURL = "https://example.com/inline-download.pdf"
        let fixture = """
        PTimerCore.ReciprocityProfile(id: "kodak-portra-400-official-threshold", \
        sourcePageUrl: Optional("\(sourceURL)"), downloadUrl: Optional("\(downloadURL)"), \
        sourceNote: Optional("kept-inline-note"))
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertFalse(canonicalized.contains(sourceURL))
        XCTAssertFalse(canonicalized.contains(downloadURL))
        XCTAssertTrue(canonicalized.contains("kept-inline-note"))
    }

    // MARK: - URL value independence

    func testCanonicalizedResultIsIndependentOfURLValue() {
        func fixture(sourceURL: String, downloadURL: String) -> String {
            """
                      ▿ sourcePageUrl: Optional("\(sourceURL)")
                        - some: "\(sourceURL)"
                      ▿ downloadUrl: Optional("\(downloadURL)")
                        - some: "\(downloadURL)"
            """
        }

        let canonicalizedA = DisplayStateSnapshot.canonicalize(fixture(
            sourceURL: "https://business.kodakmoments.com/en-us/product/kodak-professional-tri-x-400-tx",
            downloadURL: "https://business.kodakmoments.com/sites/default/files/tri-x-400-tds.pdf"
        ))
        let canonicalizedB = DisplayStateSnapshot.canonicalize(fixture(
            sourceURL: "https://www.kodakprofessional.com/photographers/film/black-white/kodak-professional-tri-x-films/515",
            downloadURL: "https://kodak.example/a-completely-different-length-of-path/file.pdf"
        ))

        XCTAssertEqual(canonicalizedA, canonicalizedB)
    }

    // MARK: - Non-target provenance fields are preserved

    func testNonTargetProvenanceFieldsArePreserved() {
        let sourceURL = "https://example.com/source-a"
        let downloadURL = "https://example.com/download-a.pdf"
        let fixture = """
                  - publisher: "Kodak"
                  ▿ title: Optional("Kodak Technical Data Sheet")
                    - some: "Kodak Technical Data Sheet"
                  ▿ citation: Optional("Publication E-4050")
                    - some: "Publication E-4050"
                  ▿ sourcePageUrl: Optional("\(sourceURL)")
                    - some: "\(sourceURL)"
                  ▿ downloadUrl: Optional("\(downloadURL)")
                    - some: "\(downloadURL)"
                  ▿ sourceNote: Optional("Official sheet found, but no reciprocity correction data was found.")
                    - some: "Official sheet found, but no reciprocity correction data was found."
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertTrue(canonicalized.contains(#"publisher: "Kodak""#))
        XCTAssertTrue(canonicalized.contains("Kodak Technical Data Sheet"))
        XCTAssertTrue(canonicalized.contains("Publication E-4050"))
        XCTAssertTrue(canonicalized.contains("Official sheet found, but no reciprocity correction data was found."))
        XCTAssertFalse(canonicalized.contains(sourceURL))
        XCTAssertFalse(canonicalized.contains(downloadURL))
    }

    func testPlainTextURLOutsideTargetFieldsIsPreserved() {
        let plainTextURL = "https://example.com/plain-text-note"
        let fixture = """
                  ▿ notes: 1 element
                    - "See \(plainTextURL) for details."
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertEqual(canonicalized, fixture)
        XCTAssertTrue(canonicalized.contains(plainTextURL))
    }

    func testUserEditableMetadataReferenceURLIsPreserved() {
        let referenceURL = "https://example.com/user-provided-reference"
        let fixture = """
                  ▿ referenceURL: Optional("\(referenceURL)")
                    - some: "\(referenceURL)"
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertEqual(canonicalized, fixture)
        XCTAssertTrue(canonicalized.contains(referenceURL))
    }

    // MARK: - `nil` URL fields are unaffected

    func testNilURLFieldsAreUnaffected() {
        let fixture = """
                  - sourcePageUrl: nil
                  - downloadUrl: nil
        """

        let canonicalized = DisplayStateSnapshot.canonicalize(fixture)

        XCTAssertEqual(canonicalized, fixture)
    }
}
