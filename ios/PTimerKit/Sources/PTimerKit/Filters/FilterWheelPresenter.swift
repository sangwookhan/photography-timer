// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Semantic type of a filter wheel candidate (FILTER-STACK-007): the
/// category behind the row's type-color rail. GND Record only and
/// Apply full value share one category; the persistent label carries
/// the mode. Independent of the user-selected Filter Set color.
public enum FilterRowTypeCategory: Hashable, Sendable, CaseIterable {
    case nd
    case cpl
    case gnd
    case empty
}

/// How one picker row of a filter wheel reads (Filter Set contract,
/// FILTER-STACK-003/007): the numeric value the scrolling viewport
/// shows, the persistent type / mode label above the viewport, the
/// item name and original registered representation for the status
/// region, and the accessibility text. Pure value; the view owns
/// fonts and colors.
public struct FilterWheelRowDisplay: Hashable, Sendable {
    public let selection: FilterWheelSelection
    /// Numeric-only value for the scrolling viewport: Standard, Fixed,
    /// and GND values in the app-global notation through the shared
    /// Standard formatter (10 stops → `10` / `3.0` / `1000`), CPL
    /// exposure loss in stops regardless of notation (`1.5`), and
    /// canonical zero for Empty (`0` / `0.0` / `1`) (FILTER-STACK-007).
    public let compactValueText: String
    /// Persistent type label above the viewport: `ND` (Standard and
    /// Fixed), `CPL`, `GND`, or `EMPTY`.
    public let typeLabel: String
    /// Persistent mode label beside the type: `REC` / `FULL` for GND;
    /// `nil` otherwise.
    public let modeLabel: String?
    /// Semantic type behind this row's color rail: a pure function of
    /// the row's own selection, so the rail travels with the candidate
    /// through dragging, fling, commit, and snap-back. Visual only —
    /// the accessibility text keeps the full names, and rows carry no
    /// type words.
    public let typeCategory: FilterRowTypeCategory
    /// The item's registered representation as the user entered it
    /// (`ND1000`, `OD 0.9`, `3 stops`, `CPL 1.5`) — equipment reference
    /// text for the status region, management UI, and accessibility;
    /// `nil` for Standard and Empty rows.
    public let registeredText: String?
    /// Full item name for the expanded moving label; `nil` for Standard
    /// and Empty rows.
    public let itemName: String?
    /// Detailed label for the status region while the wheel moves: the
    /// full item name plus the active contribution (and mode when it
    /// applies), or the Empty / Standard wording.
    public let expandedLabelText: String
    /// Why the row is unavailable on this wheel, already localized;
    /// `nil` when selectable.
    public let unavailabilityText: String?
    /// Concise dynamic VoiceOver value: current item or Empty,
    /// semantic type / mode, canonical contribution, and an optional
    /// unavailability reason (FILTER-A11Y-001/005).
    public let accessibilityValueText: String
    public let isEmpty: Bool
    public let isMounted: Bool

