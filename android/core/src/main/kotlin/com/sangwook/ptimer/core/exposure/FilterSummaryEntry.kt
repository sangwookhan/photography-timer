// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive

/**
 * Immutable per-wheel summary captured when a timer starts
 * (FILTER-PERSIST-003). Carries enough to reconstruct the shot basis —
 * source kind, Filter Set id and name, item id and name, the original
 * registered value and unit, canonical stops, the selected calculation
 * mode, and the stops actually contributed. Later inventory edits never
 * rewrite a captured entry. (iOS: `FilterSummaryEntry`.)
 *
 * The enum tokens below are the on-disk contract (iOS raw values); a
 * Kotlin rename must keep them.
 */
@Serializable
data class FilterSummaryEntry(
    val sourceKind: SourceKind,
    val filterSetId: String? = null,
    val filterSetName: String? = null,
    val itemId: String? = null,
    val itemName: String? = null,
    @Serializable(with = LenientFilterItemKindSerializer::class)
    val itemKind: FilterItemKind? = null,
    val originalValue: Double? = null,
    @Serializable(with = LenientFilterValueUnitSerializer::class)
    val originalUnit: FilterValueUnit? = null,
    val canonicalStops: Double? = null,
    @Serializable(with = LenientCalculationModeSerializer::class)
    val calculationMode: CalculationMode? = null,
    val contributedStops: Double,
) {
    @Serializable
    enum class SourceKind {
        @SerialName("standard")
        standard,

        @SerialName("filterSet")
        filterSet,
    }

    @Serializable
    enum class CalculationMode {
        @SerialName("fixed")
        fixed,

        @SerialName("cplLoss")
        cplLoss,

        @SerialName("gndRecordOnly")
        gndRecordOnly,

        @SerialName("gndApplyFullValue")
        gndApplyFullValue,
    }

    companion object {
        /**
         * Captures every wheel of [stack] against [inventory] as it
         * stands right now. Empty wheels are omitted (nothing mounted);
         * Record-only items are kept with a 0-stop contribution.
         */
        fun summary(stack: FilterStack, inventory: FilterInventory): List<FilterSummaryEntry> =
            stack.wheels.zip(stack.rows).mapNotNull { (wheel, row) ->
                when (val selection = wheel.selection) {
                    is FilterWheelSelection.Standard -> FilterSummaryEntry(
                        sourceKind = SourceKind.standard,
                        canonicalStops = selection.stops,
                        contributedStops = selection.stops,
                    )

                    is FilterWheelSelection.Empty -> null

                    is FilterWheelSelection.Item -> {
                        val filterSet = wheel.source.filterSetId?.let { inventory.filterSet(it) }
                        val item = row.item
                        val mode = when (val choice = selection.selection.choice) {
                            is FilterRowChoice.Fixed -> CalculationMode.fixed
                            is FilterRowChoice.CplLoss -> CalculationMode.cplLoss
                            is FilterRowChoice.Gnd -> when (choice.mode) {
                                GndCalculationMode.recordOnly -> CalculationMode.gndRecordOnly
                                GndCalculationMode.applyFullValue -> CalculationMode.gndApplyFullValue
                            }
                        }
                        val registered = item?.behavior?.registeredValue
                        FilterSummaryEntry(
                            sourceKind = SourceKind.filterSet,
                            filterSetId = wheel.source.filterSetId?.rawValue,
                            filterSetName = filterSet?.name,
                            itemId = selection.selection.itemId.rawValue,
                            itemName = item?.name,
                            itemKind = item?.behavior?.kind,
                            originalValue = registered?.value,
                            originalUnit = registered?.unit,
                            canonicalStops = row.registeredStops,
                            calculationMode = mode,
                            contributedStops = row.contributionStops,
                        )
                    }
                }
            }
    }
}

/**
 * Decodes a captured summary entry by entry so one damaged record never
 * erases the whole list: an entry that fails to decode — or carries a
 * non-finite contribution — is skipped and the rest survive. Encoding is
 * the ordinary list encoding. A stored value that is not an array
 * decodes as an empty summary rather than failing its timer.
 * (iOS: `PersistentFilterSummaryEntry.decodeLossyArray`.)
 */
object LossyFilterSummaryListSerializer : KSerializer<List<FilterSummaryEntry>> {
    private val delegate = ListSerializer(FilterSummaryEntry.serializer())

    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun serialize(encoder: Encoder, value: List<FilterSummaryEntry>) =
        delegate.serialize(encoder, value)

    override fun deserialize(decoder: Decoder): List<FilterSummaryEntry> {
        val input = decoder as JsonDecoder
        val elements = input.decodeJsonElement() as? JsonArray ?: return emptyList()
        return elements.mapNotNull { element ->
            runCatching {
                input.json.decodeFromJsonElement(FilterSummaryEntry.serializer(), element)
            }.getOrNull()
        }.filter { it.contributedStops.isFinite() }
    }
}

/**
 * Nullable token serializer for a captured entry's OPTIONAL enum fields:
 * an unknown token degrades that field to `null` instead of discarding
 * the whole entry (iOS parity). Required fields keep the strict enum
 * decoding, so an unknown source kind still drops the entry.
 */
@OptIn(ExperimentalSerializationApi::class)
internal open class LenientTokenSerializer<T : Any>(
    serialName: String,
    private val values: List<T>,
    private val token: (T) -> String,
) : KSerializer<T?> {

    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor(serialName, PrimitiveKind.STRING).nullable

    override fun serialize(encoder: Encoder, value: T?) {
        if (value == null) encoder.encodeNull() else encoder.encodeString(token(value))
    }

    override fun deserialize(decoder: Decoder): T? {
        val element = (decoder as JsonDecoder).decodeJsonElement()
        val raw = (element as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        return values.firstOrNull { token(it) == raw }
    }
}

internal object LenientFilterItemKindSerializer : LenientTokenSerializer<FilterItemKind>(
    "FilterItemKind",
    FilterItemKind.entries,
    { it.name },
)

internal object LenientFilterValueUnitSerializer : LenientTokenSerializer<FilterValueUnit>(
    "FilterValueUnit",
    FilterValueUnit.entries,
    { it.name },
)

internal object LenientCalculationModeSerializer :
    LenientTokenSerializer<FilterSummaryEntry.CalculationMode>(
        "FilterSummaryCalculationMode",
        FilterSummaryEntry.CalculationMode.entries,
        { it.name },
    )
