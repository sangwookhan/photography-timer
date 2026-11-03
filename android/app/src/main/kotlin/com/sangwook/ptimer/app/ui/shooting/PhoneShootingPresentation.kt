// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal val LocalPhoneShooting = staticCompositionLocalOf { false }
private val LocalPhoneWheelRow = staticCompositionLocalOf { 36.dp }
private val LocalPhoneResultRow = staticCompositionLocalOf { 52.dp }

internal fun usesPhoneShootingPresentation(width: Dp, height: Dp, smallestWidth: Int, hasFold: Boolean): Boolean =
    !hasFold && smallestWidth < 600 && width >= 360.dp && width < 600.dp && height > 0.dp

@Composable
internal fun PhoneShootingPresentation(enabled: Boolean, extra: Dp = 0.dp, content: @Composable () -> Unit) {
    val base = MaterialTheme.typography
    val boundedExtra = extra.coerceIn((-6).dp, 18.dp)
    val wheelRow = 36.dp + boundedExtra
    val resultRow = 52.dp + boundedExtra.coerceAtLeast(0.dp) / 2
    CompositionLocalProvider(
        LocalPhoneShooting provides enabled,
        LocalPhoneWheelRow provides wheelRow,
        LocalPhoneResultRow provides resultRow,
    ) {
        MaterialTheme(typography = if (enabled) base.copy(
            titleMedium = base.titleMedium.copy(fontSize = 22.sp, lineHeight = 28.sp, letterSpacing = 0.sp, fontWeight = FontWeight.SemiBold),
            bodyMedium = base.bodyMedium.copy(fontSize = 22.sp, lineHeight = 28.sp, letterSpacing = 0.sp, fontWeight = FontWeight.SemiBold),
            bodyLarge = base.bodyLarge.copy(fontSize = 18.sp, lineHeight = 24.sp),
            bodySmall = base.bodySmall.copy(fontSize = 18.sp, lineHeight = 24.sp),
            labelLarge = base.labelLarge.copy(fontSize = 15.sp, lineHeight = 20.sp),
            labelMedium = base.labelMedium.copy(fontSize = 14.sp, lineHeight = 20.sp),
            labelSmall = base.labelSmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
        ) else base, content = content)
    }
}

internal val mainWheelItemHeight: Dp
    @Composable get() = if (LocalPhoneShooting.current) LocalPhoneWheelRow.current else WheelItemHeight

internal val mainResultRowHeight: Dp
    @Composable get() = if (LocalPhoneShooting.current) LocalPhoneResultRow.current else 48.dp
