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

/** Confines phone typography to the shooting page; dialogs and wide/fold layouts retain their theme. */
internal val LocalPhoneShooting = staticCompositionLocalOf { false }

internal fun usesPhoneShootingPresentation(width: Dp, height: Dp, smallestWidth: Int, hasFold: Boolean): Boolean =
    !hasFold && smallestWidth < 600 && width >= 360.dp && width < 600.dp && height >= 680.dp

@Composable
internal fun PhoneShootingPresentation(enabled: Boolean, content: @Composable () -> Unit) {
    val base = MaterialTheme.typography
    CompositionLocalProvider(LocalPhoneShooting provides enabled) {
        MaterialTheme(typography = if (enabled) base.copy(
            titleMedium = base.titleMedium.copy(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
            bodyMedium = base.bodyMedium.copy(fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold),
            bodySmall = base.bodySmall.copy(fontSize = 14.sp, lineHeight = 20.sp),
            labelLarge = base.labelLarge.copy(fontSize = 15.sp, lineHeight = 20.sp),
            labelMedium = base.labelMedium.copy(fontSize = 14.sp, lineHeight = 20.sp),
            labelSmall = base.labelSmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
        ) else base, content = content)
    }
}

internal val mainWheelItemHeight: Dp
    @Composable get() = if (LocalPhoneShooting.current) 44.dp else WheelItemHeight

internal val mainResultRowHeight: Dp
    @Composable get() = if (LocalPhoneShooting.current) 56.dp else 48.dp
