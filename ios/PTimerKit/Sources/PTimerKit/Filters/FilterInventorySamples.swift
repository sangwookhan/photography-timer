// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

extension FilterInventory {
    /// The three editable example Filter Sets (FILTER-SET-008): ordinary
    /// inventory with new stable ids, none of them selected for a camera.
    /// The Set and item names are fixed example data and stay English in
    /// every locale (L10N-011); the exposure losses are explicit example
    /// metadata, never inferred from a name.
    public static func samples() -> FilterInventory {
        func nd(_ name: String, _ value: Double, _ unit: FilterValueUnit) -> FilterItem {
            FilterItem(name: name, behavior: .fixed(FilterRegisteredValue(value: value, unit: unit)))
        }
        func color(_ name: String, _ stops: Double, _ swatch: FilterSetColor) -> FilterItem {
            FilterItem(name: name, behavior: .color(FilterExposureLoss(stops: stops), swatch))
        }
        return FilterInventory(filterSets: [
            FilterSet(
                name: "Digital Magnetic Filters",
                color: .teal,
                items: [
                    nd("ND8", 3, .stops),
                    nd("ND64", 6, .stops),
                    nd("ND1000", 10, .stops),
                    nd("ND100k", 100_000, .filterFactor),
                    FilterItem(name: "Night Filter", behavior: .effect(FilterExposureLoss(stops: 0.3))),
                ]
            ),
            FilterSet(
                name: "Film Square ND/GND",
                color: .purple,
                items: [
                    nd("ND400", 400, .filterFactor),
                    nd("2-stop ND", 2, .stops),
                    nd("3-stop ND", 3, .stops),
                    nd("4-stop ND", 4, .stops),
                    FilterItem(name: "3-stop Soft GND", behavior: .gnd(FilterRegisteredValue(value: 3, unit: .stops))),
                ]
            ),
            FilterSet(
                name: "Film Color Filters",
                color: .orange,
                items: [
                    color("Red Filter", 3, .red),
                    color("Orange Filter", 2, .orange),
                    color("Yellow Filter", 1, .yellow),
                    FilterItem(name: "CPL", behavior: .cpl(CPLExposureLossChoices(fields: [1, 1.5, 2]))),
                ]
            ),
        ])
    }
}
