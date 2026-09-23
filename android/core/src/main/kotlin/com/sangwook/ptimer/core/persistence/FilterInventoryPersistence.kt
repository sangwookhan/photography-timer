// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonObject

/**
 * On-disk schema for the user's filter inventory (Filter Sets and their
 * physical items). Decoded per record through [VersionedCollectionDecoder]:
 * a Filter Set that fails to decode is dropped while the rest survive, and
 * a malformed item inside a set is skipped without losing the set. Stable
 * ids, names, colors, order, kinds, original values/units, and CPL choices
 * round-trip (FILTER-PERSIST-001/002).
 * (iOS: PersistentFilterInventorySnapshot.)
 */
@Serializable
data class PersistentFilterInventorySnapshot(
    val filterSets: List<PersistentFilterSetRecord> = emptyList(),
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
) {
    /**
     * Runtime inventory: records that do not restore (empty id or name)
     * are skipped safely.
     */
    val restoredInventory: FilterInventory
        get() = FilterInventory(filterSets.mapNotNull { it.restoredFilterSet })

    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1

        fun from(inventory: FilterInventory): PersistentFilterInventorySnapshot =
            PersistentFilterInventorySnapshot(
                inventory.filterSets.map { PersistentFilterSetRecord.from(it) },
            )
    }
}

@Serializable
data class PersistentFilterSetRecord(
    val id: String,
    val name: String,
    /** [FilterSetColor] token; an unknown token restores as the default
     *  color rather than dropping the set. */
    val color: String,
    val items: List<PersistentFilterItemRecord> = emptyList(),
) {
    val restoredFilterSet: FilterSet?
        get() {
            val trimmedId = id.trim()
            val trimmedName = name.trim()
            if (trimmedId.isEmpty() || trimmedName.isEmpty()) return null
            val seen = HashSet<FilterItemId>()
            val restoredItems = items.mapNotNull { it.restoredItem }.filter { seen.add(it.id) }
            return FilterSet(
                name = trimmedName,
                color = FilterSetColor.fromToken(color),
                items = restoredItems,
                id = FilterSetId(trimmedId),
            )
        }

    companion object {
        fun from(filterSet: FilterSet): PersistentFilterSetRecord = PersistentFilterSetRecord(
            id = filterSet.id.rawValue,
            name = filterSet.name,
            color = filterSet.color.name,
            items = filterSet.items.map { PersistentFilterItemRecord.from(it) },
        )
    }
}

@Serializable
data class PersistentFilterItemRecord(
    val id: String,
    val name: String,
    /** [FilterItemKind] token. */
    val kind: String,
    /** Original registered value for Fixed / GND items. */
    val value: Double? = null,
    /** [FilterValueUnit] token for Fixed / GND items. */
    val unit: String? = null,
    /** The three CPL fields; `null` entries are empty fields. */
    val cplChoices: List<Double?>? = null,
) {
    /**
     * `null` when the record cannot restore as a well-formed item
     * (unknown kind, missing or invalid value, no valid CPL choice).
     */
    val restoredItem: FilterItem?
        get() {
            val trimmedId = id.trim()
            val trimmedName = name.trim()
            if (trimmedId.isEmpty() || trimmedName.isEmpty()) return null
            val itemKind = FilterItemKind.fromToken(kind) ?: return null
            val behavior = when (itemKind) {
                FilterItemKind.fixed, FilterItemKind.gnd -> {
                    val registeredValue = value ?: return null
                    val valueUnit = FilterValueUnit.fromToken(unit) ?: return null
                    val registered = FilterRegisteredValue(registeredValue, valueUnit)
                    if (itemKind == FilterItemKind.fixed) {
                        FilterItemBehavior.Fixed(registered)
                    } else {
                        FilterItemBehavior.Gnd(registered)
                    }
                }

                FilterItemKind.cpl ->
                    FilterItemBehavior.Cpl(CplExposureLossChoices(cplChoices ?: return null))
            }
            val item = FilterItem(
                name = trimmedName,
                behavior = behavior,
                id = FilterItemId(trimmedId),
            )
            return if (item.isWellFormed) item else null
        }

    companion object {
        fun from(item: FilterItem): PersistentFilterItemRecord = when (val behavior = item.behavior) {
            is FilterItemBehavior.Fixed -> record(item, behavior.value)
            is FilterItemBehavior.Gnd -> record(item, behavior.value)
            is FilterItemBehavior.Cpl -> PersistentFilterItemRecord(
                id = item.id.rawValue,
                name = item.name,
                kind = item.behavior.kind.name,
                cplChoices = behavior.choices.fields,
            )
        }

        private fun record(item: FilterItem, value: FilterRegisteredValue) =
            PersistentFilterItemRecord(
                id = item.id.rawValue,
                name = item.name,
                kind = item.behavior.kind.name,
                value = value.value,
                unit = value.unit.name,
            )
    }
}

