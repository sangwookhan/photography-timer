// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

final class TargetNDSelectionTests: XCTestCase {
    private let selector = TargetNDSelection()
    private let setID = FilterSetID(rawValue: "set")

    private func inventory(_ stops: [Double]) -> FilterInventory {
        let items = stops.enumerated().map {
            FilterItem(id: .init(rawValue: "item-\($0.offset)"), name: "ND \($0.offset)", behavior: .fixed(.init(value: $0.element, unit: .stops)))
        }
        return .init(filterSets: [.init(id: setID, name: "ND", color: .blue, items: items)])
    }

    private func selected(_ required: Double, inventory: FilterInventory, sets: [FilterSetID], current: FilterStack = .init(standardSteps: [NDStep(stops: 0)]), interval: ClosedRange<Double> = -0.5...1) throws -> TargetNDCandidate {
        let result = selector.evaluate(baseSeconds: 1, targetSeconds: pow(2, required), profile: nil, inventory: inventory, context: .init(selectedSets: sets, current: current, allowance: interval))
        guard case .available(_, let candidate) = result else { XCTFail("\(result)"); throw Failure.missing }
        return candidate
    }

    private enum Failure: Error { case missing }

    func testStandardReplacementIgnoresRemovedSiblingsAndLegacyFractions() throws {
        let old = FilterStack(standardSteps: [NDStep(stops: 10), NDStep(stops: 10)])
        let candidate = try selected(25, inventory: .empty, sets: [], current: old)
        XCTAssertEqual(candidate.stack.wheels, [.standard(NDStep(stops: 25))])
        let legacy = FilterStack(standardSteps: [NDStep(stops: 6.6)])
        let replacement = try selected(6.6, inventory: .empty, sets: [], current: legacy)
        XCTAssertEqual(replacement.stack.wheels, [.standard(NDStep(stops: 7))])
        XCTAssertFalse(replacement.isCurrent)
    }

    func testSelectedNDDisablesStandardAndUnselectedInventory() {
        let inv = inventory([3])
        XCTAssertEqual(selector.evaluate(baseSeconds: 1, targetSeconds: 1024, profile: nil, inventory: inv, context: .init(selectedSets: [setID], current: .init(standardSteps: [NDStep(stops: 0)]), allowance: -0.5...1)), .unavailable(.noCombination))
    }

    func testEmptyAndAuxiliaryOnlySetsUseStandard() throws {
        let empty = FilterInventory(filterSets: [.init(id: setID, name: "Empty", color: .blue)])
        XCTAssertEqual(try selected(10, inventory: empty, sets: [setID]).stack.effectiveStep.stops, 10)
        let auxOnly = FilterInventory(filterSets: [.init(id: setID, name: "Aux", color: .blue, items: [.init(name: "GND", behavior: .gnd(.init(value: 3, unit: .stops)))])])
        XCTAssertEqual(try selected(10, inventory: auxOnly, sets: [setID]).stack.effectiveStep.stops, 10)
        XCTAssertEqual(try selected(10, inventory: inventory([3]), sets: []).stack.effectiveStep.stops, 10)
    }

    func testZeroNDUsesOneEmptyAndDoesNotCountAsPhysicalFilter() throws {
        let inv = inventory([3, 6])
        let result = try selected(0, inventory: inv, sets: [setID])
        XCTAssertEqual(result.stack.wheels, [.empty(in: setID)])
        XCTAssertTrue(result.isCurrent, "Empty and Standard zero have no mounted ND identity.")
    }

    func testEquivalenceBandPrefersFewerFiltersAtPointOneButNotOutside() throws {
        for (single, expectedCount) in [(8.9, 1), (8.899999, 2)] {
            let inv = inventory([single, 3, 6])
            let candidate = try selected(9, inventory: inv, sets: [setID])
            XCTAssertEqual(candidate.stack.wheels.count, expectedCount)
        }
    }

