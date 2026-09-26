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
import kotlinx.serialization.Transient
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
     *
     * Skipping is safe for the session and NOT safe for the payload — the
     * skipped record is the user's own Filter Set. [FilterInventoryCodec]
     * counts these so the store can quarantine the original bytes before
     * the reduced inventory is written back over them.
     */
    val restoredInventory: FilterInventory
        get() = FilterInventory(filterSets.mapNotNull { it.restoredFilterSet })

    /** Records that parse but cannot be restored. @see restoredInventory */
    val unrestorableRecordCount: Int get() = filterSets.count { it.restoredFilterSet == null }

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
    /**
     * Item elements the codec could not parse at all, so they never
     * became an entry in [items]. Set by [FilterInventoryCodec]; never
     * encoded, and zero on a record built from a runtime Filter Set.
     */
    @Transient
    val undecodableItemCount: Int = 0,
) {
    val restoredFilterSet: FilterSet?
        get() {
            val trimmedId = id.trim()
            val trimmedName = name.trim()
            if (trimmedId.isEmpty() || trimmedName.isEmpty()) return null
            return FilterSet(
                name = trimmedName,
                color = FilterSetColor.fromToken(color),
                items = restoration.items,
                id = FilterSetId(trimmedId),
            )
        }

    /**
     * Items of this record that do not survive restoration: an unknown
     * kind, a missing or invalid value, no valid CPL choice, or a
     * duplicate id. [undecodableItemCount] is on top of this — those were
     * lost one step earlier, before they could become records.
     */
    val lostItemCount: Int get() = undecodableItemCount + restoration.droppedItemCount

    /**
     * The items that restore, and how many were lost getting there, from
     * one walk — so the set that is handed to the app and the count that
     * is handed to the store can never disagree about what went missing.
     */
    private val restoration: RestoredItems
        get() {
            val seen = HashSet<FilterItemId>()
            val restored = ArrayList<FilterItem>()
            var dropped = 0
            for (record in items) {
                val item = record.restoredItem
                if (item == null || !seen.add(item.id)) dropped++ else restored.add(item)
            }
            return RestoredItems(restored, dropped)
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

/** @see PersistentFilterSetRecord.restoration */
private data class RestoredItems(val items: List<FilterItem>, val droppedItemCount: Int)

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
 * generated decoder.
 *
 * Every one of those losses degrades the outcome, including the ones that
 * only appear when the records are restored into runtime values. The store
 * quarantines on the outcome, so a loss that does not reach
 * [decodeWithDiagnostics] is a loss with no copy kept anywhere.
 * [decode] is the fail-safe wrapper.
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
        val snapshot = PersistentFilterInventorySnapshot(filterSets = result.records)
        // What the collection decoder cannot see. It counts the Filter
        // Sets IT refused; it knows nothing about a set that parses and
        // then cannot be restored, nor about items lost inside a set that
        // survives. Both silently shrink the user's own inventory, and
        // the store quarantines on this outcome alone — so if these do
        // not reach it, the reduced inventory is written back over the
        // original bytes on the next edit and the filter is gone.
        val lostOnRestore = snapshot.unrestorableRecordCount + result.records.sumOf { it.lostItemCount }
        return SnapshotDecodeResult(
            snapshot = snapshot,
            outcome = when {
                result.outcome != PersistenceLoadOutcome.loaded -> result.outcome
                lostOnRestore > 0 -> PersistenceLoadOutcome.degraded
                else -> PersistenceLoadOutcome.loaded
            },
            droppedRecordCount = result.droppedRecordCount,
            droppedOnRestoreCount = lostOnRestore,
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
        // An ABSENT `items` is the legacy default: a set with no filters
        // registered. A present one that is not an array is corruption of
        // the set's own structure, and it hid a whole set's worth of
        // filters — `as? JsonArray ?: empty` read `"items": {}` exactly
        // like an empty list, so nothing was dropped, nothing degraded,
        // and nothing was quarantined. Rejecting the record is how this
        // codec already answers a set whose own fields are damaged: the
        // collection decoder counts it, the outcome degrades, and the raw
        // payload is kept.
        val declared = record["items"]
        if (declared != null && declared !is JsonArray) {
            throw SerializationException("Filter set record has a non-array `items`.")
        }
        val elements = declared as? JsonArray ?: JsonArray(emptyList())
        val items = elements.mapNotNull { item ->
            runCatching { json.decodeFromJsonElement<PersistentFilterItemRecord>(item) }.getOrNull()
        }
        return PersistentFilterSetRecord(
            id = record.requiredString("id"),
            name = record.requiredString("name"),
            color = record.requiredString("color"),
            items = items,
            // Carried on the record so it reaches the diagnostics: these
            // elements never became items, so nothing downstream can
            // notice they were there.
            undecodableItemCount = elements.size - items.size,
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
