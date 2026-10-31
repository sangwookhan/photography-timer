// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Long values reflow within the same row height rather than squeezing away the result label. */
@Composable
internal fun PhoneExposureResultRow(
    label: String,
    value: String,
    secondary: String?,
    valueColor: Color,
    numeric: Boolean,
    onStart: () -> Unit,
    startEnabled: Boolean,
    startContentDescription: String,
) {
    val labelStyle = mainLabelStyle()
    val valueStyle = MaterialTheme.typography.titleMedium.copy(
        fontSize = 22.sp,
        fontWeight = FontWeight.Bold,
        fontFamily = if (numeric) FontFamily.Monospace else FontFamily.Default,
    )
    val secondaryStyle = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace)
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    fun width(text: String, style: androidx.compose.ui.text.TextStyle) =
        measurer.measure(text, style, maxLines = 1, softWrap = false).size.width
    BoxWithConstraints(Modifier.fillMaxWidth().height(mainResultRowHeight)) {
        val textWidth = width(label, labelStyle) + width(value, valueStyle) +
            (secondary?.let { width(it, secondaryStyle) } ?: 0)
        val fitsOneRow = textWidth + with(density) { (48.dp + if (secondary == null) 16.dp else 24.dp).roundToPx() } <=
            with(density) { maxWidth.roundToPx() }
        Row(
            modifier = Modifier.fillMaxWidth().height(mainResultRowHeight),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (fitsOneRow) {
                Text(label, style = labelStyle, maxLines = 1, modifier = Modifier.weight(1f),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                secondary?.let { Text(it, style = secondaryStyle, maxLines = 1,
                    color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Text(value, style = valueStyle, maxLines = 1, color = valueColor)
            } else {
                Column(Modifier.weight(1f)) {
                    Text(label, style = labelStyle, maxLines = 1, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        secondary?.let { Text(it, style = secondaryStyle, maxLines = 1,
                            color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        Text(value, style = valueStyle, maxLines = 1, color = valueColor)
                    }
                }
            }
            StartButton(onStart, startEnabled, startContentDescription)
        }
    }
}
