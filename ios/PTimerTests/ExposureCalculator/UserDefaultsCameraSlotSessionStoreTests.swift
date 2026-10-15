// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
@testable import PTimer

/// The concrete managed-camera-list store: absent content, readable
/// content, and content that was read but cannot be decoded
/// (CAMERA-PERSIST-004). A `UserDefaults` read cannot fail, so the
/// failed-read outcome belongs to the recovery tests of the controller.
final class UserDefaultsCameraSlotSessionStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let key = "ptimer.managed-camera-list.snapshot"

    override func setUp() {
        super.setUp()
        suiteName = "UserDefaultsCameraSlotSessionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> UserDefaultsCameraSlotSessionStore {
        UserDefaultsCameraSlotSessionStore(userDefaults: defaults, managedKey: key)
    }

    func testAnEmptyStoreIsAbsent() {
        XCTAssertEqual(makeStore().loadManagedList(), .absent)
    }

    func testASavedListRoundTrips() {
        let store = makeStore()
        let snapshot = PersistentManagedCameraListSnapshot(
            issuedIDRaws: ["camera1"],
            activeCameraIDRaw: "camera1",
            cameras: [PersistentManagedCamera(idRaw: "camera1", name: "Nikon Z7", isDisplayed: true, calculator: nil)]
        )
        store.saveManagedList(snapshot)
        XCTAssertEqual(makeStore().loadManagedList(), .loaded(snapshot))
    }

    func testContentThatCannotBeDecodedIsUndecodableNotAbsent() {
        let store = makeStore()
        defaults.set(Data("not json".utf8), forKey: key)
        XCTAssertEqual(store.loadManagedList(), .undecodable)
        defaults.set("a string", forKey: key)
        XCTAssertEqual(store.loadManagedList(), .undecodable)
        defaults.set(Data(#"{"schemaVersion":99,"issuedIDRaws":[],"cameras":[]}"#.utf8), forKey: key)
        XCTAssertEqual(store.loadManagedList(), .undecodable, "An unknown version follows the corruption rule.")
        defaults.set(Data(#"{"schemaVersion":1,"issuedIDRaws":[],"cameras":"nope"}"#.utf8), forKey: key)
        XCTAssertEqual(store.loadManagedList(), .undecodable)
    }
}
