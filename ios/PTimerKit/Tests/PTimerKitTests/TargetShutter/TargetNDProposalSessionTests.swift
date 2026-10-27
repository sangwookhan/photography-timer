// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

final class TargetNDProposalSessionTests: XCTestCase {
    private func input(camera: String = "camera-1", target: Double = 1024, settings: TargetNDSettings = .init(), inventory: FilterInventory = .empty, filmID: String? = nil, filmColor: FilmColor? = nil) -> TargetNDProposalInput {
        .init(cameraID: camera, baseSeconds: 1, targetSeconds: target, profile: nil, inventory: inventory, selectedSets: [], current: .init(standardSteps: [NDStep(stops: 0)]), settings: settings, medium: .digital, filmID: filmID, filmColor: filmColor)
    }
    private func ready(_ input: TargetNDProposalInput, now: TimeInterval = 10) -> TargetNDProposalSession {
        var session = TargetNDProposalSession()
        session.begin(input)
        let token = session.settle(input, filtersAreQuiet: true)!
        XCTAssertTrue(session.complete(input.evaluate(), input: input, generation: token, now: now))
        return session
    }

    func testSameValueInteractionQualifiesOnlyAtFinalCommitWithQuietFilters() {
        let data = input()
        var session = TargetNDProposalSession()
        XCTAssertNil(session.settle(data, filtersAreQuiet: true), "Input changes cannot offer without a manual interaction.")
        session.begin(data)
        session.preview(data)
        XCTAssertNil(session.settle(data, filtersAreQuiet: false))
        XCTAssertEqual(session.phase, .interacting)
        XCTAssertNotNil(session.settle(data, filtersAreQuiet: true))
        XCTAssertEqual(session.phase, .evaluating)
    }

    func testOfferExpiresExactlyFiveSecondsAfterResultReadiness() {
        var session = ready(input())
        let token = session.generation
        session.expire(generation: token, now: 14.999)
        XCTAssertEqual(session.phase, .result)
        session.expire(generation: token, now: 15)
        XCTAssertEqual(session.phase, .idle)
    }

    func testNoCombinationExpiresTwoSecondsAfterReadinessAndOldTimeoutCannotDismissNewOffer() {
        let data = input(target: pow(2, 31))
        var session = ready(data)
        XCTAssertEqual(session.result, .unavailable(.noCombination))
        let old = session.generation
        session.expire(generation: old, now: 11.999)
        XCTAssertEqual(session.phase, .result)
        var expired = session
        expired.expire(generation: old, now: 12)
        XCTAssertEqual(expired.phase, .idle)
        session.begin(input())
        let current = input()
        let fresh = session.settle(current, filtersAreQuiet: true)!
        XCTAssertTrue(session.complete(current.evaluate(), input: current, generation: fresh, now: 12))
        session.expire(generation: old, now: 100)
        XCTAssertEqual(session.phase, .result)
        session.expire(generation: fresh, now: 17)
        XCTAssertEqual(session.phase, .idle)
    }

    func testOlderTimeoutAndLateCompletionCannotAffectNewInteraction() {
        let data = input()
        var session = ready(data)
        let old = session.generation
        session.begin(data)
        let fresh = session.settle(data, filtersAreQuiet: true)!
        XCTAssertFalse(session.complete(data.evaluate(), input: data, generation: old, now: 20))
        XCTAssertTrue(session.complete(data.evaluate(), input: data, generation: fresh, now: 20))
        session.expire(generation: old, now: 100)
        XCTAssertEqual(session.phase, .result)
    }

    func testScreenReaderFocusSuspendsExpiryAndResumesRemainingLifetime() {
        var session = ready(input())
        session.focusAction(true, now: 12)
        session.expire(generation: session.generation, now: 100)
        XCTAssertEqual(session.phase, .result)
        session.focusAction(false, now: 100)
        XCTAssertEqual(session.expiresAt, 103)
        session.expire(generation: session.generation, now: 103)
        XCTAssertEqual(session.phase, .idle)
    }

    func testCameraTargetSettingsAndInventoryChangesCannotApplyOldProposal() {
        var disabled = TargetNDSettings()
        disabled.isEnabled = false
        let inventory = FilterInventory(filterSets: [.init(name: "New", color: .blue)])
        for changed in [input(camera: "camera-2"), input(target: 512), input(settings: disabled), input(inventory: inventory), input(filmID: "other-film"), input(filmColor: .color)] {
            var session = ready(input())
            XCTAssertEqual(try? session.consume(current: changed, now: 11).get(), nil)
            XCTAssertEqual(session.phase, .idle)
        }
    }

    func testConsumeRevalidatesOnceAndNeverMutatesInputs() throws {
        let data = input()
        var session = ready(data)
        let stack = try session.consume(current: data, now: 11).get()
        XCTAssertEqual(stack.effectiveStep.stops, 10)
        XCTAssertEqual(data.current.effectiveStep.stops, 0)
        guard case .failure(.duplicate) = session.consume(current: data, now: 11) else { return XCTFail("Duplicate Apply must fail") }
        session.expire(generation: session.generation, now: 12.5)
        XCTAssertEqual(session.phase, .idle)
    }

    func testInvalidationDoesNotReopenOfferAndDiscardsLateWorker() {
        let data = input()
        var session = ready(data)
        let old = session.generation
        session.invalidate()
        XCTAssertFalse(session.complete(data.evaluate(), input: data, generation: old, now: 20))
        XCTAssertNil(session.settle(data, filtersAreQuiet: true))
    }
}
