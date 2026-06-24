package com.sangwook.ptimer.core.exposure

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import kotlin.math.abs

/**
 * Drives the cross-platform golden fixture `shared/test-fixtures/exposure-golden.json`
 * against the Kotlin port, proving exposure parity with iOS PTimerCore.
 */
class ExposureGoldenTest {

    private val calc = ExposureCalculator()
    private val fixture: JsonObject = loadFixture()

    @Test
    fun fullStopLadderMatchesFixture() {
        val fixtureLadder = fixture["fullStopShutterSpeeds"]!!.jsonArray.map { it.jsonPrimitive.double }
        assertEquals(
            "ladder length",
            fixtureLadder.size,
            ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS.size,
        )
        fixtureLadder.forEachIndexed { i, expected ->
            val actual = ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS[i]
            assertTrue("ladder[$i] expected≈$expected got $actual", abs(actual - expected) <= 1e-4)
        }
    }

    @Test
    fun calculationCasesMatch() {
        for (case in fixture["cases"]!!.jsonArray.map { it.jsonObject }) {
            val desc = case["description"]!!.jsonPrimitive.content
            val base = case["baseShutterSeconds"]!!.jsonPrimitive.double
            val ndStops = case["ndStops"]!!.jsonPrimitive.int
            val expectedSeconds = case["expectedCalculatedSeconds"]!!.jsonPrimitive.double
            val expectedFormatted = case["expectedFormattedResult"]!!.jsonPrimitive.content
            val tolerance = case["tolerance"]!!.jsonPrimitive.double

            val actual = calc.calculate(base, ndStops)
            assertTrue(
                "[$desc] calc expected $expectedSeconds got $actual (tol $tolerance)",
                abs(actual - expectedSeconds) <= tolerance,
            )
            assertEquals("[$desc] formatted", expectedFormatted, calc.formatShutter(actual))
        }
    }

    @Test
    fun timeDisplayCasesMatch() {
        for (case in fixture["timeDisplayCases"]!!.jsonArray.map { it.jsonObject }) {
            val desc = case["description"]!!.jsonPrimitive.content
            val input = case["inputSeconds"]!!.jsonPrimitive.double
            val expectedPrimary = case["expectedPrimary"]!!.jsonPrimitive.content
            val expectedSecondary = case["expectedSecondary"]!!.jsonPrimitive.content

            val display = calc.formatTimeDisplay(input)
            assertEquals("[$desc] primary", expectedPrimary, display.primary)
            assertEquals("[$desc] secondary", expectedSecondary, display.secondary)
        }
    }

    @Test
    fun shutterFormatCasesMatch() {
        for (case in fixture["shutterFormatCases"]!!.jsonArray.map { it.jsonObject }) {
            val input = case["inputSeconds"]!!.jsonPrimitive.double
            val expected = case["expectedFormatted"]!!.jsonPrimitive.content
            assertEquals("formatShutter($input)", expected, calc.formatShutter(input))
        }
    }

    @Test
    fun errorCasesMatch() {
        for (case in fixture["errorCases"]!!.jsonArray.map { it.jsonObject }) {
            val desc = case["description"]!!.jsonPrimitive.content
            val expectedError = case["expectedError"]!!.jsonPrimitive.content

            val actualKey = try {
                if (case.containsKey("baseShutterInput")) {
                    calc.parseBaseShutter(case["baseShutterInput"]!!.jsonPrimitive.content)
                } else {
                    val base = case["baseShutterSeconds"]!!.jsonPrimitive.double
                    val ndStops = case["ndStops"]!!.jsonPrimitive.int
                    calc.calculate(base, ndStops)
                }
                fail("[$desc] expected $expectedError but no error was thrown")
                "" // unreachable
            } catch (e: ExposureCalculatorException) {
                e.error.key
            }
            assertEquals("[$desc]", expectedError, actualKey)
        }
    }

    private fun loadFixture(): JsonObject {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "shared/test-fixtures/exposure-golden.json")
            if (candidate.exists()) {
                return Json.parseToJsonElement(candidate.readText()).jsonObject
            }
            dir = dir.parentFile
        }
        throw IllegalStateException(
            "exposure-golden.json not found walking up from ${System.getProperty("user.dir")}",
        )
    }
}
