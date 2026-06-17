package com.sangwook.ptimer.slots

import com.sangwook.ptimer.calculator.SlotCalculatorSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Round-trip + fail-safe tests for the camera-slot session codec. */
class SlotSessionCodecTest {

    @Test
    fun roundTripsActiveSlotSnapshotsAndNames() {
        val session = CameraSlotSession()
        session.store("camera1", SlotCalculatorSnapshot(1.0, 5, "ilford-pan-f-plus-50", null))
        session.setCustomName("camera1", "Hasselblad")
        session.activate("camera2")
        session.store("camera2", SlotCalculatorSnapshot(0.5, 3, null, null))

        val restoredData = SlotSessionCodec.decode(SlotSessionCodec.encode(session))!!
        val restored = CameraSlotSession()
        restored.restore(restoredData.activeSlotId, restoredData.snapshots, restoredData.names)

        assertEquals("camera2", restored.activeSlotId)
        assertEquals("Hasselblad", restored.label("camera1"))
        assertEquals(SlotCalculatorSnapshot(1.0, 5, "ilford-pan-f-plus-50", null), restored.snapshot("camera1"))
        assertEquals(SlotCalculatorSnapshot(0.5, 3, null, null), restored.snapshot("camera2"))
    }

    @Test
    fun corruptPayloadDecodesToNull() {
        assertNull(SlotSessionCodec.decode("{ not json"))
    }

    @Test
    fun unknownSchemaVersionDecodesToNull() {
        assertNull(SlotSessionCodec.decode("""{"schemaVersion":999,"activeSlotId":"camera1","slots":[]}"""))
    }
}
