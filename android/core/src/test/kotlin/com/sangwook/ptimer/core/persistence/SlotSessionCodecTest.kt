package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
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
}
