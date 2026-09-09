// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// How one picker row of a filter wheel reads (Filter Set contract,
/// FILTER-STACK-003/007): the compact value the wheel shows at rest,
/// a short calculation-mode caption, the item name for the expanded
/// label, and the accessibility text. Pure value; the view owns
/// fonts and colors.
public struct FilterWheelRowDisplay: Hashable, Sendable {
    public let selection: FilterWheelSelection
    /// Compact value shown in the wheel column: the Standard value in
    /// the active notation, an item's registered representation
    /// (`ND1000`, `OD 0.9`, `3 stops`, `CPL 1.5`) independent of that
    /// notation, or the Empty marker (FILTER-STACK-007).
    public let compactValueText: String
    /// Short mode caption under the value (`Rec` / `Full` for GND);
    /// `nil` for Standard, Fixed, CPL, and Empty.
    public let modeCaption: String?
    /// The item's registered representation as the user entered it;
    /// `nil` for Standard and Empty rows.
    public let registeredText: String?
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

    public init(selection: FilterWheelSelection, compactValueText: String, modeCaption: String?, registeredText: String? = nil, itemName: String?, expandedLabelText: String, unavailabilityText: String?, isEmpty: Bool, isMounted: Bool) {
        self.selection = selection
        self.compactValueText = compactValueText
        self.modeCaption = modeCaption
        self.registeredText = registeredText
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
            // Registered representation as the user entered it — never
            // the Standard notation (FILTER-STACK-007). A CPL's
            // representation is its selected exposure-loss choice.
            let registered = registeredText(for: row.item, choice: selection.choice, fallbackStops: row.registeredStops)
            let modeCaption: String?
            let modeName: String?
            switch selection.choice {
            case .fixed, .cplLoss:
                modeCaption = nil
                modeName = nil
            case .gnd(.recordOnly):
                modeCaption = String(localized: "Rec")
                modeName = gndModeName(.recordOnly)
            case .gnd(.applyFullValue):
                modeCaption = String(localized: "Full")
                modeName = gndModeName(.applyFullValue)
            }
            // Expanded label: full name · registered representation ·
            // (mode) · active contribution. A Fixed item registered in
            // stops would print its value twice, so the contribution is
            // shown once in that case.
            var segments = [name, registered]
            if let modeName {
                segments.append(modeName)
            }
            if registered != contribution || modeName != nil {
                segments.append(contribution)
            }
            return FilterWheelRowDisplay(
                selection: row.selection,
                compactValueText: registered,
                modeCaption: modeCaption,
                registeredText: registered,
                itemName: name,
                expandedLabelText: segments.joined(separator: " · "),
                unavailabilityText: unavailabilityText,
                isEmpty: false,
                isMounted: true
            )
        }
    }

    /// Registered representation of a mounted row: the Fixed / GND
    /// value as entered (`ND1000`, `OD 0.9`, `3 stops`) or the CPL's
    /// selected choice (`CPL 1.5`). `fallbackStops` covers an item that
    /// could not be resolved (defensive; rows are always resolved).
    public static func registeredText(for item: FilterItem?, choice: FilterRowChoice, fallbackStops: Double) -> String {
        switch choice {
        case .cplLoss(let loss):
            return String(localized: "CPL \(decimalStopsValue(loss))")
        case .fixed, .gnd:
            if let value = item?.behavior.registeredValue {
                return registeredValueText(value)
            }
            return stopsText(fallbackStops)
        }
    }

    /// `N stops` / `1 stop` text for a contribution.
    public static func stopsText(_ stops: Double) -> String {
        if abs(stops - 1) <= ExposureCalculator.stabilityEpsilon {
            return String(localized: "1 stop")
        }
        return String(localized: "\(decimalStopsValue(stops)) stops")
    }

    /// Plain decimal rendering of a registered or contributed stops
    /// value: whole values as integers, otherwise up to two trimmed
    /// decimals (`1.5`, `3.33`, `6.6`). Filter Item values are user
    /// decimals — never ladder values — so they deliberately bypass
    /// the Standard ladder's mixed-fraction notation.
    public static func decimalStopsValue(_ stops: Double) -> String {
        if abs(stops - stops.rounded()) <= ExposureCalculator.stabilityEpsilon {
            return String(Int(stops.rounded()))
        }
        let formatted = String(format: "%.2f", stops)
        var trimmed = formatted
        while trimmed.contains("."), trimmed.hasSuffix("0") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
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

    public static func trimmedNumber(_ value: Double) -> String {
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
