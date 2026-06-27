// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class CoreSmokeTest {

    @Test
    fun moduleNameIsStable() {
        assertEquals("PTimerCore", CoreModule.NAME)
    }

    @Test
    fun serializationPluginRoundTrips() {
        val info = CoreModuleInfo(CoreModule.NAME, schemaVersion = 1)
        val json = Json.encodeToString(info)
        val decoded = Json.decodeFromString<CoreModuleInfo>(json)
        assertEquals(info, decoded)
    }
}
