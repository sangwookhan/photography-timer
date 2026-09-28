// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Stable identity of a user-owned Filter Set. Names and colors are
/// presentation metadata; only this id participates in stack
/// references and captured summaries.
public struct FilterSetID: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() -> FilterSetID {
        FilterSetID(rawValue: UUID().uuidString)
    }
}

/// Stable identity of one physical filter. Two items with equal
/// names and values remain two distinct physical filters.
public struct FilterItemID: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() -> FilterItemID {
        FilterItemID(rawValue: UUID().uuidString)
    }
}

/// Fixed, platform-neutral color palette for Filter Sets. Persisted
/// by `rawValue` so both platforms map the same token to their own
/// color system. Duplicate colors across Filter Sets are allowed.
public enum FilterSetColor: String, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case brown

    /// Random suggestion for a new Filter Set that differs from the
    /// suggestion offered on the immediately preceding creation
    /// opening. With one color excluded there are always eleven
    /// candidates left, so the call never fails.
    public static func suggestion<G: RandomNumberGenerator>(
        excluding previous: FilterSetColor?,
        using generator: inout G
    ) -> FilterSetColor {
        let candidates = allCases.filter { $0 != previous }
        return candidates.randomElement(using: &generator) ?? .blue
    }

    public static func suggestion(excluding previous: FilterSetColor?) -> FilterSetColor {
        var generator = SystemRandomNumberGenerator()
        return suggestion(excluding: previous, using: &generator)
    }
}

/// Input unit of a registered filter value. Conversion to canonical
/// stops: Stops unchanged, `OD / 0.3`, `log2(ND factor)`.
public enum FilterValueUnit: String, CaseIterable, Sendable {
    case stops
    case opticalDensity
    case filterFactor
}

/// A registered Fixed or GND filter value as the user entered it —
/// the original value and unit are preserved for display, while
/// calculation consumes `canonicalStops`.
public struct FilterRegisteredValue: Hashable, Sendable {
    public let value: Double
    public let unit: FilterValueUnit

    public init(value: Double, unit: FilterValueUnit) {
        self.value = value
        self.unit = unit
    }

    /// Canonical stops, or `nil` when the value cannot be registered:
    /// non-finite, zero or negative stops, or above the 30-stop cap.
    /// An ND factor that exactly matches a commercial Standard label
    /// (`NDCommercialFactorMapping`) takes that label's ladder value —
    /// ND1000 is exactly 10 stops; any other factor uses `log2` without
    /// snapping.
    public var canonicalStops: Double? {
        Self.canonicalStops(value: value, unit: unit)
    }

    public var isValid: Bool {
        canonicalStops != nil
    }

    static func canonicalStops(value: Double, unit: FilterValueUnit) -> Double? {
        guard value.isFinite else {
            return nil
        }
        let stops: Double
        switch unit {
        case .stops:
            stops = value
        case .opticalDensity:
            stops = value / 0.3
        case .filterFactor:
            if let ladderStops = NDCommercialFactorMapping.canonicalStops(matchingCommercialFactor: value) {
                stops = ladderStops
            } else {
                stops = value > 0 ? log2(value) : -.infinity
            }
        }
        guard stops.isFinite,
              stops > 0,
              stops <= Double(ExposureScale.maximumWholeNDStops) + ExposureCalculator.stabilityEpsilon else {
            return nil
        }
        return stops
    }
}

/// Parses user-entered decimal text for filter registration. Accepts
/// either `.` or `,` as the decimal separator so locale keyboards,
/// pasted text, and hardware keyboards normalize to one rule.
public enum FilterDecimalInput {
    static func normalizedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
    }

    /// General decimal parse (Fixed / GND values). `nil` for empty or
    /// non-numeric text.
    public static func parseDecimal(_ text: String) -> Double? {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty,
              normalized.range(of: "^[0-9]+(\\.[0-9]+)?$|^\\.[0-9]+$", options: .regularExpression) != nil,
              let value = Double(normalized) else {
            return nil
        }
        return value
    }

    /// CPL exposure-loss field parse: one integer digit, at most one
    /// fractional digit, in the closed range 0.1–9.9. `.empty` for
    /// blank text, `.invalid` for anything else.
    public enum CPLFieldParse: Equatable, Sendable {
        case empty
        case value(Double)
        case invalid
    }

    public static func parseCPLField(_ text: String) -> CPLFieldParse {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else {
            return .empty
        }
        guard normalized.range(of: "^[0-9](\\.[0-9])?$", options: .regularExpression) != nil,
              let value = Double(normalized),
              CPLExposureLossChoices.isValidChoice(value) else {
            return .invalid
        }
        return .value(value)
    }
}

