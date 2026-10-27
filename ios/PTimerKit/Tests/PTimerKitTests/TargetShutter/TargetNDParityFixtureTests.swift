// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

final class TargetNDParityFixtureTests: XCTestCase {
    private struct Fixture: Decodable { let cases: [Case] }
    private struct Case: Decodable {
        let name: String
        let requiredStops: Double
        let items: [Double]
        let selectSet: Bool
        let minimumError: Double
        let maximumError: Double
        let expectedStops: Double?
        let expectedCount: Int?
    }

    func testSharedSelectionCases() throws {
        let url = SharedFixtureLocator.fixturesRoot().appendingPathComponent("target-nd-selection.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let setID = FilterSetID(rawValue: "set")
        for row in fixture.cases {
            let items = row.items.enumerated().map {
                FilterItem(id: .init(rawValue: "item-\($0.offset)"), name: "ND \($0.offset)", behavior: .fixed(.init(value: $0.element, unit: .stops)))
            }
            let inventory = FilterInventory(filterSets: [.init(id: setID, name: "ND", color: .blue, items: items)])
            let result = TargetNDSelection().evaluate(baseSeconds: 1, targetSeconds: pow(2, row.requiredStops), profile: nil, inventory: inventory, context: .init(selectedSets: row.selectSet ? [setID] : [], current: .init(standardSteps: [NDStep(stops: 0)]), allowance: row.minimumError...row.maximumError))
            if let expected = row.expectedStops {
                guard case .available(_, let candidate) = result else { XCTFail("\(row.name): \(result)"); continue }
                XCTAssertEqual(candidate.stack.effectiveStep.stops, expected, accuracy: 1e-10, row.name)
                XCTAssertEqual(candidate.stack.wheels.filter { !$0.isCleanable }.count, row.expectedCount, row.name)
            } else { XCTAssertEqual(result, .unavailable(.noCombination), row.name) }
        }
    }
}
