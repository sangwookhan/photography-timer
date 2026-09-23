// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit

/// FILTER-SET-001: the one decision every exit path of the name field
/// (Submit, focus loss, leaving the screen) makes with its draft.
final class FilterSetRenameCommitTests: XCTestCase {
    func testChangedDraftRenamesToTheTrimmedName() {
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: "  Lee holder ", currentName: "Lee"), .rename("Lee holder"))
    }

    func testUnchangedDraftDoesNothing() {
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: "Lee", currentName: "Lee"), .none)
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: " Lee\n", currentName: "Lee"), .none, "Whitespace-only differences are not a rename.")
    }

    func testBlankDraftRestoresThePriorName() {
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: "   ", currentName: "Lee"), .restore("Lee"))
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: "", currentName: "Lee"), .restore("Lee"))
    }

    func testDeletedSetIsANoOpWhateverTheDraft() {
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: "Renamed", currentName: nil), .none)
        XCTAssertEqual(FilterSetRenameCommit.decide(draft: "", currentName: nil), .none)
    }
}
