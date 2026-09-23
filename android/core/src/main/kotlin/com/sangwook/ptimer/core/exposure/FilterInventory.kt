// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.exposure.ExposureCalculator.Companion.STABILITY_EPSILON
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.math.abs
import kotlin.math.log2
import kotlin.random.Random

/**
 * Stable identity of a user-owned Filter Set. Names and colors are
 * presentation metadata; only this id participates in stack references
 * and captured summaries. (iOS: `FilterSetID`.)
 */
data class FilterSetId(val rawValue: String) {
    companion object {
        fun generate(): FilterSetId = FilterSetId(UUID.randomUUID().toString())
    }
}

/**
 * Stable identity of one physical filter. Two items with equal names
 * and values remain two distinct physical filters. (iOS: `FilterItemID`.)
 */
data class FilterItemId(val rawValue: String) {
    companion object {
        fun generate(): FilterItemId = FilterItemId(UUID.randomUUID().toString())
    }
}

/**
 * Fixed, platform-neutral color palette for Filter Sets. Persisted by
 * [name] so both platforms map the same token to their own color
 * system. Duplicate colors across Filter Sets are allowed.
 * (iOS: `FilterSetColor`.)
 */
enum class FilterSetColor {
    red,
    orange,
    yellow,
    green,
    mint,
    teal,
    cyan,
    blue,
    indigo,
    purple,
    pink,
    brown;

    companion object {
        /** Fail-safe parse: an unknown/missing token restores as [blue]. */
        fun fromToken(token: String?): FilterSetColor =
            entries.firstOrNull { it.name == token } ?: blue

        /**
         * Random suggestion for a new Filter Set that differs from the
         * suggestion offered on the immediately preceding creation
         * opening. With one color excluded there are always eleven
         * candidates left, so the call never fails.
         */
        fun suggestion(excluding: FilterSetColor?, random: Random = Random.Default): FilterSetColor =
            entries.filter { it != excluding }.random(random)
    }
}

/**
 * Input unit of a registered filter value. Conversion to canonical
 * stops: Stops unchanged, `OD / 0.3`, `log2(ND factor)`. Persisted by
 * [name]; the tokens are part of the on-disk contract.
 * (iOS: `FilterValueUnit`.)
 */
@Serializable
enum class FilterValueUnit {
    @SerialName("stops")
    stops,

    @SerialName("opticalDensity")
    opticalDensity,

    @SerialName("filterFactor")
    filterFactor;

    companion object {
        fun fromToken(token: String?): FilterValueUnit? = entries.firstOrNull { it.name == token }
    }
}

/**
 * A registered Fixed or GND filter value as the user entered it — the
 * original value and unit are preserved for display, while calculation
 * consumes [canonicalStops]. (iOS: `FilterRegisteredValue`.)
 */
data class FilterRegisteredValue(val value: Double, val unit: FilterValueUnit) {

    /**
     * Canonical stops, or `null` when the value cannot be registered:
     * non-finite, zero or negative stops, or above the 30-stop cap
     * (FILTER-ITEM-004). An ND factor that exactly matches a commercial
     * Standard label ([NDCommercialFactorMapping]) takes that label's
     * ladder value — ND1000 is exactly 10 stops; any other factor uses
     * `log2` without snapping.
     */
    val canonicalStops: Double?
        get() {
            if (!value.isFinite()) return null
            val stops = when (unit) {
                FilterValueUnit.stops -> value
                FilterValueUnit.opticalDensity -> value / 0.3
                FilterValueUnit.filterFactor ->
                    NDCommercialFactorMapping.canonicalStops(matchingCommercialFactor = value)
                        ?: if (value > 0) log2(value) else Double.NEGATIVE_INFINITY
            }
            val withinCap = stops <= ExposureScale.MAXIMUM_WHOLE_ND_STOPS + STABILITY_EPSILON
            return if (stops.isFinite() && stops > 0 && withinCap) stops else null
        }

    val isValid: Boolean get() = canonicalStops != null
}

