package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.testsupport.SharedFixtureLocator
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Drives the cross-platform exposure golden fixture
 * (`shared/test-fixtures/exposure-golden.json`) through the Kotlin
 * ExposureCalculator. iOS behavior is the source of truth; the fixture
 * is the shared oracle. Read-only — the fixture is not modified.
 */
class ExposureGoldenTest {

    private val calculator = ExposureCalculator()
    private val root = Json.parseToJsonElement(
        SharedFixtureLocator.readText("exposure-golden.json")
    ).jsonObject

    @Test
    fun fullStopShutterSpeedsMatchFixture() {
        val fixtureLadder = root["fullStopShutterSpeeds"]!!.jsonArray.map { it.jsonPrimitive.double }
        assertEquals(fixtureLadder.size, ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS.size)
        fixtureLadder.forEachIndexed { i, expected ->
            assertEquals("ladder[$i]", expected, ExposureCalculator.FULL_STOP_SHUTTER_SPEEDS[i], 0.0001)
        }
    }

    @Test
    fun calculationCasesMatchFixture() {
        for (case in root["cases"]!!.jsonArray) {
            val obj = case.jsonObject
            val desc = obj["description"]!!.jsonPrimitive.content
            val base = obj["baseShutterSeconds"]!!.jsonPrimitive.double
            val ndStops = obj["ndStops"]!!.jsonPrimitive.int
            val expectedCalc = obj["expectedCalculatedSeconds"]!!.jsonPrimitive.double
            val expectedFmt = obj["expectedFormattedResult"]!!.jsonPrimitive.content
            val tolerance = obj["tolerance"]!!.jsonPrimitive.double

            val calc = calculator.calculate(base, ndStops)
            assertEquals("calc: $desc", expectedCalc, calc, tolerance)
            assertEquals("format: $desc", expectedFmt, calculator.formatShutter(calc))
        }
    }

    @Test
    fun timeDisplayCasesMatchFixture() {
        for (case in root["timeDisplayCases"]!!.jsonArray) {
            val obj = case.jsonObject
            val desc = obj["description"]!!.jsonPrimitive.content
            val input = obj["inputSeconds"]!!.jsonPrimitive.double
            val expectedPrimary = obj["expectedPrimary"]!!.jsonPrimitive.content
            val expectedSecondary = obj["expectedSecondary"]!!.jsonPrimitive.content

            val display = calculator.formatTimeDisplay(input)
            assertEquals("primary: $desc", expectedPrimary, display.primary)
            assertEquals("secondary: $desc", expectedSecondary, display.secondary)
        }
    }

    @Test
    fun shutterFormatCasesMatchFixture() {
        for (case in root["shutterFormatCases"]!!.jsonArray) {
            val obj = case.jsonObject
            val input = obj["inputSeconds"]!!.jsonPrimitive.double
            val expected = obj["expectedFormatted"]!!.jsonPrimitive.content
            assertEquals(expected, calculator.formatShutter(input))
        }
    }

    @Test
    fun errorCasesMatchFixture() {
        for (case in root["errorCases"]!!.jsonArray) {
            val obj = case.jsonObject
            val desc = obj["description"]!!.jsonPrimitive.content
            val expectedToken = obj["expectedError"]!!.jsonPrimitive.content

            val thrown: ExposureCalcError? = try {
                if (obj.containsKey("baseShutterInput")) {
                    calculator.parseBaseShutter(obj["baseShutterInput"]!!.jsonPrimitive.content)
                } else {
                    val base = obj["baseShutterSeconds"]!!.jsonPrimitive.double
                    val ndStops = obj["ndStops"]!!.jsonPrimitive.int
                    calculator.calculate(base, ndStops)
                }
                null
            } catch (e: ExposureCalcException) {
                e.error
            }

            if (thrown == null) fail("Expected error for: $desc")
            assertEquals("error token: $desc", expectedToken, thrown!!.token)
        }
    }
}
