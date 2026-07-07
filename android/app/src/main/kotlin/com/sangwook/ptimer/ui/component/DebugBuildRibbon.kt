// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Small corner marker shown only in debug builds (PTIMER-210) so a debug
 * install is visually distinguishable from release on screen, not just by
 * launcher label.
 */
@Composable
fun DebugBuildRibbon(modifier: Modifier = Modifier) {
    Text(
        text = "DEBUG",
        color = Color.White,
        style = MaterialTheme.typography.labelSmall,
        modifier = modifier
            .background(Color.Red)
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}
