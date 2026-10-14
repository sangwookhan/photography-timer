// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
@testable import PTimer

/// The concrete automatic-name sequence store: absent, usable, and the
/// unusable cases that must be preserved rather than overwritten.
final class UserDefaultsCameraNameSequenceStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let key = "ptimer.camera-name-sequence.snapshot"

    override func setUp() {
        super.setUp()
        suiteName = "UserDefaultsCameraNameSequenceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> UserDefaultsCameraNameSequenceStore {
        UserDefaultsCameraNameSequenceStore(userDefaults: defaults, snapshotKey: key)
    }

    func testAnEmptyStoreIsAbsent() {
        XCTAssertEqual(makeStore().load(), .absent)
    }

    func testASavedValueRoundTrips() {
        let store = makeStore()
        XCTAssertTrue(store.save(nextNumber: 5))
        XCTAssertEqual(store.load(), .value(5))
        XCTAssertTrue(store.save(nextNumber: 6))
        XCTAssertEqual(makeStore().load(), .value(6))
    }

    func testCorruptUnsupportedAndOutOfRangeValuesAreUnusableAndNeverOverwrittenByLoad() throws {
        defaults.set("not data", forKey: key)
        XCTAssertEqual(makeStore().load(), .unusable)

        defaults.set(Data("{\"nope\":1}".utf8), forKey: key)
        XCTAssertEqual(makeStore().load(), .unusable)

        let future = try JSONEncoder().encode(
            PersistentCameraNameSequenceSnapshot(schemaVersion: 99, nextNumber: 5)
        )
        defaults.set(future, forKey: key)
        XCTAssertEqual(makeStore().load(), .unusable)
        XCTAssertEqual(defaults.data(forKey: key), future, "Loading preserves the stored value.")

        let zero = try JSONEncoder().encode(PersistentCameraNameSequenceSnapshot(nextNumber: 0))
        defaults.set(zero, forKey: key)
        XCTAssertEqual(makeStore().load(), .unusable)
    }

    func testASequenceBelowOneIsNotWritten() {
        let store = makeStore()
        XCTAssertFalse(store.save(nextNumber: 0))
        XCTAssertEqual(store.load(), .absent)
    }

    func testTheSequenceUsesItsOwnKeyApartFromTheManagedList() {
        XCTAssertNotEqual(key, "ptimer.managed-camera-list.snapshot")
        XCTAssertTrue(makeStore().save(nextNumber: 5))
        XCTAssertNil(defaults.object(forKey: "ptimer.managed-camera-list.snapshot"))
    }
}
