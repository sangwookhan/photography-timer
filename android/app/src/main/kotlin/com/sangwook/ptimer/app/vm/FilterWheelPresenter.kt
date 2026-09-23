// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheelRowOption
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Semantic type of a filter wheel candidate (FILTER-STACK-007): the
 * category behind the row's type-color rail. GND Record only and Apply
 * full value share one category; the persistent label carries the mode.
 * Independent of the user-selected Filter Set color.
 * (iOS: `FilterRowTypeCategory`.)
 */
enum class FilterRowTypeCategory { nd, cpl, gnd, empty }

/**
 * How one picker row of a filter wheel reads (FILTER-STACK-003/007).
 * Numeric text is resolved here; every other field stays structured so
 * the display layer localizes type words, modes, and rejection reasons
 * at render time (Android canonical-vocabulary rule).
 * (iOS: `FilterWheelRowDisplay`.)
 */
data class FilterWheelRowUiState(
    val selection: FilterWheelSelection,
    /**
     * Numeric-only value for the scrolling viewport: Standard, Fixed and
     * GND values in the app-global notation through the shared Standard
     * formatter (10 stops → `10` / `3.0` / `1000`), CPL exposure loss in
     * stops regardless of notation (`1.5`), and canonical zero for Empty
     * (`0` / `0.0` / `1`).
     */
    val compactValueText: String,
    val typeCategory: FilterRowTypeCategory,
    /** `REC` / `FULL` state of a GND row; `null` for every other row. */
    val gndMode: GndCalculationMode? = null,
    /** Full item name for the expanded moving label; `null` for Standard and Empty. */
    val itemName: String? = null,
    /** The Fixed / GND value as the user entered it; `null` otherwise. */
    val registeredValue: FilterRegisteredValue? = null,
    /** The selected CPL exposure-loss choice in stops; `null` otherwise. */
    val cplLossStops: Double? = null,
    val contributionStops: Double,
    val registeredStops: Double,
    /** Why the row is unavailable on this wheel; `null` when selectable. */
    val unavailability: FilterStackRejection? = null,
) {
    val isAvailable: Boolean get() = unavailability == null

    /** Whether an overscroll pull may remove a wheel resting on this
     *  row; see [FilterWheelSelection.isCleanable]. */
    val isCleanable: Boolean get() = selection.isCleanable
}

/**
 * Pure-value transforms from resolved filter rows into display text. One
 * place owns every numeric rendering of a Filter Set row so the wheel,
 * the status region, and the captured timer reference agree.
 * (iOS: `FilterWheelPresenter`.)
 */
object FilterWheelPresenter {

    /** Canonical source name: `Standard` or the Filter Set's own name. */
    fun sourceName(source: FilterSource, inventory: FilterInventory): String = when (source) {
        is FilterSource.Standard -> STANDARD_SOURCE_NAME
        is FilterSource.FilterSet -> inventory.filterSet(source.id)?.name ?: FALLBACK_FILTER_SET_NAME
    }

    fun row(option: FilterWheelRowOption, notationMode: NDNotationMode): FilterWheelRowUiState {
        val row = option.row
        val base = FilterWheelRowUiState(
            selection = row.selection,
            compactValueText = "",
            typeCategory = FilterRowTypeCategory.empty,
            contributionStops = row.contributionStops,
            registeredStops = row.registeredStops,
            unavailability = option.unavailability,
        )
        return when (val selection = row.selection) {
            is FilterWheelSelection.Standard -> base.copy(
                compactValueText = notationValue(selection.stops, notationMode),
                typeCategory = FilterRowTypeCategory.nd,
            )

            // Empty renders canonical zero through the shared Standard
            // formatter so it reads like Standard zero; the EMPTY label and
            // the status text keep the distinct no-filter-mounted meaning.
            is FilterWheelSelection.Empty -> base.copy(
                compactValueText = notationValue(0.0, notationMode),
                typeCategory = FilterRowTypeCategory.empty,
            )

            is FilterWheelSelection.Item -> {
                val registered = row.item?.behavior?.registeredValue
                when (val choice = selection.selection.choice) {
                    is FilterRowChoice.Fixed -> base.copy(
                        compactValueText = notationValue(row.registeredStops, notationMode),
                        typeCategory = FilterRowTypeCategory.nd,
                        itemName = row.item?.name,
                        registeredValue = registered,
                    )

                    // CPL choices are exposure loss in stops and stay plain
                    // decimals independently of the global notation.
                    is FilterRowChoice.CplLoss -> base.copy(
                        compactValueText = decimalStopsValue(choice.stops),
                        typeCategory = FilterRowTypeCategory.cpl,
                        itemName = row.item?.name,
                        cplLossStops = choice.stops,
                    )

                    // A Record-only GND still displays its registered full
                    // density; REC communicates the zero contribution.
                    is FilterRowChoice.Gnd -> base.copy(
                        compactValueText = notationValue(row.registeredStops, notationMode),
                        typeCategory = FilterRowTypeCategory.gnd,
                        gndMode = choice.mode,
                        itemName = row.item?.name,
                        registeredValue = registered,
                    )
                }
            }
        }
    }

