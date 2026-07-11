// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

/**
 * Outcome of decoding a versioned, record-collection persistence payload.
 * Distinguishes the states a bare `null` used to collapse together so the
 * store can decide whether to quarantine the raw payload (PTIMER-215). Mirror
 * of the iOS `PersistenceLoadOutcome`.
 */
enum class PersistenceLoadOutcome {
    /** Root parsed, version accepted, every record decoded. */
    loaded,

    /** Root + version accepted, but one or more records were dropped (an
     *  undecodable record — unknown enum / rule kind — or a duplicate id). */
    degraded,

    /** A schemaVersion was present and did not equal the expected version. */
    versionRejected,

    /** The payload is not a JSON object, or its records field is not an array. */
    malformed,
    ;

    val indicatesFailure: Boolean get() = this != loaded
}

/** Records decoded from a collection payload, with quarantine diagnostics. */
data class PerRecordDecodeResult<T>(
    val records: List<T>,
    val droppedRecordCount: Int,
    val outcome: PersistenceLoadOutcome,
)

/** A decoded snapshot paired with the diagnostics a store needs to quarantine
 *  and signal. `snapshot` is always usable — degraded or empty on failure. */
data class SnapshotDecodeResult<T>(
    val snapshot: T,
    val outcome: PersistenceLoadOutcome,
    val droppedRecordCount: Int,
) {
    val indicatesFailure: Boolean get() = outcome.indicatesFailure
}

/**
 * Per-record decoder for versioned collection payloads (PTIMER-215). Mirrors
 * the isolation the workspace codec already had and the iOS
 * VersionedCollectionDecoder: a payload written by a newer schema degrades
 * only the affected record. A missing version is accepted as the legacy
 * expected version; a mismatched version rejects the whole payload; duplicate
 * ids collapse first-valid-wins.
 */
object VersionedCollectionDecoder {
    fun <T> decodeRecords(
        json: Json,
        text: String,
        recordsKey: String,
        expectedSchemaVersion: Int,
        versionKey: String = "schemaVersion",
        idOf: (T) -> Any,
        decodeRecord: (JsonElement) -> T,
    ): PerRecordDecodeResult<T> {
        val root = try {
            json.parseToJsonElement(text).jsonObject
        } catch (_: Exception) {
            return PerRecordDecodeResult(emptyList(), 0, PersistenceLoadOutcome.malformed)
        }

        val versionElement = root[versionKey]
        if (versionElement != null) {
            val version = (versionElement as? JsonPrimitive)?.intOrNull
            if (version != expectedSchemaVersion) {
                return PerRecordDecodeResult(emptyList(), 0, PersistenceLoadOutcome.versionRejected)
            }
        }

        val rawRecords = root[recordsKey]
            ?: return PerRecordDecodeResult(emptyList(), 0, PersistenceLoadOutcome.loaded)
        val elements = rawRecords as? JsonArray
            ?: return PerRecordDecodeResult(emptyList(), 0, PersistenceLoadOutcome.malformed)

        val seen = HashSet<Any>()
        val records = ArrayList<T>()
        var dropped = 0
        for (element in elements) {
            val record = runCatching { decodeRecord(element) }.getOrNull()
            if (record == null) {
                dropped++
                continue
            }
            if (seen.add(idOf(record))) {
                records.add(record)
            } else {
                // Duplicate id — first valid wins.
                dropped++
            }
        }

        return PerRecordDecodeResult(
            records = records,
            droppedRecordCount = dropped,
            outcome = if (dropped > 0) PersistenceLoadOutcome.degraded else PersistenceLoadOutcome.loaded,
        )
    }
}
