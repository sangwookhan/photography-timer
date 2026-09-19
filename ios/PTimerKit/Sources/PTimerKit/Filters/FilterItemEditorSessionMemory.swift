// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// What one open Filter Set editing session remembers between
/// consecutive new items (FILTER-ITEM-007 / FR-1.12): the registered
/// value notation of the last saved new Fixed or GND item, so the
/// next new item starts in Stops, OD, or ND accordingly. The kind is
/// independent and always starts as Fixed. The value lives with the
/// open editor and is never persisted: closing the editor or
/// relaunching starts a fresh session in Stops.
public struct FilterItemEditorSessionMemory: Equatable, Sendable {
    /// Notation the next new item starts with.
    public private(set) var initialUnit: FilterValueUnit = .stops

    public init() {}

    /// Every new item starts as Fixed regardless of what was saved.
    public var initialKind: FilterItemKind { .fixed }

    /// A new item was saved in this session. Fixed and GND carry a
    /// registered notation and update the memory; a CPL has none and
    /// leaves it unchanged. Editing an existing item never calls this.
    public mutating func didSaveNewItem(_ item: FilterItem) {
        switch item.behavior {
        case .fixed(let value), .gnd(let value):
            initialUnit = value.unit
        case .cpl:
            break
        }
    }
}
