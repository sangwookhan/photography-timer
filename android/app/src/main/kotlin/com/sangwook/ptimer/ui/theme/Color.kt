// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.sangwook.ptimer.core.exposure.FilterSetColor

val Purple80 = Color(0xFFD0BCFF)
val PurpleGrey80 = Color(0xFFCCC2DC)
val Pink80 = Color(0xFFEFB8C8)

val Purple40 = Color(0xFF6650A4)
val PurpleGrey40 = Color(0xFF625B71)
val Pink40 = Color(0xFF7D5260)

// Semantic status colors. Material's color scheme has no success/warning
// roles, so these are defined once here and reused for the reciprocity
// status tones, the target-shutter attention cue, and the graph bands —
// rather than repeating raw hex literals across composables.
val StatusSuccess = Color(0xFF66BB6A)
val StatusWarning = Color(0xFFFFB74D)
val StatusDanger = Color(0xFFEF5350)

/**
 * The fixed filter-type palette behind each wheel row's rail
 * (FILTER-STACK-007): ND blue, CPL amber/orange, GND a green-leaning
 * teal that stays visibly apart from ND blue even on faded rows, and
 * Empty neutral gray. App-defined and stable across Filter Sets and
 * cameras — never derived from a user-selected Filter Set color.
 */
data class FilterTypePalette(
    val nd: Color,
    val cpl: Color,
    val gnd: Color,
    val empty: Color,
)

private val FilterTypePaletteLight = FilterTypePalette(
    nd = Color(0xFF1565C0),
    cpl = Color(0xFFE07C00),
    gnd = Color(0xFF00796B),
    empty = Color(0xFF8A8A8E),
)

private val FilterTypePaletteDark = FilterTypePalette(
    nd = Color(0xFF64B5F6),
    cpl = Color(0xFFFFB74D),
    gnd = Color(0xFF4DD0B1),
    empty = Color(0xFF9E9E9E),
)

@Composable
fun filterTypePalette(): FilterTypePalette =
    if (isSystemInDarkTheme()) FilterTypePaletteDark else FilterTypePaletteLight

// User-selected Filter Set source colors (FILTER-SET-005). One mapping
// from the platform-neutral token to a Compose color, so the Android
// source cue reads the same token iOS renders with system colors.
private val FilterSetColorsLight = mapOf(
    FilterSetColor.red to Color(0xFFD32F2F),
    FilterSetColor.orange to Color(0xFFEF6C00),
    FilterSetColor.yellow to Color(0xFFC79100),
    FilterSetColor.green to Color(0xFF2E7D32),
    FilterSetColor.mint to Color(0xFF00A78E),
    FilterSetColor.teal to Color(0xFF00796B),
    FilterSetColor.cyan to Color(0xFF0097A7),
    FilterSetColor.blue to Color(0xFF1565C0),
    FilterSetColor.indigo to Color(0xFF3949AB),
    FilterSetColor.purple to Color(0xFF7B1FA2),
    FilterSetColor.pink to Color(0xFFC2185B),
    FilterSetColor.brown to Color(0xFF6D4C41),
)

private val FilterSetColorsDark = mapOf(
    FilterSetColor.red to Color(0xFFEF5350),
    FilterSetColor.orange to Color(0xFFFFA726),
    FilterSetColor.yellow to Color(0xFFFFD54F),
    FilterSetColor.green to Color(0xFF66BB6A),
    FilterSetColor.mint to Color(0xFF4DD0A5),
    FilterSetColor.teal to Color(0xFF4DB6AC),
    FilterSetColor.cyan to Color(0xFF4DD0E1),
    FilterSetColor.blue to Color(0xFF64B5F6),
    FilterSetColor.indigo to Color(0xFF7986CB),
    FilterSetColor.purple to Color(0xFFBA68C8),
    FilterSetColor.pink to Color(0xFFF06292),
    FilterSetColor.brown to Color(0xFFA1887F),
)

/** Compose color for a Filter Set's user-selected source-color token. */
@Composable
fun filterSetColor(token: FilterSetColor): Color {
    val palette = if (isSystemInDarkTheme()) FilterSetColorsDark else FilterSetColorsLight
    return palette.getValue(token)
}