    public init(selection: FilterWheelSelection, compactValueText: String, typeLabel: String, modeLabel: String? = nil, typeCategory: FilterRowTypeCategory, registeredText: String? = nil, itemName: String?, expandedLabelText: String, unavailabilityText: String?, accessibilityValueText: String, isEmpty: Bool, isMounted: Bool) {
        self.selection = selection
        self.compactValueText = compactValueText
        self.typeLabel = typeLabel
        self.modeLabel = modeLabel
        self.typeCategory = typeCategory
        self.registeredText = registeredText
        self.itemName = itemName
        self.expandedLabelText = expandedLabelText
        self.unavailabilityText = unavailabilityText
        self.accessibilityValueText = accessibilityValueText
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
                typeLabel: TypeLabel.nd,
                typeCategory: .nd,
                itemName: nil,
                expandedLabelText: String(localized: "Standard · \(display.inline)"),
                unavailabilityText: unavailabilityText,
                accessibilityValueText: accessibilityValue(
                    segments: [String(localized: "Standard"), TypeLabel.nd, stopsText(row.contributionStops)],
                    unavailabilityText: unavailabilityText
                ),
                isEmpty: step.stops == 0,
                isMounted: false
            )
        case .empty:
            // Empty renders canonical zero through the shared Standard
            // formatter (`0` / `0.0` / `1`) so it reads like Standard
            // zero (FILTER-STACK-007); the `EMPTY` label, the gray rail,
            // and the status text keep the distinct no-filter-mounted
            // meaning, and the selection stays `.empty`.
            return FilterWheelRowDisplay(
                selection: .empty,
                compactValueText: NDNotationFormatter.display(forStops: 0, mode: notationMode).value,
                typeLabel: TypeLabel.empty,
                typeCategory: .empty,
                itemName: nil,
                expandedLabelText: String(localized: "Empty · no filter mounted"),
                unavailabilityText: unavailabilityText,
                accessibilityValueText: accessibilityValue(
                    segments: [String(localized: "Empty"), stopsText(0)],
                    unavailabilityText: unavailabilityText
                ),
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
            let viewport = viewportPresentation(for: selection.choice, registeredStops: row.registeredStops, notationMode: notationMode)
            let modeName = viewport.modeName
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
            let semanticType: String
            switch selection.choice {
            case .fixed:
                semanticType = kindName(.fixed)
            case .cplLoss:
                semanticType = TypeLabel.cpl
            case .gnd(.recordOnly):
                semanticType = "\(TypeLabel.gnd) \(gndModeName(.recordOnly))"
            case .gnd(.applyFullValue):
                semanticType = "\(TypeLabel.gnd) \(gndModeName(.applyFullValue))"
            }
            return FilterWheelRowDisplay(
                selection: row.selection,
                compactValueText: viewport.compactValue,
                typeLabel: viewport.typeLabel,
                modeLabel: viewport.modeLabel,
                typeCategory: viewport.typeCategory,
                registeredText: registered,
                itemName: name,
                expandedLabelText: segments.joined(separator: " · "),
                unavailabilityText: unavailabilityText,
                accessibilityValueText: accessibilityValue(
                    segments: [name, semanticType, contribution],
                    unavailabilityText: unavailabilityText
                ),
                isEmpty: false,
                isMounted: true
            )
        }
    }

    /// Viewport value and labels of a mounted row: Fixed and
    /// GND follow the global notation through the shared Standard
    /// formatter (numeric component only, GND showing its registered
    /// full density in both modes); CPL stays exposure loss in stops.
    private struct ViewportPresentation {
        let compactValue: String
        let typeLabel: String
        let modeLabel: String?
        let typeCategory: FilterRowTypeCategory
        let modeName: String?
    }

    private static func viewportPresentation(
        for choice: FilterRowChoice,
        registeredStops: Double,
        notationMode: NDNotationMode
    ) -> ViewportPresentation {
        let notationValue = NDNotationFormatter.display(forStops: registeredStops, mode: notationMode).value
        switch choice {
        case .fixed:
            return ViewportPresentation(compactValue: notationValue, typeLabel: TypeLabel.nd, modeLabel: nil, typeCategory: .nd, modeName: nil)
        case .cplLoss(let loss):
            return ViewportPresentation(compactValue: decimalStopsValue(loss), typeLabel: TypeLabel.cpl, modeLabel: nil, typeCategory: .cpl, modeName: nil)
        case .gnd(.recordOnly):
            return ViewportPresentation(
                compactValue: notationValue,
                typeLabel: TypeLabel.gnd,
                modeLabel: TypeLabel.rec,
                typeCategory: .gnd,
                modeName: gndModeName(.recordOnly)
            )
        case .gnd(.applyFullValue):
            return ViewportPresentation(
                compactValue: notationValue,
                typeLabel: TypeLabel.gnd,
                modeLabel: TypeLabel.full,
                typeCategory: .gnd,
                modeName: gndModeName(.applyFullValue)
            )
        }
    }

    /// Persistent type / mode label tokens above every wheel viewport
    /// (FILTER-STACK-007). Deliberately short so they stay complete at
    /// four wheels; identical on both platforms.
    public enum TypeLabel {
        public static let nd = String(localized: "ND")
        public static let cpl = String(localized: "CPL")
        public static let gnd = String(localized: "GND")
        public static let rec = String(localized: "REC")
        public static let full = String(localized: "FULL")
        public static let empty = String(localized: "EMPTY")
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

    /// Announced when an assistive adjustment reaches the plain end of
    /// the wheel with no rejected candidate on the way (FILTER-A11Y-004).
    public static func boundaryText() -> String {
        String(localized: "No more filters in this direction")
    }

    /// Announced once after automatic cleanup actually removed
    /// `count` empty wheels while a screen reader is active
    /// (FILTER-STACK-006): the wording names an empty filter wheel,
    /// never an item whose contribution happens to be zero.
    public static func emptyWheelRemovalText(count: Int) -> String {
        count == 1
            ? String(localized: "Empty filter wheel removed")
            : String(localized: "\(count) empty filter wheels removed")
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

    /// Stable VoiceOver identity of one wheel (FILTER-A11Y-001): only
    /// its position and source. The committed selection is exposed as
    /// the element's separate dynamic accessibility value.
    public static func wheelAccessibilityLabel(position: Int, wheelCount: Int, sourceName: String) -> String {
        String(localized: "Filter \(position) of \(wheelCount), \(sourceName)")
    }

    private static func accessibilityValue(
        segments: [String],
        unavailabilityText: String?
    ) -> String {
        (segments + [unavailabilityText].compactMap { $0 }).joined(separator: ", ")
    }

    /// The wheel element's dynamic VoiceOver value (FILTER-A11Y-005):
    /// the committed row's concise value — item or Empty, type or
    /// mode, canonical contribution — followed by the current complete
    /// Total, so a successful adjustment is heard as, for example,
    /// `Lee GND 0.9, GND Apply full value, 3 stops, Total 21.6 stops`.
    /// Rejected and boundary adjustments never reach this value; they
    /// announce their reason alone.
    public static func wheelAccessibilityValue(
        committed display: FilterWheelRowDisplay,
        total: NDStackTotalDisplayState
    ) -> String {
        "\(display.accessibilityValueText), \(FilterStatusRegionPresenter.totalText(total))"
    }

    /// VoiceOver hint of the Plus wheel (FILTER-PLUS-003, FILTER-A11Y-002):
    /// activating adds the displayed source; the adjustable value
    /// changes the displayed source without adding; management is a
    /// named action. No touch drag or long press is required.
    public static func plusAccessibilityHint(sourceName: String) -> String {
        String(localized: "Double-tap to add a filter from \(sourceName). Swipe up or down to choose Standard or a Filter Set. Use the actions to manage Filter Sets.")
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
