// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
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
