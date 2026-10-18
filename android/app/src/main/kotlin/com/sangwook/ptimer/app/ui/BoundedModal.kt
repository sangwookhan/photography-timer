// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.ui.shooting.FoldSide
import com.sangwook.ptimer.app.ui.shooting.besideFold
import com.sangwook.ptimer.app.ui.shooting.rememberWindowFold

/** Upper bound for a modal task's width on a wide window (SHELL-060). */
private val BoundedModalMaxWidth = 640.dp

/** Space kept around a bounded modal. */
private val BoundedModalMargin = 24.dp

/**
 * The surface of a full-screen selection, management, editing or details
 * task. On a window wider than the task needs it becomes a centered card
 * of bounded width over a scrim instead of stretching its controls across
 * the window (SHELL-060), on the larger side of an active fold
 * (SHELL-061). The composition is the same in both presentations, so a
 * resize keeps the task's state (SHELL-053).
 */
@Composable
fun BoundedModalSurface(content: @Composable () -> Unit) {
    val fold = rememberWindowFold()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val bounded = maxWidth >= BoundedModalMaxWidth + BoundedModalMargin * 2
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(if (bounded) MaterialTheme.colorScheme.scrim.copy(alpha = 0.32f) else Color.Transparent)
                .besideFold(fold, FoldSide.Larger, fillsHeight = true),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = if (bounded) {
                    // The card sits inside the system bars, which it
                    // consumes, so the task's own insets are not added
                    // again inside it.
                    Modifier
                        .windowInsetsPadding(WindowInsets.safeDrawing)
                        .padding(BoundedModalMargin)
                        .widthIn(max = BoundedModalMaxWidth)
                        .fillMaxSize()
                } else {
                    Modifier.fillMaxSize()
                },
                shape = if (bounded) MaterialTheme.shapes.extraLarge else RectangleShape,
            ) {
                content()
            }
        }
    }
}
