// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * PTIMER-199: consumes `shared/test-fixtures/nd-stack-golden.json` so
 * stack summation, the post-commit sort order, and the resulting
 * calculation stay in lockstep with iOS. The calculation runs on the
 * shipping one-third-stop scale, which never snaps the output.
 */
class NdStackGoldenTest {
    @Test
    fun goldenFixtureCasesMatchDomainAndCalculator() {
        val fixture = loadFixture()
        val calculator = ExposureCalculator()

        fixture["cases"]!!.jsonArray.forEach { element ->
            val case = element.jsonObject
            val description = case["description"]!!.jsonPrimitive.content
            val wheelStops = case["wheelStops"]!!.jsonArray.map { it.jsonPrimitive.double }
            val stack = NdFilterStack(wheelStops)
            val tolerance = case["tolerance"]!!.jsonPrimitive.double

            assertEquals(
                "[$description] effective sum",
                case["expectedEffectiveStops"]!!.jsonPrimitive.double,
                stack.effectiveStops,
                1e-9,
            )
            assertEquals(
                "[$description] sorted order",
                case["expectedSortedStops"]!!.jsonArray.map { it.jsonPrimitive.double },
                stack.sortedForCommit().entries,
            )
            assertEquals(
                "[$description] calculated seconds",
                case["expectedCalculatedSeconds"]!!.jsonPrimitive.double,
                calculator.calculate(
                    case["baseShutterSeconds"]!!.jsonPrimitive.double,
                    NDStep(stack.effectiveStops),
                    ExposureScaleMode.ONE_THIRD_STOP,
                ),
                tolerance,
            )
        }
    }

    private fun loadFixture(): JsonObject {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "shared/test-fixtures/nd-stack-golden.json")
            if (candidate.exists()) {
                return Json.parseToJsonElement(candidate.readText()).jsonObject
            }
            dir = dir.parentFile
        }
        throw IllegalStateException(
            "nd-stack-golden.json not found walking up from ${System.getProperty("user.dir")}",
        )
    }
}
