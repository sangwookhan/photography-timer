// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterExposureLoss
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterValueUnit

/**
 * The three editable example Filter Sets (FILTER-SET-008): ordinary
 * inventory with new stable ids on every call, none of them selected for a
 * camera. The Set and item names are fixed example data and stay English in
 * every locale (L10N-011); the exposure losses are explicit example
 * metadata, never inferred from a name.
 * (iOS: `FilterInventory.samples()`.)
 */
object FilterInventorySamples {
    fun inventory(): FilterInventory {
        fun nd(name: String, value: Double, unit: FilterValueUnit) =
            FilterItem(name, FilterItemBehavior.Fixed(FilterRegisteredValue(value, unit)))
        fun color(name: String, stops: Double, swatch: FilterSetColor) =
            FilterItem(name, FilterItemBehavior.Color(FilterExposureLoss(stops), swatch))
        return FilterInventory(
            listOf(
                FilterSet(
                    "Digital Magnetic Filters",
                    FilterSetColor.teal,
                    listOf(
                        nd("ND8", 3.0, FilterValueUnit.stops),
                        nd("ND64", 6.0, FilterValueUnit.stops),
                        nd("ND1000", 10.0, FilterValueUnit.stops),
                        nd("ND100k", 100_000.0, FilterValueUnit.filterFactor),
                        FilterItem("Night Filter", FilterItemBehavior.Effect(FilterExposureLoss(0.3))),
                    ),
                ),
                FilterSet(
                    "Film Square ND/GND",
                    FilterSetColor.purple,
                    listOf(
                        nd("ND400", 400.0, FilterValueUnit.filterFactor),
                        nd("2-stop ND", 2.0, FilterValueUnit.stops),
                        nd("3-stop ND", 3.0, FilterValueUnit.stops),
                        nd("4-stop ND", 4.0, FilterValueUnit.stops),
                        FilterItem("3-stop Soft GND", FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops))),
                    ),
                ),
                FilterSet(
                    "Film Color Filters",
                    FilterSetColor.orange,
                    listOf(
                        color("Red Filter", 3.0, FilterSetColor.red),
                        color("Orange Filter", 2.0, FilterSetColor.orange),
                        color("Yellow Filter", 1.0, FilterSetColor.yellow),
                        FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0)))),
                    ),
                ),
            ),
        )
    }
}
