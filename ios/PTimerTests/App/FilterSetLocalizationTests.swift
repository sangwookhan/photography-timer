// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimer

/// FILTER-A11Y-003: the Filter Set strings that reach the user through
/// speech or the status region exist in both English and Korean in the
/// compiled catalog. Read from the app bundle's per-locale tables so a
/// missing or untranslated key fails here instead of on a device.
final class FilterSetLocalizationTests: XCTestCase {
    private let keys = [
        "Empty filter wheel removed",
        "%lld empty filter wheels removed",
        "No more filters in this direction",
        "Add filter",
        "Manage Filter Sets",
        "Filter Sets",
        "Filter not available",
        "Already mounted on this camera",
        "Exceeds 30 stops",
        "Empty · no filter mounted",
        "Filter Set name",
        "Finish Editing",
    ]

    func testFilterSetStringsHaveEnglishAndKoreanValues() throws {
        for key in keys {
            // English is the catalog's source language: its value is the
            // key itself, so the compiled bundle carries no `en.lproj`
            // override and the main-bundle lookup resolves to the key.
            let english = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            let korean = try localizedValue(key, locale: "ko")
            XCTAssertEqual(english, key, "English value for \(key)")
            XCTAssertNotEqual(korean, "MISSING", "Korean entry missing for \(key)")
            XCTAssertNotEqual(korean, key, "Korean entry untranslated for \(key)")
        }
    }

    func testRemovedRemoveActionStringIsGone() throws {
        XCTAssertEqual(try localizedValue("Remove empty filter", locale: "ko"), "MISSING", "The container-level Remove action and its string were removed.")
    }

    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"), "\(locale).lproj in the app bundle")
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: "MISSING", table: nil)
    }
}
