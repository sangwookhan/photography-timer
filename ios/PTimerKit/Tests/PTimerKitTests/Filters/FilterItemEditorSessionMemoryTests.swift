// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// FILTER-ITEM-007 / FR-1.12: within one open Filter Set editing
/// session the next new item starts in the notation of the last saved
/// new Fixed or GND item; the kind always starts Fixed; a new session
/// starts in Stops.
final class FilterItemEditorSessionMemoryTests: XCTestCase {
    private func fixed(_ unit: FilterValueUnit, _ value: Double = 3) -> FilterItem {
        FilterItem(name: "F", behavior: .fixed(FilterRegisteredValue(value: value, unit: unit)))
    }

    func testANewSessionStartsInStopsAndFixed() {
        let memory = FilterItemEditorSessionMemory()
        XCTAssertEqual(memory.initialUnit, .stops)
        XCTAssertEqual(memory.initialKind, .fixed)
    }

    func testTheNextNewItemStartsInTheLastSavedNotation() {
        var memory = FilterItemEditorSessionMemory()
        memory.didSaveNewItem(fixed(.stops))
        XCTAssertEqual(memory.initialUnit, .stops, "Stops -> next starts Stops")
        memory.didSaveNewItem(fixed(.opticalDensity, 0.9))
        XCTAssertEqual(memory.initialUnit, .opticalDensity, "OD -> next starts OD")
        memory.didSaveNewItem(fixed(.filterFactor, 1000))
        XCTAssertEqual(memory.initialUnit, .filterFactor, "ND -> next starts ND")
        memory.didSaveNewItem(FilterItem(name: "G", behavior: .gnd(FilterRegisteredValue(value: 0.6, unit: .opticalDensity))))
        XCTAssertEqual(memory.initialUnit, .opticalDensity, "A GND's notation counts like a Fixed one.")
    }

    func testKindNeverInheritsAndCPLLeavesTheNotationUnchanged() {
        var memory = FilterItemEditorSessionMemory()
        memory.didSaveNewItem(fixed(.filterFactor, 64))
        memory.didSaveNewItem(FilterItem(name: "C", behavior: .cpl(CPLExposureLossChoices.defaults)))
        XCTAssertEqual(memory.initialKind, .fixed, "After a CPL the next item is still Fixed.")
        XCTAssertEqual(memory.initialUnit, .filterFactor, "A CPL has no notation and does not reset ND.")
        memory.didSaveNewItem(FilterItem(name: "G", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops))))
        XCTAssertEqual(memory.initialKind, .fixed, "After a GND the next item is still Fixed.")
    }

    func testClosingTheEditorResetsToStops() {
        var memory = FilterItemEditorSessionMemory()
        memory.didSaveNewItem(fixed(.opticalDensity))
        // The owning editor view discards its session value when it
        // closes; a new session is a fresh value.
        let reopened = FilterItemEditorSessionMemory()
        XCTAssertEqual(reopened.initialUnit, .stops)
        XCTAssertNotEqual(memory, reopened)
    }
}
