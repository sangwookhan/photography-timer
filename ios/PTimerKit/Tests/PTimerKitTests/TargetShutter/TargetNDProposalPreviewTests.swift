// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit

final class TargetNDProposalPreviewTests: XCTestCase {
    func testOnlyChangedProposalsOfferApplyAndWarningIsTextual() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "ko")] {
            for fixture in TargetNDProposalPreview.allCases {
                let state = fixture.displayState(locale: locale)
                XCTAssertEqual(state.canApply, fixture == .ordinary || fixture == .warning)
                XCTAssertEqual(state.warningText != nil, fixture == .warning)
                if let warning = state.warningText { XCTAssertTrue(state.fullText.contains(warning)) }
            }
        }
    }

    func testOrdinaryProposalKeepsRequiredTotalAndSignedResidualDistinct() {
        let state = TargetNDProposalPreview.ordinary.displayState(locale: Locale(identifier: "en"))
        XCTAssertEqual(state.requiredText, "Required ND: 8.7 stops")
        XCTAssertEqual(state.detailText, "ND 6 + 3 · Error −0.3 stop")
        XCTAssertNil(state.warningText)
    }
}
