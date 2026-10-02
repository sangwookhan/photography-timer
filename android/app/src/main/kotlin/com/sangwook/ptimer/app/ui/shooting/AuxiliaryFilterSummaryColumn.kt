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
import androidx.compose.ui.text.style.LineBreak
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
 * names the space and leads to Shooting Filters; below it, one compact
 * row per item — a short identifier and its current contribution in
 * stops — for the first three items in display order, spread down the
 * space, and a `+ N more` line for the rest. The space never scrolls.
 *
 * The whole column is one button (FILTER-A11Y-001) that speaks every
 * mounted item, including the ones the count hides, and opens Shooting
 * Filters; it never pretends to be an adjustable wheel.
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
    val openLabel = stringResource(R.string.filter_shooting_open)
    val spoken = (listOf(title) + summary.items.map { auxiliarySummaryItemSpokenText(it) }).joinToString(", ")
    val moreText = summary.hiddenItemCount.takeIf { it > 0 }?.let { stringResource(R.string.filter_auxiliary_more, it) }

    // Below the label row every wheel column reserves (FILTER-STACK-007),
    // so the summary's background, frame, and touch area share the picker
    // viewports' top and bottom (FILTER-AUX-005); its title sits inside.
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(FilterWheelLabelRowHeight))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .height(viewportHeight)
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f))
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
                }
                .padding(horizontal = 3.dp, vertical = 4.dp),
        ) {
            // The title and the more-count wrap to a second line in a
            // narrow column rather than being cut; the rows keep their
            // size (FILTER-AUX-002).
            SummaryCue("$title ›")
            // One to three rows spread down the space rather than packed
            // at the top (FILTER-AUX-002).
            summary.visibleItems.forEach { item ->
                Spacer(Modifier.weight(1f))
                AuxiliarySummaryRow(item)
            }
            if (moreText != null) {
                Spacer(Modifier.weight(1f))
                SummaryCue(moreText)
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

/**
 * The summary's title or more-count, whole: on one line when it fits at
 * most slightly smaller, otherwise on two lines broken between words.
 */
@Composable
private fun SummaryCue(text: String) {
    val base = MaterialTheme.typography.labelSmall
    val style = base.copy(
        fontWeight = FontWeight.SemiBold,
        lineHeight = base.fontSize * 1.15f,
        lineBreak = LineBreak.Heading.copy(wordBreak = LineBreak.WordBreak.Phrase),
    )
    val minFontSize = base.fontSize * 0.8f
    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val measurer = rememberTextMeasurer()
        val widthPx = with(LocalDensity.current) { maxWidth.toPx() }
        val fitsOneLine = measurer.measure(text, style.copy(fontSize = minFontSize), softWrap = false, maxLines = 1).size.width <= widthPx
        Text(
            text,
            style = style,
            color = MaterialTheme.colorScheme.primary,
            maxLines = if (fitsOneLine) 1 else 2,
            softWrap = !fitsOneLine,
            autoSize = TextAutoSize.StepBased(minFontSize = minFontSize, maxFontSize = base.fontSize),
        )
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