/**
 * Parses user-entered decimal text for filter registration. Accepts
 * either `.` or `,` as the decimal separator so locale keyboards,
 * pasted text, and hardware keyboards normalize to one rule
 * (FILTER-CPL-003). (iOS: `FilterDecimalInput`.)
 */
object FilterDecimalInput {
    private val decimalPattern = Regex("^[0-9]+(\\.[0-9]+)?$|^\\.[0-9]+$")
    private val cplFieldPattern = Regex("^[0-9](\\.[0-9])?$")

    internal fun normalizedText(text: String): String = text.trim().replace(',', '.')

    /**
     * General decimal parse (Fixed / GND values). `null` for empty or
     * non-numeric text.
     */
    fun parseDecimal(text: String): Double? {
        val normalized = normalizedText(text)
        if (!decimalPattern.matches(normalized)) return null
        return normalized.toDoubleOrNull()
    }

    /**
     * CPL exposure-loss field parse: one integer digit, at most one
     * fractional digit, in the closed range 0.1–9.9 (FILTER-CPL-002).
     */
    sealed class CplFieldParse {
        /** Blank text — the field omits a choice. */
        data object Empty : CplFieldParse()

        data class Value(val stops: Double) : CplFieldParse()

        data object Invalid : CplFieldParse()
    }

    fun parseCplField(text: String): CplFieldParse {
        val normalized = normalizedText(text)
        if (normalized.isEmpty()) return CplFieldParse.Empty
        if (!cplFieldPattern.matches(normalized)) return CplFieldParse.Invalid
        val value = normalized.toDoubleOrNull() ?: return CplFieldParse.Invalid
        return if (CplExposureLossChoices.isValidChoice(value)) {
            CplFieldParse.Value(value)
        } else {
            CplFieldParse.Invalid
        }
    }
}

/**
 * The three user-editable CPL exposure-loss choices. A field may be
 * empty (omits a choice); at least one field must hold a valid value
 * (FILTER-CPL-001/002). (iOS: `CPLExposureLossChoices`.)
 */
class CplExposureLossChoices(fields: List<Double?>) {

    /** Exactly three slots; `null` is an empty field. */
    val fields: List<Double?> = List(FIELD_COUNT) { fields.getOrNull(it) }

    val isValid: Boolean
        get() {
            val present = fields.filterNotNull()
            return present.isNotEmpty() && present.all { isValidChoice(it) }
        }

    /**
     * Distinct valid choices in ascending order — the rows the shooting
     * wheel offers for this item. Duplicates appear once.
     */
    val shootingChoices: List<Double>
        get() {
            val seen = ArrayList<Double>()
            for (value in fields.filterNotNull()) {
                if (!isValidChoice(value)) continue
                if (seen.none { abs(it - value) <= STABILITY_EPSILON }) seen.add(value)
            }
            return seen.sorted()
        }

    override fun equals(other: Any?): Boolean =
        this === other || (other is CplExposureLossChoices && other.fields == fields)

    override fun hashCode(): Int = fields.hashCode()

    override fun toString(): String = "CplExposureLossChoices(fields=$fields)"

    companion object {
        const val FIELD_COUNT: Int = 3
        private val range = 0.1..9.9

        /** Shipping defaults for a new CPL item: 1, 1.5, and 2 stops. */
        val defaults = CplExposureLossChoices(listOf(1.0, 1.5, 2.0))

        /**
         * A choice is valid when it is finite, inside 0.1–9.9, and has at
         * most one fractional digit (so `1.25` is rejected).
         */
        fun isValidChoice(value: Double): Boolean {
            if (!value.isFinite() || value !in range) return false
            val tenths = value * 10
            return abs(tenths - tenths.swiftRounded()) <= STABILITY_EPSILON
        }
    }
}

/**
 * Per-shot GND calculation mode (FILTER-GND-001). Persisted by [name].
 * (iOS: `GNDCalculationMode`.)
 */
enum class GndCalculationMode {
    /** The GND is mounted and recorded; it contributes 0 stops. */
    recordOnly,

    /** The GND contributes its complete registered value. */
    applyFullValue;

