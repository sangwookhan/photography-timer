// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

/// PTIMER-84 follow-up: covers
/// `CustomFilmEditorPreviewPresenter.diagnose(form:)`, the
/// recovery-oriented diagnostic surface the preview card uses to
/// swap row-level "Invalid formula result" repetition for a single
/// reason-aware message.
final class CustomFilmEditorPreviewDiagnoseTests: XCTestCase {

    /// diagnose(form:) maps each form state to its recovery reason
    /// (nil for a valid form, the neutral .emptyExponent for a blank
    /// new form, and a field-specific reason for each invalid field).
    func test_diagnose_returnsExpectedReasonPerFormState() {
        typealias Reason = CustomFilmEditorPreviewPresenter.InvalidReason
        struct Case {
            let name: String
            let build: () -> CustomFilmEditorFormState
            let expected: Reason?
        }
        let cases: [Case] = [
            Case(name: "valid", build: {
                CustomFilmEditorFormState(
                    exponentText: "1.30", baseTmText: "1", baseTcText: "1",
                    offsetSecondsText: "", noCorrectionThroughText: "1", validThroughText: ""
                )
            }, expected: nil),
            Case(name: "empty exponent (neutral)", build: { CustomFilmEditorFormState() }, expected: .emptyExponent),
            Case(name: "invalid exponent", build: { CustomFilmEditorFormState(exponentText: "abc") }, expected: .invalidExponent),
            Case(name: "invalid baseTm", build: {
                CustomFilmEditorFormState(exponentText: "1.30", baseTmText: "abc")
            }, expected: .invalidBaseTm),
            Case(name: "invalid baseTc", build: {
                CustomFilmEditorFormState(exponentText: "1.30", baseTcText: "abc")
            }, expected: .invalidBaseTc),
            Case(name: "invalid offset", build: {
                CustomFilmEditorFormState(exponentText: "1.30", offsetSecondsText: "-")
            }, expected: .invalidOffset),
            Case(name: "source range below no-correction", build: {
                CustomFilmEditorFormState(exponentText: "1.30", noCorrectionThroughText: "1", validThroughText: "0.5")
            }, expected: .invalidSourceRange),
        ]
        for c in cases {
            XCTAssertEqual(
                CustomFilmEditorPreviewPresenter.diagnose(form: c.build()),
                c.expected,
                "[\(c.name)] diagnose reason"
            )
        }
    }

    func test_displayMessage_usesSymbolAnchoredVocabulary() {
        // Anchor reasons use the same symbol-anchored vocabulary
        // (`Tm₀`, `Tc₀`) the editor rows use, so the preview's
        // recovery panel reads consistently with the row labels
        // the photographer just left.
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.InvalidReason
                .invalidBaseTm.displayMessage,
            "Tm₀ must be > 0."
        )
        XCTAssertEqual(
            CustomFilmEditorPreviewPresenter.InvalidReason
                .invalidBaseTc.displayMessage,
            "Tc₀ must be > 0."
        )
    }
}