/// The three user-editable CPL exposure-loss choices. A field may be
/// empty (omits a choice); at least one field must hold a valid value.
public struct CPLExposureLossChoices: Hashable, Sendable {
    public static let fieldCount = 3
    static let range: ClosedRange<Double> = 0.1...9.9
    /// Shipping defaults for a new CPL item: 1, 1.5, and 2 stops.
    public static let defaults = CPLExposureLossChoices(fields: [1, 1.5, 2])

    /// Exactly three slots; `nil` is an empty field.
    public let fields: [Double?]

    public init(fields: [Double?]) {
        var padded = Array(fields.prefix(Self.fieldCount))
        while padded.count < Self.fieldCount {
            padded.append(nil)
        }
        self.fields = padded
    }

    /// A choice is valid when it is finite, inside 0.1–9.9, and has
    /// at most one fractional digit (so `1.25` is rejected).
    static func isValidChoice(_ value: Double) -> Bool {
        guard value.isFinite, range.contains(value) else {
            return false
        }
        let tenths = value * 10
        return abs(tenths - tenths.rounded()) <= ExposureCalculator.stabilityEpsilon
    }

    public var isValid: Bool {
        let present = fields.compactMap { $0 }
        return !present.isEmpty && present.allSatisfy(Self.isValidChoice)
    }

    /// Distinct valid choices in ascending order — the rows the
    /// shooting wheel offers for this item. Duplicates appear once.
    public var shootingChoices: [Double] {
        var seen: [Double] = []
        for value in fields.compactMap({ $0 }) where Self.isValidChoice(value) {
            if !seen.contains(where: { abs($0 - value) <= ExposureCalculator.stabilityEpsilon }) {
                seen.append(value)
            }
        }
        return seen.sorted()
    }
}

/// Per-shot GND calculation mode.
public enum GNDCalculationMode: String, CaseIterable, Sendable {
    /// The GND is mounted and recorded; it contributes 0 stops.
    case recordOnly
    /// The GND contributes its complete registered value.
    case applyFullValue
}

/// Behavior kind of a physical item — chosen explicitly by the user,
/// never inferred from the name. `fixed` is the ND kind: the only
/// kind an ND wheel offers. CPL, GND, Color, and Effect are auxiliary
/// kinds, mounted through the shooting selection surface instead.
public enum FilterItemKind: String, CaseIterable, Sendable {
    case fixed
    case cpl
    case gnd
    case color
    case effect

    /// Whether items of this kind are mounted as auxiliary filters
    /// rather than selected on an ND wheel (FILTER-ITEM-003).
    public var isAuxiliary: Bool {
        self != .fixed
    }
}

/// Optical color of a Color filter (FILTER-COLOR-001) — equipment
/// identity separate from the source-set color and from the loss.
/// Persisted by `rawValue`, shared by both platforms.
public enum FilterOpticalColor: String, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case yellowGreen
    case green
}

/// User-supplied exposure loss of a Color or Effect filter, in stops
/// (FILTER-COLOR-001/002). Distinct from `FilterRegisteredValue`: no
/// unit conversion, and zero is allowed so a filter with no measurable
/// loss can still be mounted and recorded. Valid when finite and in
/// the closed range 0–30 stops.
public struct FilterExposureLoss: Hashable, Sendable {
    public static let range: ClosedRange<Double> = 0...Double(ExposureScale.maximumWholeNDStops)

    public let stops: Double

    public init(stops: Double) {
        self.stops = stops
    }

    public var isValid: Bool {
        stops.isFinite && Self.range.contains(stops)
    }
}

public enum FilterItemBehavior: Hashable, Sendable {
    case fixed(FilterRegisteredValue)
    case cpl(CPLExposureLossChoices)
    case gnd(FilterRegisteredValue)
    /// A Color filter: its optical color and its explicit loss.
    case color(FilterExposureLoss, FilterOpticalColor)
    /// An Effect filter (for example a night light-pollution filter)
    /// with its explicit loss.
    case effect(FilterExposureLoss)

