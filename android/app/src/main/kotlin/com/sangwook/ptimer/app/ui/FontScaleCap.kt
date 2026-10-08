// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density

/**
 * Caps the system font-scale setting applied below this point (PTIMER-219):
 * standard OS "Font size" settings top out around here, and dense per-camera
 * layout (wheels, segmented toggles) can't reflow to accommodate the much
 * larger range the newer Accessibility > Font size slider allows without a
 * dedicated redesign. Text still scales up to this cap; only the extreme end
 * is clamped.
 */
internal const val MaxCappedFontScale = 1.3f

/**
 * Regions whose layout must not change with the system font scale hold their
 * text at 1x (SHELL-023). Measured on device: any enlargement moves the
 * Timers sheet and Details components (26 px and 9 px at 1.05), and from 1.3
 * the Timers action row wraps.
 */
internal const val MaxMiniTimerFontScale = 1f
internal const val MaxTimersFontScale = 1f
internal const val MaxDetailsFontScale = 1f

/**
 * Wraps [content] with a [LocalDensity] whose fontScale is clamped to
 * [maxFontScale] (defaults to [MaxCappedFontScale]). Must be applied INSIDE
 * each `Dialog`/`AlertDialog`/`ModalBottomSheet` composable's own content, not
 * just once at an ancestor: Compose's `Dialog` hosts content in a new
 * `AndroidComposeView` that re-derives `LocalDensity` from the system
 * Configuration at its own composition root, which shadows (and ignores) any
 * `CompositionLocalProvider` set up by a calling composition outside that
 * dialog.
 */
@Composable
internal fun CappedFontScale(maxFontScale: Float = MaxCappedFontScale, content: @Composable () -> Unit) {
    val base = LocalDensity.current
    val capped = Density(density = base.density, fontScale = base.fontScale.coerceAtMost(maxFontScale))
    CompositionLocalProvider(LocalDensity provides capped, content = content)
}

/**
 * The one size shared by the five Main left-hand labels (Target Shutter, Base
 * Shutter, Adjusted Shutter, Reciprocity, Corrected Exposure), in sp at a 1x
 * density: 14 x the system font scale, held between 13 and 14.5. Main pins its
 * density at 1x, so this number is the rendered size; the system scale
 * [systemFontScale] is applied here, once, and nowhere else.
 */
internal fun mainLabelSizeSp(systemFontScale: Float): Float =
    (MainLabelBaseSp * systemFontScale).coerceIn(MainLabelMinSp, MainLabelMaxSp)

/** Main labels that still follow the system scale (the seconds values) grow up to this inside their fixed slot. */
internal const val MaxMainLabelFontScale = 1.2f

private const val MainLabelBaseSp = 14f
private const val MainLabelMinSp = 13f
private const val MainLabelMaxSp = 14.5f

/**
 * Applies the SYSTEM font scale (up to [maxFontScale]) to [content] even when an
 * ancestor pinned the density to 1x. Pair it with a fixed-size slot so the
 * growing text cannot change the size of its parent or siblings.
 */
@Composable
internal fun ScaledLabelFontScale(maxFontScale: Float = MaxMainLabelFontScale, content: @Composable () -> Unit) {
    val base = LocalDensity.current
    val system = LocalConfiguration.current.fontScale
    val scaled = Density(density = base.density, fontScale = system.coerceAtMost(maxFontScale).coerceAtLeast(base.fontScale))
    CompositionLocalProvider(LocalDensity provides scaled, content = content)
}
