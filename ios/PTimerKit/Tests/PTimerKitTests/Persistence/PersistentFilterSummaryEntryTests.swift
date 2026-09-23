// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-PERSIST-003: the captured summary is stored through its own
/// persistence record with raw string tokens, and entries decode
/// independently so one damaged entry never erases the others.
final class PersistentFilterSummaryEntryTests: XCTestCase {
    private let entry = FilterSummaryEntry(
        sourceKind: .filterSet,
        filterSetID: "s",
        filterSetName: "Lee",
        itemID: "i",
        itemName: "GND",
        itemKind: .gnd,
        originalValue: 0.9,
        originalUnit: .opticalDensity,
        canonicalStops: 3,
        calculationMode: .gndRecordOnly,
        contributedStops: 0
    )

    func testRecordStoresRawTokensAndRoundTrips() throws {
        let snapshot = PersistentTimerMetadataSnapshot(id: UUID(), order: 1, name: "t", basisSummary: "b", filterSummary: [entry])
        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"sourceKind\":\"filterSet\""), json)
        XCTAssertTrue(json.contains("\"calculationMode\":\"gndRecordOnly\""), json)

        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: data)
        XCTAssertEqual(decoded.filterSummary, [entry])
    }

    func testOneMalformedEntryIsDroppedAndTheOthersSurvive() throws {
        let json = """
        {"id":"\(UUID().uuidString)","order":1,"name":"t","basisSummary":"b","filterSummary":[
          {"sourceKind":"standard","canonicalStops":2,"contributedStops":2},
          {"sourceKind":"standard","canonicalStops":"broken"},
          {"sourceKind":"unknownKind","contributedStops":1},
          {"sourceKind":"filterSet","itemKind":"laser","originalUnit":"parsec","contributedStops":4}
        ]}
        """
        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(decoded.filterSummary)
        XCTAssertEqual(summary.count, 2, "The undecodable and the unknown-source entries are dropped.")
        XCTAssertEqual(summary[0].contributedStops, 2)
        XCTAssertEqual(summary[1].sourceKind, .filterSet)
        XCTAssertNil(summary[1].itemKind, "An unknown optional token degrades to nil instead of dropping the entry.")
        XCTAssertNil(summary[1].originalUnit)
    }

    func testANonArraySummaryDecodesAsAbsent() throws {
        let json = """
        {"id":"\(UUID().uuidString)","order":1,"name":"t","basisSummary":"b","filterSummary":{"bad":true}}
        """
        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.filterSummary)
    }
}
