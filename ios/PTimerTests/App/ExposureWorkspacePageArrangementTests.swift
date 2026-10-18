// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// A window change that switches the page arrangement keeps the inputs'
/// and results' views, so state they own — an open Target Shutter entry
/// and its uncommitted value — survives the switch (SHELL-053).
@MainActor
final class ExposureWorkspacePageArrangementTests: XCTestCase {
    func testArrangementRoundTripKeepsInputAndResultState() {
        let model = ArrangementModel()
        let recorder = StateRecorder()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = UIHostingController(rootView: Host(model: model, recorder: recorder))
        window.makeKeyAndVisible()
        settle(window)

        // The user starts editing: the inputs probe's state now holds a draft.
        recorder.inputs.last?.setDraft("1/4")
        settle(window)

        for arrangement in [ExposureWorkspaceArrangement.sideBySide, .singleColumn] {
            model.arrangement = arrangement
            settle(window)
        }

        XCTAssertEqual(Set(recorder.inputs.map(\.id)).count, 1, "The inputs keep their state across the round trip.")
        XCTAssertEqual(Set(recorder.results.map(\.id)).count, 1, "The results keep their state across the round trip.")
        XCTAssertEqual(recorder.inputs.last?.draft, "1/4", "The uncommitted draft survives.")
        XCTAssertGreaterThanOrEqual(recorder.inputs.count, 3, "The inputs rendered in each arrangement.")
    }

    private func settle(_ window: UIWindow) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
    }
}

private final class ArrangementModel: ObservableObject {
    @Published var arrangement: ExposureWorkspaceArrangement = .singleColumn
}

private final class StateRecorder {
    struct Entry {
        let id: UUID
        let draft: String
        let setDraft: (String) -> Void
    }

    var inputs: [Entry] = []
    var results: [Entry] = []
}

private struct Host: View {
    @ObservedObject var model: ArrangementModel
    let recorder: StateRecorder

    var body: some View {
        ExposureWorkspacePageArrangement(arrangement: model.arrangement, resultSpacerMinLength: 8) {
            Text(verbatim: "Header")
        } inputs: {
            StateProbe(arrangement: model.arrangement) { recorder.inputs.append($0) }
        } results: {
            StateProbe(arrangement: model.arrangement) { recorder.results.append($0) }
        }
    }
}

/// Owns state the way TargetShutterSectionView owns its entry sheet, and
/// reports it on every render.
private struct StateProbe: View {
    let arrangement: ExposureWorkspaceArrangement
    let report: (StateRecorder.Entry) -> Void
    @State private var id = UUID()
    @State private var draft = ""

    var body: some View {
        let draftBinding = $draft
        report(StateRecorder.Entry(id: id, draft: draft, setDraft: { draftBinding.wrappedValue = $0 }))
        return Text(verbatim: "\(arrangement) \(draft)")
    }
}