/** Persistence boundary for the filter inventory. */
interface FilterInventoryStoring {
    fun loadSnapshot(): PersistentFilterInventorySnapshot?
    fun saveSnapshot(snapshot: PersistentFilterInventorySnapshot)
    fun clearSnapshot()
}

class NoOpFilterInventoryStore : FilterInventoryStoring {
    override fun loadSnapshot(): PersistentFilterInventorySnapshot? = null
    override fun saveSnapshot(snapshot: PersistentFilterInventorySnapshot) {}
    override fun clearSnapshot() {}
}

/**
 * Pure JSON codec for the filter inventory. Encoding is total. Decoding is
 * per-record and version-gated: one undecodable Filter Set is dropped and
 * the rest of the inventory survives, duplicate set ids collapse
 * first-valid-wins, a missing version is accepted as the legacy v1, and a
 * version mismatch or a malformed root rejects the whole payload. A
 * malformed ITEM inside a surviving set is dropped on its own, which is why
 * the set record is decoded field by field here rather than through the
 * generated decoder. [decodeWithDiagnostics] reports the outcome so the
 * store can quarantine; [decode] is the fail-safe wrapper.
 */
object FilterInventoryCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(snapshot: PersistentFilterInventorySnapshot): String = json.encodeToString(snapshot)

    fun decodeWithDiagnostics(text: String): SnapshotDecodeResult<PersistentFilterInventorySnapshot> {
        val result = VersionedCollectionDecoder.decodeRecords(
            json = json,
            text = text,
            recordsKey = "filterSets",
            expectedSchemaVersion = PersistentFilterInventorySnapshot.CURRENT_SCHEMA_VERSION,
            idOf = { it.id },
            decodeRecord = { decodeSetRecord(it) },
        )
        return SnapshotDecodeResult(
            snapshot = PersistentFilterInventorySnapshot(filterSets = result.records),
            outcome = result.outcome,
            droppedRecordCount = result.droppedRecordCount,
        )
    }

    fun decode(text: String): PersistentFilterInventorySnapshot? {
        val result = decodeWithDiagnostics(text)
        return when (result.outcome) {
            PersistenceLoadOutcome.malformed, PersistenceLoadOutcome.versionRejected -> null
            else -> result.snapshot
        }
    }

    /** Lenient item decoding: one malformed item element is skipped, the
     *  set and its remaining items survive. */
    private fun decodeSetRecord(element: JsonElement): PersistentFilterSetRecord {
        val record = element.jsonObject
        val items = record["items"] as? JsonArray ?: JsonArray(emptyList())
        return PersistentFilterSetRecord(
            id = record.requiredString("id"),
            name = record.requiredString("name"),
            color = record.requiredString("color"),
            items = items.mapNotNull { item ->
                runCatching { json.decodeFromJsonElement<PersistentFilterItemRecord>(item) }.getOrNull()
            },
        )
    }

    private fun JsonObject.requiredString(key: String): String {
        val primitive = this[key] as? JsonPrimitive
        if (primitive == null || !primitive.isString) {
            throw SerializationException("Filter set record is missing a string `$key`.")
        }
        return primitive.content
    }
}
