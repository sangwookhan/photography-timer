// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

extension FilterInventory {
    /// The editable example Sets a fresh installation starts with
    /// (FILTER-SET-008): ordinary inventory with new stable ids, none of
    /// them selected for a camera. Set names follow the app language at
    /// first launch and are user data afterwards. The Color losses are
    /// the manufacturer's stop compensations for those named models.
    public static func samples() -> FilterInventory {
        func nd(_ name: String, _ value: Double, _ unit: FilterValueUnit) -> FilterItem {
            FilterItem(name: name, behavior: .fixed(FilterRegisteredValue(value: value, unit: unit)))
        }
        func color(_ name: String, _ stops: Double, _ swatch: FilterSetColor) -> FilterItem {
            FilterItem(name: name, behavior: .color(FilterExposureLoss(stops: stops), swatch))
        }
        return FilterInventory(filterSets: [
            FilterSet(
                name: String(localized: "Sample ND"),
                color: .teal,
                items: [nd("ND8", 3, .stops), nd("ND64", 6, .stops), nd("ND1000", 10, .stops)]
            ),
            FilterSet(
                name: String(localized: "Sample ND — Extended"),
                color: .purple,
                items: [
                    nd("ND100", 100, .filterFactor),
                    nd("ND200", 200, .filterFactor),
                    nd("ND400", 400, .filterFactor),
                    nd("ND100k", 100_000, .filterFactor),
                ]
            ),
            FilterSet(
                name: String(localized: "Sample Aux Filter Set"),
                color: .orange,
                items: [
                    FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2]))),
                    color("B+W 091 Red Dark", 3, .red),
                    color("B+W 040 Orange", 2, .orange),
                    color("B+W 022 Yellow", 1, .yellow),
                    FilterItem(name: "GND 2 stops", behavior: .gnd(FilterRegisteredValue(value: 2, unit: .stops))),
                ]
            ),
        ])
    }
}
