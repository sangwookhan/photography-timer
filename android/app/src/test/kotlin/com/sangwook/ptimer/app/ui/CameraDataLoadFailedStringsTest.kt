// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import java.io.File

/**
 * The failed-read explanation (CAMERA-PERSIST-004/006): the exact English text
 * the spec requires, and a Korean string that exists and is not left in English.
 */
class CameraDataLoadFailedStringsTest {
    private fun value(dir: String): String {
        val file = File("src/main/res/$dir/strings.xml")
        val match = Regex("""<string name="camera_data_load_failed">(.*?)</string>""").find(file.readText())
        return requireNotNull(match) { "camera_data_load_failed missing in $dir" }.groupValues[1].replace("\\'", "'")
    }

    @Test
    fun englishIsTheExactSpecifiedText() {
        assertEquals("Camera data couldn't be loaded. Restart the app.", value("values"))
    }

    @Test
    fun koreanExistsAndIsLocalized() {
        val korean = value("values-ko")
        assertNotEquals(value("values"), korean)
        assert(korean.any { it in '\uAC00'..'\uD7A3' })
    }
}