    func testConfiguredAllowanceIsFilteredBeforeEquivalence() throws {
        let inv = inventory([9.1, 3, 6])
        let candidate = try selected(9, inventory: inv, sets: [setID], interval: 0...1)
        XCTAssertEqual(candidate.stack.wheels.count, 2)
        XCTAssertEqual(candidate.remainingError, 0)
    }

    func testChangeCountThenIdentityAndCurrentSuitable() throws {
        let inv = inventory([6, 6])
        let current = try XCTUnwrap(FilterStack.validated(wheels: [.init(source: .filterSet(setID), selection: .item(.init(itemID: .init(rawValue: "item-1"), choice: .fixed)))], inventory: inv))
        let candidate = try selected(6, inventory: inv, sets: [setID], current: current)
        XCTAssertTrue(candidate.isCurrent)
        XCTAssertEqual(candidate.stack.wheels, current.wheels)
        let stable = try selected(6, inventory: inv, sets: [setID])
        XCTAssertEqual(stable.stack.wheels.first?.mountedItemID?.rawValue, "item-0")
    }

    func testPhysicalItemCannotBeUsedTwiceAndFourWheelLimitIsEnforced() throws {
        let inv = inventory([3])
        XCTAssertEqual(selector.evaluate(baseSeconds: 1, targetSeconds: 64, profile: nil, inventory: inv, context: .init(selectedSets: [setID, setID], current: .init(standardSteps: [NDStep(stops: 0)]), allowance: 0...0)), .unavailable(.noCombination))
        let five = inventory([1, 2, 4, 8, 15])
        XCTAssertEqual(selector.evaluate(baseSeconds: 1, targetSeconds: pow(2, 30), profile: nil, inventory: five, context: .init(selectedSets: [setID], current: .init(standardSteps: [NDStep(stops: 0)]), allowance: 0...0)), .unavailable(.noCombination))
    }

    func testNegativeTotalAndInvalidInputsAreHonestFailures() {
        let current = FilterStack(standardSteps: [NDStep(stops: 0)])
        XCTAssertEqual(selector.evaluate(baseSeconds: 2, targetSeconds: 1, profile: nil, inventory: .empty, context: .init(selectedSets: [], current: current, allowance: -2...0)), .unavailable(.negativeRequiredTotal))
        XCTAssertEqual(selector.evaluate(baseSeconds: .nan, targetSeconds: 1, profile: nil, inventory: .empty, context: .init(selectedSets: [], current: current, allowance: -1...0)), .unavailable(.invalidInput))
        XCTAssertEqual(selector.evaluate(baseSeconds: 1, targetSeconds: pow(2, 31), profile: nil, inventory: .empty, context: .init(selectedSets: [], current: current, allowance: 0...0)), .unavailable(.noCombination))
    }

    func testAllAllowanceEndpointsAndImmediatelyOutside() {
        for medium in TargetNDMedium.allCases {
            for mode in TargetNDAllowance.allCases {
                let interval = mode.interval(for: medium)
                XCTAssertTrue(interval.contains(interval.lowerBound))
                XCTAssertTrue(interval.contains(interval.upperBound))
                XCTAssertFalse(interval.contains(interval.lowerBound.nextDown))
                XCTAssertFalse(interval.contains(interval.upperBound.nextUp))
            }
        }
    }
    func testAuxiliaryChoicesSurviveZeroSolutionAndNDLimit() throws {
        var inv = inventory([1, 2, 4, 8])
        let cpl = FilterItem(id: .init(rawValue: "cpl"), name: "CPL", behavior: .cpl(.init(fields: [1, 2])))
        let gnd = FilterItem(id: .init(rawValue: "gnd"), name: "GND", behavior: .gnd(.init(value: 3, unit: .stops)))
        inv.filterSets[0].items += [cpl, gnd]
        let mounts: [MountedAuxiliaryFilter] = [
            .init(filterSetID: setID, itemID: cpl.id, choice: .cplLoss(2)),
            .init(filterSetID: setID, itemID: gnd.id, choice: .gnd(.recordOnly)),
        ]
        let current = try XCTUnwrap(FilterStack.validated(wheels: [.empty(in: setID)], auxiliaryFilters: mounts, inventory: inv))
        let zero = try selected(2, inventory: inv, sets: [setID], current: current, interval: 0...0)
        XCTAssertEqual(zero.stack.auxiliaryFilters, current.auxiliaryFilters)
        XCTAssertEqual(zero.stack.wheels, [.empty(in: setID)])
        XCTAssertEqual(zero.stack.effectiveStep.stops, 2)
        XCTAssertEqual(selector.evaluate(baseSeconds: 1, targetSeconds: pow(2, 17), profile: nil, inventory: inv, context: .init(selectedSets: [setID], current: current, allowance: 0...0)), .unavailable(.noCombination), "Aux leaves only three ND slots; 1+2+4+8 requires four.")
        XCTAssertEqual(selector.evaluate(baseSeconds: 1, targetSeconds: 1, profile: nil, inventory: inv, context: .init(selectedSets: [setID], current: current, allowance: -0.5...1)), .unavailable(.noCombination), "Fixed auxiliary loss must not be reduced to make a candidate.")
    }

