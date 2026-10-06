// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.AuxiliaryFilterSummaryDisplayState
import com.sangwook.ptimer.app.vm.AuxiliaryFilterSummaryItemDisplay
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.ui.theme.filterSetColor

/**
 * The Main summary of the mounted auxiliary filters (FILTER-AUX-001/002):
 * one space immediately after Base Shutter, the same width as an ND
 * wheel, shown only while an auxiliary filter is mounted. The label row
 * names the space and leads to the shooting popup; below it, one compact
 * row per item — a short identifier and its current contribution in
 * stops — for the first three items in display order, spread down the
 * space, and a `+ N more` line for the rest. The space never scrolls.
 *
 * The whole column is one button (FILTER-A11Y-001) that speaks every
 * mounted item, including the ones the count hides, and opens the
 * popup; it never pretends to be an adjustable wheel.
 * (iOS: `AuxiliaryFilterSummaryView`.)
 */
@Composable
internal fun AuxiliaryFilterSummaryColumn(
    summary: AuxiliaryFilterSummaryDisplayState,
    viewportHeight: Dp,
    enabled: Boolean,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val title = stringResource(R.string.filter_auxiliary_title)
    val openLabel = stringResource(R.string.filter_auxiliary_open)
    val spoken = (listOf(title) + summary.items.map { auxiliarySummaryItemSpokenText(it) }).joinToString(", ")
    val moreText = summary.hiddenItemCount.takeIf { it > 0 }?.let { stringResource(R.string.filter_auxiliary_more, it) }

    Column(
        modifier = modifier
            .clickable(enabled = enabled, onClickLabel = openLabel, onClick = onOpen)
            .clearAndSetSemantics {
                contentDescription = spoken
                role = Role.Button
                if (enabled) {
                    onClick(openLabel) {
                        onOpen()
                        true
                    }
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // The label row every wheel column reserves (FILTER-STACK-007),
        // here naming the space and leading to the popup.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(FilterWheelLabelRowHeight),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "$title ›",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
                softWrap = false,
                autoSize = TextAutoSize.StepBased(
                    minFontSize = MaterialTheme.typography.labelSmall.fontSize * 0.7f,
                    maxFontSize = MaterialTheme.typography.labelSmall.fontSize,
                ),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .height(viewportHeight)
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f))
                .padding(horizontal = 3.dp),
        ) {
            // One to three rows spread down the space rather than packed
            // at the top (FILTER-AUX-002).
            summary.visibleItems.forEach { item ->
                Spacer(Modifier.weight(1f))
                AuxiliarySummaryRow(item)
            }
            if (moreText != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    moreText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Clip,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

/**
 * One compact summary row: the optical-color dot of a Color filter, the
 * longest identifier candidate that fits the column whole, and the
 * contribution trailing. The last candidate may shrink slightly instead
 * of being cut (FILTER-AUX-002).
 */
@Composable
private fun AuxiliarySummaryRow(item: AuxiliaryFilterSummaryItemDisplay) {
    val nameStyle = MaterialTheme.typography.bodySmall
    val valueStyle = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold)
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        item.opticalColor?.let {
            SourceCue(filterSetColor(it), size = 6.dp)
            Spacer(Modifier.width(3.dp))
        }
        BoxWithConstraints(modifier = Modifier.weight(1f)) {
            val label = fittingLabel(item.compactLabels, nameStyle, maxWidth)
            Text(
                label,
                style = nameStyle,
                maxLines = 1,
                softWrap = false,
                autoSize = if (label == item.compactLabels.last()) {
                    TextAutoSize.StepBased(minFontSize = nameStyle.fontSize * 0.8f, maxFontSize = nameStyle.fontSize)
                } else {
                    null
                },
                overflow = TextOverflow.Clip,
            )
        }
        Spacer(Modifier.width(4.dp))
        Text(item.contributionText, style = valueStyle, maxLines = 1, softWrap = false)
    }
}

/** The first identifier candidate that fits [width] whole; the last
 *  candidate when none does. */
@Composable
private fun fittingLabel(candidates: List<String>, style: TextStyle, width: Dp): String {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val widthPx = with(density) { width.toPx() }
    return candidates.firstOrNull { candidate ->
        measurer.measure(candidate, style, softWrap = false, maxLines = 1).size.width <= widthPx
    } ?: candidates.last()
}

/** `Soft GND 2, GND Record only, 0 stops` — name, type or mode, and
 *  contribution, spoken for every mounted item. */
@Composable
private fun auxiliarySummaryItemSpokenText(item: AuxiliaryFilterSummaryItemDisplay): String {
    val kind = localizedFilterKindName(item.kind)
    val type = when {
        item.kind == FilterItemKind.gnd && item.gndMode != null -> "$kind ${localizedGndModeName(item.gndMode)}"
        item.opticalColor != null -> "$kind ${filterColorName(item.opticalColor)}"
        else -> kind
    }
    return "${item.name}, $type, ${filterStopsText(item.contributionStops)}"
}
