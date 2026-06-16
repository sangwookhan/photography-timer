package com.sangwook.ptimer.core

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Smoke test confirming the pure-Kotlin :core module is wired and its
 * JVM test source set runs without an Android dependency.
 */
class CoreModuleSmokeTest {
    @Test
    fun coreModuleIsWired() {
        assertEquals(2, 1 + 1)
    }
}
