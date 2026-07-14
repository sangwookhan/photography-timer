// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.slots.canonicalNDStops
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SlotSessionCodecTest {

    @Test
    fun roundTripsActiveSlotSnapshotsAndNames() {
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera2,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(3, 1, "kodak", "p1", 30.0),
                CameraSlotId.camera2 to SlotCalculatorSnapshot(7, 0, null, null, null),
            ),
            customNames = mapOf(CameraSlotId.camera1 to "Leica"),
        )
        val decoded = SlotSessionCodec.decode(SlotSessionCodec.encode(session))
        assertEquals(session, decoded)
    }

    @Test
    fun malformedPayloadDecodesToNull() {
        assertNull(SlotSessionCodec.decode("{not json"))
    }

    @Test
    fun unknownSchemaVersionDecodesToNull() {
        val json = SlotSessionCodec.encode(
            PersistentSlotSession(CameraSlotId.camera1, schemaVersion = 999),
        )
        assertNull(SlotSessionCodec.decode(json))
    }

    // --- PTIMER-209 ndStops through the real JSON codec ---

    /** A commercial preset survives an actual encode → decode cycle exactly. */
    @Test
    fun commercialPresetNdStopsSurvivesJsonRoundTrip() {
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(
                    shutterIndex = 3, ndIndex = 17, selectedFilmId = null,
                    selectedProfileId = null, ndStops = 16.6,
                ),
            ),
        )
        val decoded = SlotSessionCodec.decode(SlotSessionCodec.encode(session))!!
        val snap = decoded.snapshots.getValue(CameraSlotId.camera1)
        assertEquals(16.6, snap.ndStops!!, 1e-9)
        assertEquals(16.6, snap.canonicalNDStops(), 1e-9)
    }

    /**
     * A pre-PTIMER-209 payload (no `ndStops` key) decodes under schema v1 with
     * `ndStops = null` and restores the legacy whole-stop value — the additive
     * optional field is backward-compatible.
     */
    @Test
    fun legacyPayloadWithoutNdStopsRestoresWholeStop() {
        val json = """
            {"activeSlotId":"camera1","snapshots":{"camera1":{"shutterIndex":3,
            "ndIndex":5,"selectedFilmId":null,"selectedProfileId":null}},
            "customNames":{},"schemaVersion":1}
        """.trimIndent().replace("\n", "")
        val decoded = SlotSessionCodec.decode(json)!!
        val snap = decoded.snapshots.getValue(CameraSlotId.camera1)
        assertNull(snap.ndStops)
        assertEquals(5.0, snap.canonicalNDStops(), 1e-9)
    }

    /**
     * An unsupported off-grid `ndStops` survives the codec but is ignored at the
     * calculator boundary (`canonicalNDStops` falls back to the whole stop), so
     * the fixed product set stays a domain invariant end-to-end.
     */
    @Test
    fun unsupportedNdStopsIsIgnoredAfterDecode() {
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(
                    shutterIndex = 0, ndIndex = 5, selectedFilmId = null,
                    selectedProfileId = null, ndStops = 12.4,
                ),
            ),
        )
        val decoded = SlotSessionCodec.decode(SlotSessionCodec.encode(session))!!
        val snap = decoded.snapshots.getValue(CameraSlotId.camera1)
        assertEquals(12.4, snap.ndStops!!, 1e-9)
        assertEquals(5.0, snap.canonicalNDStops(), 1e-9)
    }
}