    public var kind: FilterItemKind {
        switch self {
        case .fixed: return .fixed
        case .cpl: return .cpl
        case .gnd: return .gnd
        case .color: return .color
        case .effect: return .effect
        }
    }

    /// Registered full-density value for Fixed and GND items; the
    /// other kinds carry choices or a plain loss instead.
    public var registeredValue: FilterRegisteredValue? {
        switch self {
        case .fixed(let value), .gnd(let value):
            return value
        case .cpl, .color, .effect:
            return nil
        }
    }

    /// The explicit loss of a Color or Effect item; `nil` otherwise.
    public var exposureLoss: FilterExposureLoss? {
        switch self {
        case .color(let loss, _), .effect(let loss):
            return loss
        case .fixed, .cpl, .gnd:
            return nil
        }
    }

    /// The optical color of a Color item; `nil` otherwise.
    public var opticalColor: FilterOpticalColor? {
        if case .color(_, let color) = self {
            return color
        }
        return nil
    }

    public var isValid: Bool {
        switch self {
        case .fixed(let value), .gnd(let value):
            return value.isValid
        case .cpl(let choices):
            return choices.isValid
        case .color(let loss, _), .effect(let loss):
            return loss.isValid
        }
    }
}

/// One physical filter with a stable id. Equal names, kinds, units,
/// and values do not make two items the same item.
public struct FilterItem: Identifiable, Hashable, Sendable {
    public let id: FilterItemID
    public var name: String
    public var behavior: FilterItemBehavior

    public init(id: FilterItemID = .generate(), name: String, behavior: FilterItemBehavior) {
        self.id = id
        self.name = name
        self.behavior = behavior
    }

    public var isWellFormed: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && behavior.isValid
    }
}

/// A user-owned, ordered group of physical filters with a stable id,
/// a non-empty name, and a required color.
public struct FilterSet: Identifiable, Hashable, Sendable {
    public let id: FilterSetID
    public var name: String
    public var color: FilterSetColor
    public var items: [FilterItem]

    public init(id: FilterSetID = .generate(), name: String, color: FilterSetColor, items: [FilterItem] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.items = items
    }

    public var isWellFormed: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func item(withID id: FilterItemID) -> FilterItem? {
        items.first { $0.id == id }
    }

    /// The set's ND items — the only items an ND wheel offers
    /// (FILTER-STACK-003).
    public var ndItems: [FilterItem] {
        items.filter { !$0.behavior.kind.isAuxiliary }
    }

    /// The set's auxiliary items (CPL, GND, Color, Effect), mounted
    /// through shooting selection.
    public var auxiliaryItems: [FilterItem] {
        items.filter { $0.behavior.kind.isAuxiliary }
    }
}

/// The complete user inventory: Filter Sets in user-defined display
/// order. Standard is a fixed built-in source that always precedes
/// every Filter Set.
public struct FilterInventory: Hashable, Sendable {
    public var filterSets: [FilterSet]

    public init(filterSets: [FilterSet] = []) {
        self.filterSets = filterSets
    }

    public static let empty = FilterInventory()

    public func filterSet(withID id: FilterSetID) -> FilterSet? {
        filterSets.first { $0.id == id }
    }

    public func item(withID id: FilterItemID) -> (filterSet: FilterSet, item: FilterItem)? {
        for filterSet in filterSets {
            if let item = filterSet.item(withID: id) {
                return (filterSet, item)
            }
        }
        return nil
    }

    /// Filter Sources in selection order: Standard, then Filter Sets
    /// in their user-defined order.
    public var sources: [FilterSource] {
        [.standard] + filterSets.map { .filterSet($0.id) }
    }

    /// Position of `source` in `sources`; unknown Filter Sets sort
    /// after every known source so a stale reference never jumps
    /// ahead of real ones.
    func sourceOrderIndex(of source: FilterSource) -> Int {
        sources.firstIndex(of: source) ?? sources.count
    }

    public func contains(_ source: FilterSource) -> Bool {
        switch source {
        case .standard:
            return true
        case .filterSet(let id):
            return filterSet(withID: id) != nil
        }
    }
}