    private fun notationValue(stops: Double, mode: NDNotationMode): String =
        NDNotationFormatter.display(stops, mode).value

    /** Canonical `N stops` / `1 stop` text for a contribution. */
    fun stopsText(stops: Double): String =
        if (abs(stops - 1) <= ExposureCalculator.STABILITY_EPSILON) {
            "1 $STOP_SINGULAR"
        } else {
            "${decimalStopsValue(stops)} $STOP_PLURAL"
        }

    /**
     * Plain decimal rendering of a registered or contributed stops value:
     * whole values as integers, otherwise up to two trimmed decimals
     * (`1.5`, `3.33`, `6.6`). Filter Item values are user decimals — never
     * ladder values — so they deliberately bypass the Standard ladder's
     * mixed-fraction notation.
     */
    fun decimalStopsValue(stops: Double): String = trimmed(stops, decimals = 2)

    /** Trimmed three-decimal rendering of a registered numeric value. */
    fun trimmedNumber(value: Double): String = trimmed(value, decimals = 3)

    /**
     * Original registered representation for the editor, the status
     * region, and the captured reference: `OD 0.9`, `ND8`, or `3 stops`.
     */
    fun registeredValueText(value: FilterRegisteredValue): String {
        val number = trimmedNumber(value.value)
        return when (value.unit) {
            FilterValueUnit.stops -> stopsText(value.value)
            FilterValueUnit.opticalDensity -> "$OPTICAL_DENSITY_PREFIX$number"
            FilterValueUnit.filterFactor -> "$FILTER_FACTOR_PREFIX$number"
        }
    }

    private fun trimmed(value: Double, decimals: Int): String {
        if (abs(value - value.roundToLong()) <= ExposureCalculator.STABILITY_EPSILON) {
            return value.roundToLong().toString()
        }
        var text = String.format(Locale.US, "%.${decimals}f", value)
        while (text.contains('.') && text.endsWith('0')) text = text.dropLast(1)
        if (text.endsWith('.')) text = text.dropLast(1)
        return text
    }

    /** Canonical English vocabulary; the display layer localizes it. */
    const val STANDARD_SOURCE_NAME: String = "Standard"
    const val FALLBACK_FILTER_SET_NAME: String = "Filter Set"
    const val FALLBACK_ITEM_NAME: String = "Filter"
    const val RECORD_ONLY_MODE_NAME: String = "Record only"
    const val APPLY_FULL_VALUE_MODE_NAME: String = "Apply full value"
    const val STOP_SINGULAR: String = "stop"
    const val STOP_PLURAL: String = "stops"
    private const val OPTICAL_DENSITY_PREFIX = "OD "
    private const val FILTER_FACTOR_PREFIX = "ND"

    fun gndModeName(mode: GndCalculationMode): String = when (mode) {
        GndCalculationMode.recordOnly -> RECORD_ONLY_MODE_NAME
        GndCalculationMode.applyFullValue -> APPLY_FULL_VALUE_MODE_NAME
    }
}
