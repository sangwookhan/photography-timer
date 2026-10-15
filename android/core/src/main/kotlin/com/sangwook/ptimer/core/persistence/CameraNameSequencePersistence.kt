// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// The automatic `Camera N` sequence lives in its own versioned store,
// independent of the managed camera list. It is never reconstructed from
// cameras, names, order, count, identities, or timer records
// (CAMERA-NAME-004, PERSIST-CAMERA-SEQUENCE-001). (iOS:
// PersistentCameraNameSequenceSnapshot.)

/** On-disk shape of the sequence: the number the next automatic name will use. */
@Serializable
data class PersistentCameraNameSequence(
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val nextNumber: Int,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1
    }
}

/** Outcome of reading the sequence store. */
sealed interface CameraNameSequenceLoadResult {
    /** No sequence has been stored. */
    data object Absent : CameraNameSequenceLoadResult

    /** The next automatic number. */
    data class Value(val nextNumber: Int) : CameraNameSequenceLoadResult

    /**
     * A value was read successfully but cannot be used (undecodable,
     * unsupported version, or out of range). The allocator treats it like a
     * missing sequence (CAMERA-PERSIST-007).
     */
    data object Unusable : CameraNameSequenceLoadResult

    /**
     * The read itself failed and supplied no content. Nothing is written, so
     * a healthy stored value cannot be overwritten by a guess.
     */
    data object ReadFailed : CameraNameSequenceLoadResult
}

/**
 * The allocatable range of the stored next number: 5 (the first automatic
 * number after the four default cameras) through `Int.MAX_VALUE - 1` (so the
 * following value can still be stored). Anything else is unusable and follows
 * the normal fallback: reserve 5, durably store 6, then commit `Camera 5`.
 */
object CameraNameSequenceRange {
    const val MIN: Int = 5
    const val MAX: Int = Int.MAX_VALUE - 1

    fun isUsable(nextNumber: Int): Boolean = nextNumber in MIN..MAX
}

/** Persistence boundary for the automatic-name sequence. */
interface CameraNameSequenceStoring {
    fun load(): CameraNameSequenceLoadResult

    /** Durably stores the next automatic number. Returns whether the write succeeded. */
    fun save(nextNumber: Int): Boolean
}

/**
 * In-memory sequence store: the default when no persistent store is
 * injected, and the test double (it can simulate corruption and write
 * failures).
 */
class InMemoryCameraNameSequenceStore(
    var result: CameraNameSequenceLoadResult = CameraNameSequenceLoadResult.Absent,
) : CameraNameSequenceStoring {
    var failsWrites = false
    var saveCount = 0
        private set

    override fun load(): CameraNameSequenceLoadResult = result

    override fun save(nextNumber: Int): Boolean {
        if (failsWrites) return false
        saveCount++
        result = CameraNameSequenceLoadResult.Value(nextNumber)
        return true
    }
}

/** Pure JSON codec for the sequence payload. */
object CameraNameSequenceCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(nextNumber: Int): String =
        json.encodeToString(PersistentCameraNameSequence(nextNumber = nextNumber))

    /**
     * [CameraNameSequenceLoadResult.Value] for a next number in
     * [CameraNameSequenceRange], or `Unusable` for anything not usable
     * (negative, 0 to 4, `Int.MAX_VALUE`, malformed, unsupported version).
     */
    fun decode(text: String): CameraNameSequenceLoadResult = try {
        val payload = json.decodeFromString<PersistentCameraNameSequence>(text)
        if (payload.schemaVersion == PersistentCameraNameSequence.CURRENT_SCHEMA_VERSION && CameraNameSequenceRange.isUsable(payload.nextNumber)) {
            CameraNameSequenceLoadResult.Value(payload.nextNumber)
        } else {
            CameraNameSequenceLoadResult.Unusable
        }
    } catch (_: Exception) {
        CameraNameSequenceLoadResult.Unusable
    }
}
