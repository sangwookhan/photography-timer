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
 * The editable example Sets a fresh installation starts with
 * (FILTER-SET-008): ordinary inventory with new stable ids, none of them
 * selected for a camera. Set names come from the app language at first
 * launch and are user data afterwards. The Color losses are the
 * manufacturer's stop compensations for those named models.
 * (iOS: `FilterInventory.samples()`.)
 */
object FilterInventorySamples {
    fun inventory(sampleNdName: String, sampleNdExtendedName: String, sampleAuxName: String): FilterInventory {
        fun nd(name: String, value: Double, unit: FilterValueUnit) =
            FilterItem(name, FilterItemBehavior.Fixed(FilterRegisteredValue(value, unit)))
        fun color(name: String, stops: Double, swatch: FilterSetColor) =
            FilterItem(name, FilterItemBehavior.Color(FilterExposureLoss(stops), swatch))
        return FilterInventory(
            listOf(
                FilterSet(
                    sampleNdName,
                    FilterSetColor.teal,
                    listOf(nd("ND8", 3.0, FilterValueUnit.stops), nd("ND64", 6.0, FilterValueUnit.stops), nd("ND1000", 10.0, FilterValueUnit.stops)),
                ),
                FilterSet(
                    sampleNdExtendedName,
                    FilterSetColor.purple,
                    listOf(
                        nd("ND100", 100.0, FilterValueUnit.filterFactor),
                        nd("ND200", 200.0, FilterValueUnit.filterFactor),
                        nd("ND400", 400.0, FilterValueUnit.filterFactor),
                        nd("ND100k", 100_000.0, FilterValueUnit.filterFactor),
                    ),
                ),
                FilterSet(
                    sampleAuxName,
                    FilterSetColor.orange,
                    listOf(
                        FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0)))),
                        color("B+W 091 Red Dark", 3.0, FilterSetColor.red),
                        color("B+W 040 Orange", 2.0, FilterSetColor.orange),
                        color("B+W 022 Yellow", 1.0, FilterSetColor.yellow),
                        FilterItem("GND 2 stops", FilterItemBehavior.Gnd(FilterRegisteredValue(2.0, FilterValueUnit.stops))),
                    ),
                ),
            ),
        )
    }
}