    func testStandardRespectsAuxiliaryBudgetAndTotalCap() throws {
        let aux = FilterItem(name: "Color", behavior: .color(.init(stops: 1), .blue))
        let set = FilterSet(id: setID, name: "Aux", color: .blue, items: [aux])
        let inv = FilterInventory(filterSets: [set])
        let current = try XCTUnwrap(FilterStack.validated(wheels: [.standard(NDStep(stops: 0))], auxiliaryFilters: [.init(filterSetID: setID, itemID: aux.id, choice: .registeredLoss)], inventory: inv))
        let candidate = try selected(30, inventory: inv, sets: [setID], current: current, interval: 0...0)
        XCTAssertEqual(candidate.stack.wheels, [.standard(NDStep(stops: 29))])
        XCTAssertEqual(candidate.stack.auxiliaryFilters, current.auxiliaryFilters)
        XCTAssertEqual(candidate.stack.effectiveStep.stops, 30)
    }

    func testFilmSelectionUsesInverseAndRetainsContinuationWarning() throws {
        let profile = ReciprocityProfile(id: "formula", name: "Formula", source: .init(kind: .userDefined, authority: .userDefined, publisher: "Custom"), rules: [.formula(.init(formula: .init(exponent: 2, noCorrectionThroughSeconds: 1, sourceRangeThroughSeconds: 10)))])
        let current = FilterStack(standardSteps: [NDStep(stops: 0)])
        let result = selector.evaluate(baseSeconds: 1, targetSeconds: 1024, profile: profile, inventory: .empty, context: .init(selectedSets: [], current: current, allowance: -0.5...1))
        guard case .available(let required, let candidate) = result else { return XCTFail("Expected numeric continuation") }
        XCTAssertEqual(required, 5, accuracy: 1e-12)
        XCTAssertEqual(candidate.stack.effectiveStep.stops, 5)
        XCTAssertTrue(candidate.requiresSourceWarning)
        XCTAssertEqual(candidate.remainingError, 0, accuracy: 1e-12)
    }

    func testStructuredPhysicalIdentitiesCannotAliasAcrossSources() throws {
        let first = FilterSet(id: .init(rawValue: "a"), name: "First", color: .blue, items: [.init(id: .init(rawValue: "b:c"), name: "ND6", behavior: .fixed(.init(value: 6, unit: .stops)))])
        let second = FilterSet(id: .init(rawValue: "a:b"), name: "Second", color: .red, items: [.init(id: .init(rawValue: "c"), name: "ND7", behavior: .fixed(.init(value: 7, unit: .stops)))])
        let inv = FilterInventory(filterSets: [first, second])
        let current = try XCTUnwrap(FilterStack.validated(wheels: [.init(source: .filterSet(first.id), selection: .item(.init(itemID: first.items[0].id, choice: .fixed)))], inventory: inv))
        let candidate = try selected(7, inventory: inv, sets: [first.id, second.id], current: current)
        XCTAssertEqual(candidate.stack.effectiveStep.stops, 7)
        XCTAssertFalse(candidate.isCurrent)
    }

}
