// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class TimerWorkspaceListEntryTests: XCTestCase {
    @MainActor
    func testRepeatMovesSamePausedEntryDownAndInsertsOneFreshTimer() throws {
        var now = Date(timeIntervalSince1970: 100)
        let manager = RuntimeBackedTimerManaging(dateProvider: { now })
        let model = makeModel(manager)
        let sourceID = try XCTUnwrap(model.startTimer(duration: 600, name: "Source", basisSummary: "Manual"))
        let otherID = try XCTUnwrap(model.startTimer(duration: 900, name: "Other", basisSummary: "Manual"))
        now += 10
        model.pauseTimer(id: sourceID)
        let source = try XCTUnwrap(model.timers.first { $0.id == sourceID })
        let before = entries(model)
        let oldRow = try XCTUnwrap(before.first { $0.id == "timer:\(sourceID.uuidString)" })

        let newID = try XCTUnwrap(model.startTimer(cloning: source))
        let after = entries(model)
        let newIDs = Set(after.map(\.id)).subtracting(before.map(\.id))
        let insertedTimers = newIDs.filter { $0.hasPrefix("timer:") }
        XCTAssertEqual(insertedTimers, ["timer:\(newID.uuidString)"])
        XCTAssertEqual(Set(after.map(\.id)).count, after.count)
        XCTAssertTrue(after.contains { $0.id == oldRow.id })
        XCTAssertGreaterThan(try XCTUnwrap(after.firstIndex { $0.id == oldRow.id }),
                             try XCTUnwrap(before.firstIndex { $0.id == oldRow.id }))
        let timerItems = after.compactMap { entry -> BottomSheetLargeItem? in
            if case .timer(let item) = entry { return item }
            return nil
        }
        XCTAssertEqual(timerItems.map(\.id), [newID, otherID, sourceID])
        XCTAssertEqual(timerItems.last?.status, .canceled)
        XCTAssertEqual(timerItems.last?.cancellationReasonText, "New timer")
        XCTAssertTrue(after.contains(.header(title: TimerWorkspaceSection.historyTitle, isHistory: true)))
    }

    @MainActor
    func testCountdownTicksChangeContentButNotStructuralAnimationIdentity() throws {
        var now = Date(timeIntervalSince1970: 100)
        let manager = RuntimeBackedTimerManaging(dateProvider: { now })
        let model = makeModel(manager)
        let id = try XCTUnwrap(model.startTimer(duration: 600, name: "Source", basisSummary: "Manual"))
        model.pauseTimer(id: id)
        let before = entries(model)
        now += 1
        manager.tick(now: now)
        let after = entries(model)
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
    }

    @MainActor
    func testExistingHistoryHeaderAndTimerKeepTheirIdentitiesOnAnotherRepeat() throws {
        let manager = RuntimeBackedTimerManaging(dateProvider: { Date(timeIntervalSince1970: 100) })
        let model = makeModel(manager)
        let firstID = try XCTUnwrap(model.startTimer(duration: 600, name: "First", basisSummary: "Manual"))
        model.pauseTimer(id: firstID)
        let first = try XCTUnwrap(model.timers.first)
        let secondID = try XCTUnwrap(model.startTimer(cloning: first))
        model.pauseTimer(id: secondID)
        let before = entries(model)
        let second = try XCTUnwrap(model.timers.first { $0.id == secondID })
        let thirdID = try XCTUnwrap(model.startTimer(cloning: second))
        let after = entries(model)
        XCTAssertEqual(Set(after.map(\.id)).subtracting(before.map(\.id)), ["timer:\(thirdID.uuidString)"])
        XCTAssertTrue(Set(before.map(\.id)).isSubset(of: Set(after.map(\.id))))
    }

    @MainActor
    private func makeModel(_ manager: any TimerManaging) -> TimerWorkspaceModel {
        TimerWorkspaceModel(timerManager: manager, metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
                            defaultName: { _ in "Timer" })
    }

    @MainActor
    private func entries(_ model: TimerWorkspaceModel) -> [TimerWorkspaceListEntry] {
        let snapshot = BottomSheetWorkspaceSnapshot.make(
            from: model.timers, formatRemaining: { BottomSheetWorkspaceSnapshot.compactDurationText($0) },
            formatShutter: { String($0) }, ndNotationMode: .stops,
            timeContext: { _ in "Now" }, compactCompletedSupplementaryText: { _ in nil }
        )
        return TimerWorkspaceListEntry.make(from: snapshot.sections)
    }
}
