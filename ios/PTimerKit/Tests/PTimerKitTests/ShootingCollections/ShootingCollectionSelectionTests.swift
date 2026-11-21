// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class ShootingCollectionSelectionTests: XCTestCase {
    func testMarkerComputationDoesNotAutomaticallySelectAnything() {
        let anchor = timer(at: 0)
        let nearby = timer(at: 100)
        var selection = ShootingCollectionSelection()
        XCTAssertTrue(selection.suggestedIDs(from: [anchor, nearby], collectedIDs: []).isEmpty)
        selection.toggle(anchor.id)
        XCTAssertEqual(selection.suggestedIDs(from: [anchor, nearby], collectedIDs: []), [nearby.id])
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
    }

    func testWindowIncludesBothThirtyMinuteBoundariesAndExcludesBeyondThem() {
        let anchor = timer(at: 0)
        let before = timer(at: -1_800)
        let after = timer(at: 1_800)
        let outsideBefore = timer(at: -1_800.001)
        let outsideAfter = timer(at: 1_800.001)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        let history = [outsideAfter, after, anchor, before, outsideBefore]
        XCTAssertEqual(selection.suggestedIDs(from: history, collectedIDs: []), [before.id, after.id])
    }

    func testActualTimeWindowWorksAcrossMidnight() {
        let anchor = timer(at: 86_100)
        let afterMidnight = timer(at: 86_700)
        let previousDaySameClock = timer(at: -300)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        XCTAssertEqual(selection.suggestedIDs(from: [anchor, afterMidnight, previousDaySameClock], collectedIDs: []), [afterMidnight.id])
    }

    func testRecommendationsExcludeCollectedSelectedAndActiveEvents() {
        let anchor = timer(at: 0)
        let selected = timer(at: 100)
        let collected = timer(at: 200)
        let canceled = timer(at: 300, status: .canceled)
        let running = timer(at: 400, status: .running)
        let paused = timer(at: 500, status: .paused)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        selection.toggle(selected.id)
        let history = [anchor, selected, collected, canceled, running, paused]
        XCTAssertEqual(selection.suggestedIDs(from: history, collectedIDs: [collected.id]), [canceled.id])
    }

    func testConfirmedSelectionDoesNotChainWindowAndKeepsExistingSelection() {
        let anchor = timer(at: 0)
        let nearby = timer(at: 1_200)
        let chained = timer(at: 2_400)
        let manuallySelected = timer(at: 9_000)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        selection.toggle(manuallySelected.id)
        let history = [anchor, nearby, chained, manuallySelected]
        confirmAll(&selection, from: history, collectedIDs: [])
        XCTAssertEqual(selection.selectedIDs, [anchor.id, nearby.id, manuallySelected.id])
        XCTAssertTrue(selection.suggestedIDs(from: history, collectedIDs: []).isEmpty)
        confirmAll(&selection, from: history, collectedIDs: [])
        XCTAssertFalse(selection.selectedIDs.contains(chained.id))
    }

    func testRemovingAnchorUsesFirstRemainingSelectionAndClearingRemovesMarker() {
        let first = timer(at: 0)
        let second = timer(at: 9_000)
        let firstNeighbor = timer(at: 300)
        let secondNeighbor = timer(at: 9_300)
        let history = [first, second, firstNeighbor, secondNeighbor]
        var selection = ShootingCollectionSelection()
        selection.toggle(first.id)
        selection.toggle(second.id)
        XCTAssertEqual(selection.suggestedIDs(from: history, collectedIDs: []), [firstNeighbor.id])
        selection.toggle(first.id)
        XCTAssertEqual(selection.suggestedIDs(from: history, collectedIDs: []), [secondNeighbor.id])
        selection.toggle(second.id)
        XCTAssertTrue(selection.selectedIDs.isEmpty)
        XCTAssertTrue(selection.suggestedIDs(from: history, collectedIDs: []).isEmpty)
    }

    func testConfirmationUsesCurrentEligibilityAndAllowsIndividualDeselect() {
        let anchor = timer(at: 0)
        let nearby = timer(at: 100)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        XCTAssertEqual(selection.suggestedIDs(from: [anchor, nearby], collectedIDs: []), [nearby.id])
        confirmAll(&selection, from: [anchor, nearby], collectedIDs: [nearby.id])
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
        confirmAll(&selection, from: [anchor, nearby], collectedIDs: [])
        XCTAssertEqual(selection.selectedIDs, [anchor.id, nearby.id])
        selection.toggle(nearby.id)
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
        XCTAssertTrue(selection.suggestedIDs(from: [anchor], collectedIDs: []).isEmpty)
    }

    func testCameraAndFilmDifferencesDoNotExcludeNearbyEventsOrDuplicateCounts() {
        let anchor = timer(at: 0, camera: .camera1, film: "HP5")
        let otherCamera = timer(at: 100, camera: .camera2, film: "Portra")
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        XCTAssertEqual(selection.suggestedIDs(from: [anchor, otherCamera, otherCamera], collectedIDs: []), [otherCamera.id])
    }

    @MainActor
    func testSuggestionsAreTransientAndOnlyExplicitCreateCommitsCollection() throws {
        let archive = ShootingCollectionModel(store: NoOpShootingCollectionStore())
        let history = [timer(at: 0), timer(at: 100)]
        var selection = ShootingCollectionSelection()
        selection.toggle(history[0].id)
        confirmAll(&selection, from: history, collectedIDs: archive.collectedEventIDs)
        XCTAssertTrue(archive.collections.isEmpty)
        _ = try archive.create(from: history.filter { selection.selectedIDs.contains($0.id) }, at: Date(), timeZone: .gmt).get()
        XCTAssertEqual(archive.collections.first?.records.count, 2)
        XCTAssertEqual(archive.collectedEventIDs, selection.selectedIDs)
        XCTAssertTrue(selection.suggestedIDs(from: history, collectedIDs: archive.collectedEventIDs).isEmpty)
    }

    func testPreviewIsReadOnlyAndConfirmationCanAddOnlyAChosenSubset() throws {
        let anchor = timer(at: 0)
        let first = timer(at: 100)
        let second = timer(at: 200)
        let history = [anchor, first, second]
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        let preview = try XCTUnwrap(selection.suggestion(from: history, collectedIDs: []))
        XCTAssertEqual(selection.selectedIDs, [anchor.id], "Opening/closing a preview commits nothing.")
        XCTAssertEqual(preview.candidates.map(\.id), [first.id, second.id])
        selection.confirmSuggestion(preview, choosing: [], from: history, collectedIDs: [])
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
        selection.confirmSuggestion(preview, choosing: [second.id], from: history, collectedIDs: [])
        XCTAssertEqual(selection.selectedIDs, [anchor.id, second.id])
        XCTAssertEqual(selection.suggestedIDs(from: history, collectedIDs: []), [first.id])
    }

    func testConfirmationRejectsUnseenAndNowIneligibleCandidates() throws {
        let anchor = timer(at: 0)
        let original = timer(at: 100)
        let laterArrival = timer(at: 200)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        let preview = try XCTUnwrap(selection.suggestion(from: [anchor, original], collectedIDs: []))
        selection.confirmSuggestion(
            preview, choosing: [original.id, laterArrival.id],
            from: [anchor, original, laterArrival], collectedIDs: [original.id]
        )
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
        selection.confirmSuggestion(preview, choosing: [original.id], from: [anchor], collectedIDs: [])
        XCTAssertEqual(selection.selectedIDs, [anchor.id])
    }

    func testChangedAnchorInvalidatesAnEarlierPreview() throws {
        let anchor = timer(at: 0)
        let nearby = timer(at: 100)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        let preview = try XCTUnwrap(selection.suggestion(from: [anchor, nearby], collectedIDs: []))
        selection.toggle(anchor.id)
        selection.toggle(nearby.id)
        selection.confirmSuggestion(preview, choosing: [anchor.id, nearby.id], from: [anchor, nearby], collectedIDs: [])
        XCTAssertEqual(selection.selectedIDs, [nearby.id])
    }

    func testReopeningPreviewReflectsManualChangesAndRelativeTimesHaveDirection() throws {
        let anchor = timer(at: 0)
        let before = timer(at: -300)
        let after = timer(at: 600)
        var selection = ShootingCollectionSelection()
        selection.toggle(anchor.id)
        let first = try XCTUnwrap(selection.suggestion(from: [anchor, before, after], collectedIDs: []))
        selection.toggle(before.id)
        let reopened = try XCTUnwrap(selection.suggestion(from: [anchor, before, after], collectedIDs: []))
        XCTAssertEqual(reopened.candidates.map(\.id), [after.id])
        XCTAssertEqual(first.candidates.map(\.id), [before.id, after.id])
        XCTAssertTrue(ShootingCollectionSuggestionPresenter.offsetText(start: before.startDate, anchor: anchor.startDate).hasPrefix("−"))
        XCTAssertTrue(ShootingCollectionSuggestionPresenter.offsetText(start: after.startDate, anchor: anchor.startDate).hasPrefix("+"))
    }

    private func confirmAll(
        _ selection: inout ShootingCollectionSelection,
        from history: [RunningTimerItem], collectedIDs: Set<UUID>
    ) {
        guard let preview = selection.suggestion(from: history, collectedIDs: collectedIDs) else { return }
        selection.confirmSuggestion(
            preview, choosing: Set(preview.candidates.map(\.id)), from: history, collectedIDs: collectedIDs
        )
    }

    private func timer(
        at seconds: TimeInterval, status: TimerStatus = .completed,
        camera: CameraSlotID? = nil, film: String? = nil
    ) -> RunningTimerItem {
        RunningTimerItem(
            id: UUID(), order: 1, name: "Captured timer", basisSummary: "Captured basis", duration: 10,
            startDate: Date(timeIntervalSince1970: seconds), endDate: Date(timeIntervalSince1970: seconds + 10),
            pausedRemainingTime: nil, pausedAt: nil, status: status, referenceDate: Date(),
            cameraSlot: camera.map { CameraSlotIdentity(id: $0) }, filmDisplayName: film
        )
    }
}
