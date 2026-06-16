package com.sangwook.ptimer.core.testsupport

import java.io.File

/**
 * Locates cross-platform golden fixtures under `shared/test-fixtures/`
 * at the repository root by walking up from the test working directory.
 * Mirrors the intent of the iOS `SharedFixtureLocator`.
 */
object SharedFixtureLocator {
    fun fixture(name: String): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "shared/test-fixtures/$name")
            if (candidate.isFile) return candidate
            dir = dir.parentFile
        }
        error("Could not locate shared/test-fixtures/$name from ${System.getProperty("user.dir")}")
    }

    fun readText(name: String): String = fixture(name).readText()
}
