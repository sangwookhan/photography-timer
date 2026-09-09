// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// How one picker row of a filter wheel reads (Filter Set contract,
/// FILTER-STACK-003/007): the compact value the wheel shows at rest,
/// a short calculation-mode caption, the item name for the expanded
/// label, and the accessibility text. Pure value; the view owns
/// fonts and colors.
public struct FilterWheelRowDisplay: Equatable, Sendable {
    public let selection: FilterWheelSelection
    /// Compact value shown in the wheel column: the Standard value in
    /// the active notation, an item's contribution in stops, or the
    /// Empty marker.
    public let compactValueText: String
    /// Short mode caption under the value (`Rec` / `Full` for GND,
    /// `CPL` for a CPL row); `nil` for Standard, Fixed, and Empty.
    public let modeCaption: String?
    /// Full item name for the expanded moving label; `nil` for Standard
    /// and Empty rows.
    public let itemName: String?
    /// Expanded label shown while the wheel moves: the full item name
    /// plus the active contribution (and mode when it applies), or the
    /// Empty / Standard wording.
    public let expandedLabelText: String
    /// Why the row is unavailable on this wheel, already localized;
    /// `nil` when selectable.
    public let unavailabilityText: String?
    public let isEmpty: Bool
    public let isMounted: Bool

    public init(selection: FilterWheelSelection, compactValueText: String, modeCaption: String?, itemName: String?, expandedLabelText: String, unavailabilityText: String?, isEmpty: Bool, isMounted: Bool) {
        self.selection = selection
        self.compactValueText = compactValueText
        self.modeCaption = modeCaption
        self.itemName = itemName
        self.expandedLabelText = expandedLabelText
        self.unavailabilityText = unavailabilityText
        self.isEmpty = isEmpty
        self.isMounted = isMounted
    }

    public var isAvailable: Bool {
        unavailabilityText == nil
    }
}

/// Pure-value transforms from resolved filter rows into display text.
/// One place owns every rendering of a Filter Set row so the wheel,
/// the expanded label, VoiceOver, and the timer summary agree.
public enum FilterWheelPresenter {
    public static func rowDisplay(
        for option: FilterWheelRowOption,
        notationMode: NDNotationMode
    ) -> FilterWheelRowDisplay {
        rowDisplay(for: option.row, unavailability: option.unavailability, notationMode: notationMode)
    }

    public static func rowDisplay(
        for row: ResolvedFilterRow,
        unavailability: FilterStackRejection? = nil,
        notationMode: NDNotationMode
    ) -> FilterWheelRowDisplay {
        let unavailabilityText = unavailability.map(rejectionText(for:))
        switch row.selection {
        case .standard(let step):
            let display = NDNotationFormatter.display(for: step, mode: notationMode)
            return FilterWheelRowDisplay(
                selection: row.selection,
                compactValueText: display.value,
                modeCaption: nil,
                itemName: nil,
                expandedLabelText: String(localized: "Standard · \(display.inline)"),
                unavailabilityText: unavailabilityText,
                isEmpty: step.stops == 0,
                isMounted: false
            )
        case .empty:
            return FilterWheelRowDisplay(
                selection: .empty,
                compactValueText: "—",
                modeCaption: nil,
                itemName: nil,
                expandedLabelText: String(localized: "Empty · no filter mounted"),
                unavailabilityText: unavailabilityText,
                isEmpty: true,
                isMounted: false
            )
        case .item(let selection):
            let name = row.item?.name ?? ""
            let contribution = stopsText(row.contributionStops)
            let modeCaption: String?
            let expanded: String
            switch selection.choice {
            case .fixed:
                modeCaption = nil
                expanded = String(localized: "\(name) · \(contribution)")
            case .cplLoss:
                modeCaption = String(localized: "CPL")
                expanded = String(localized: "\(name) · CPL \(contribution)")
            case .gnd(.recordOnly):
                modeCaption = String(localized: "Rec")
                expanded = String(localized: "\(name) · Record only · \(contribution)")
            case .gnd(.applyFullValue):
                modeCaption = String(localized: "Full")
                expanded = String(localized: "\(name) · Apply full value · \(contribution)")
            }
            return FilterWheelRowDisplay(
                selection: row.selection,
                compactValueText: NDNotationFormatter.display(forStops: row.contributionStops, mode: .stops).value,
                modeCaption: modeCaption,
                itemName: name,
                expandedLabelText: expanded,
                unavailabilityText: unavailabilityText,
                isEmpty: false,
                isMounted: true
            )
        }
    }

    /// `N stops` / `1 stop` text for a contribution.
    public static func stopsText(_ stops: Double) -> String {
        let value = NDNotationFormatter.display(forStops: stops, mode: .stops).value
        if abs(stops - 1) <= ExposureCalculator.stabilityEpsilon {
            return String(localized: "1 stop")
        }
        return String(localized: "\(value) stops")
    }

    /// Original registered representation for the editor and the
    /// expanded label: `OD 0.9`, `ND8`, or `3 stops`.
    public static func registeredValueText(_ value: FilterRegisteredValue) -> String {
        let number = trimmedNumber(value.value)
        switch value.unit {
        case .stops:
            return stopsText(value.value)
        case .opticalDensity:
            return "OD \(number)"
        case .filterFactor:
            return "ND\(number)"
        }
    }

    public static func rejectionText(for rejection: FilterStackRejection) -> String {
        switch rejection {
        case .exceedsTotalLimit:
            return String(localized: "Exceeds 30 stops")
        case .itemAlreadyMounted:
            return String(localized: "Already mounted on this camera")
        case .unresolvedSelection:
            return String(localized: "Filter not available")
        }
    }

    public static func addUnavailabilityText(for reason: FilterAddUnavailability) -> String {
        switch reason {
        case .stackFull:
            return String(localized: "Four filters already mounted")
        case .noSelectableValue:
            return String(localized: "No Standard value fits the remaining budget")
        case .unknownFilterSet:
            return String(localized: "Filter Set no longer exists")
        case .filterSetHasNoItems:
            return String(localized: "This Filter Set has no filters yet")
        case .allItemsMounted:
            return String(localized: "Every filter in this set is already mounted")
        case .exceedsTotalLimit:
            return String(localized: "Exceeds 30 stops")
        }
    }

    /// Display name for a source: `Standard` or the Filter Set's name.
    public static func sourceName(_ source: FilterSource, inventory: FilterInventory) -> String {
        switch source {
        case .standard:
            return String(localized: "Standard")
        case .filterSet(let id):
            return inventory.filterSet(withID: id)?.name ?? String(localized: "Filter Set")
        }
    }

    public static func kindName(_ kind: FilterItemKind) -> String {
        switch kind {
        case .fixed: return String(localized: "Fixed")
        case .cpl: return String(localized: "CPL")
        case .gnd: return String(localized: "GND")
        }
    }

    public static func gndModeName(_ mode: GNDCalculationMode) -> String {
        switch mode {
        case .recordOnly: return String(localized: "Record only")
        case .applyFullValue: return String(localized: "Apply full value")
        }
    }

    public static func unitName(_ unit: FilterValueUnit) -> String {
        switch unit {
        case .stops: return String(localized: "Stops")
        case .opticalDensity: return "OD"
        case .filterFactor: return "ND"
        }
    }

    static func trimmedNumber(_ value: Double) -> String {
        let formatted = String(format: "%.3f", value)
        var trimmed = formatted
        while trimmed.contains("."), trimmed.hasSuffix("0") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