    companion object {
        fun fromToken(token: String?): GndCalculationMode? = entries.firstOrNull { it.name == token }
    }
}

/**
 * Behavior kind of a physical item — chosen explicitly by the user,
 * never inferred from the name (FILTER-ITEM-003). Persisted by [name].
 * (iOS: `FilterItemKind`.)
 */
@Serializable
enum class FilterItemKind {
    @SerialName("fixed")
    fixed,

    @SerialName("cpl")
    cpl,

    @SerialName("gnd")
    gnd;

    companion object {
        fun fromToken(token: String?): FilterItemKind? = entries.firstOrNull { it.name == token }
    }
}

/** (iOS: `FilterItemBehavior`.) */
sealed class FilterItemBehavior {
    data class Fixed(val value: FilterRegisteredValue) : FilterItemBehavior()
    data class Cpl(val choices: CplExposureLossChoices) : FilterItemBehavior()
    data class Gnd(val value: FilterRegisteredValue) : FilterItemBehavior()

    val kind: FilterItemKind
        get() = when (this) {
            is Fixed -> FilterItemKind.fixed
            is Cpl -> FilterItemKind.cpl
            is Gnd -> FilterItemKind.gnd
        }

    /**
     * Registered full-density value for Fixed and GND items; CPL items
     * carry choices instead.
     */
    val registeredValue: FilterRegisteredValue?
        get() = when (this) {
            is Fixed -> value
            is Gnd -> value
            is Cpl -> null
        }

    val isValid: Boolean
        get() = when (this) {
            is Fixed -> value.isValid
            is Gnd -> value.isValid
            is Cpl -> choices.isValid
        }
}

/**
 * One physical filter with a stable id. Equal names, kinds, units, and
 * values do not make two items the same item (FILTER-ITEM-002).
 * (iOS: `FilterItem`.)
 */
data class FilterItem(
    val name: String,
    val behavior: FilterItemBehavior,
    val id: FilterItemId = FilterItemId.generate(),
) {
    val isWellFormed: Boolean get() = name.trim().isNotEmpty() && behavior.isValid
}

/**
 * A user-owned, ordered group of physical filters with a stable id, a
 * non-empty name, and a required color (FILTER-SET-002).
 * (iOS: `FilterSet`.)
 */
data class FilterSet(
    val name: String,
    val color: FilterSetColor,
    val items: List<FilterItem> = emptyList(),
    val id: FilterSetId = FilterSetId.generate(),
) {
    val isWellFormed: Boolean get() = name.trim().isNotEmpty()

    fun item(withId: FilterItemId): FilterItem? = items.firstOrNull { it.id == withId }
}

/**
 * The complete user inventory: Filter Sets in user-defined display
 * order. Standard is a fixed built-in source that always precedes every
 * Filter Set (FILTER-SET-004). (iOS: `FilterInventory`.)
 */
data class FilterInventory(val filterSets: List<FilterSet> = emptyList()) {

    fun filterSet(withId: FilterSetId): FilterSet? = filterSets.firstOrNull { it.id == withId }

    fun item(withId: FilterItemId): Pair<FilterSet, FilterItem>? {
        for (filterSet in filterSets) {
            val item = filterSet.item(withId)
            if (item != null) return filterSet to item
        }
        return null
    }

    /**
     * Filter Sources in selection order: Standard, then Filter Sets in
     * their user-defined order.
     */
    val sources: List<FilterSource>
        get() = listOf(FilterSource.Standard) + filterSets.map { FilterSource.FilterSet(it.id) }

    /**
     * Position of [source] in [sources]; unknown Filter Sets sort after
     * every known source so a stale reference never jumps ahead of real
     * ones.
     */
    internal fun sourceOrderIndex(source: FilterSource): Int =
        sources.indexOf(source).takeIf { it >= 0 } ?: sources.size

    fun contains(source: FilterSource): Boolean = when (source) {
        is FilterSource.Standard -> true
        is FilterSource.FilterSet -> filterSet(source.id) != null
    }

    companion object {
        val empty = FilterInventory()
    }
}
