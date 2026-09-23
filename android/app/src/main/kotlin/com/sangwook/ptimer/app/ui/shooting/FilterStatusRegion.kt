// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.vm.FilterSourceSummaryItem
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionContent
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.ui.theme.filterSetColor
import kotlinx.coroutines.delay

/** Height reserved for the one-row status region (FILTER-STACK-008). The
 *  region never grows or disappears, so a state change cannot move a
 *  picker or its touch center. */
internal val FilterStatusRegionHeight = 20.dp

/** Diameter of a Filter Set source-color cue. */
private val SourceCueSize = 8.dp

/** How long settled detail lingers before the idle summary returns, and
 *  how long the Standard-only total stays before it fades. */
private const val LingerMillis = 1_500L

/** Slightly longer right after a wheel was added, so the add is
 *  acknowledged before the total fades. */
private const val AddedLingerMillis = 2_500L

/**
 * The single stable status region of the mixed-stack interaction
 * (FILTER-STACK-008), directly under the wheel row: exactly one visual
 * row in every state, the leading detail yielding space first while the
 * trailing total stays complete.
 *
 * Only presentation timing lives here — held content stays until it
 * changes, settled detail lingers before the persistent idle summary
 * returns, and the Standard-only total fades — while the content itself
 * is composed by [com.sangwook.ptimer.app.vm.FilterStatusRegionPresenter].
 *
 * Accessibility (FILTER-A11Y-005): two elements — the leading text,
 * whose content description is the complete untruncated detail, and the
 * total, reachable directly without listening through the summary.
 */
@Composable
internal fun FilterStatusRegion(
    content: FilterStatusRegionContent?,
    wheelCount: Int,
    notationMode: NDNotationMode,
    modifier: Modifier = Modifier,
) {
    var visible by remember { mutableStateOf(content) }
    var lastWheelCount by remember { mutableIntStateOf(wheelCount) }

    LaunchedEffect(content, wheelCount) {
        val added = wheelCount > lastWheelCount
        lastWheelCount = wheelCount
        val current = visible
        if (content == null) {
            visible = null
            return@LaunchedEffect
        }
        // Settlement after movement or browsing: keep the expanded detail
        // for the transient interval, then return to the source summary.
        if (content.isPersistentIdle &&
            current != null && current.isHeld && !current.isWarning && !current.isPersistentIdle
        ) {
            delay(LingerMillis)
            visible = content
            return@LaunchedEffect
        }
        visible = content
        if (!content.isHeld) {
            delay(if (added) AddedLingerMillis else LingerMillis)
            visible = null
        }
    }

    val shown = visible
    Box(modifier = modifier.fillMaxWidth().height(FilterStatusRegionHeight)) {
        if (shown == null) return@Box
        val leading = leadingContent(shown.leading, notationMode)
        Row(
            modifier = Modifier.fillMaxWidth().align(Alignment.Center),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (leading != null) {
                Text(
                    text = leading.annotated,
                    inlineContent = leading.inlineContent,
                    style = MaterialTheme.typography.labelSmall,
                    color = when {
                        shown.isWarning -> MaterialTheme.colorScheme.error
                        shown.isSecondaryEmphasis -> MaterialTheme.colorScheme.onSurfaceVariant
                        else -> MaterialTheme.colorScheme.onSurface
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = leading.plainText },
                )
                Spacer(Modifier.width(6.dp))
            } else {
                Spacer(Modifier.weight(1f))
            }
            Text(
                text = shown.total,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
        }
    }
}

/** One leading content: the laid-out text with its source-color cues,
 *  plus the complete text assistive technology reads. */
private class FilterStatusLeadingContent(
    val annotated: AnnotatedString,
    val inlineContent: Map<String, InlineTextContent>,
    val plainText: String,
)

@Composable
private fun leadingContent(
    leading: FilterStatusLeading,
    notationMode: NDNotationMode,
): FilterStatusLeadingContent? = when (leading) {
    is FilterStatusLeading.Rejection -> plainLeading(filterRejectionNoticeText(leading.notice))

    is FilterStatusLeading.BrowsingSource -> cuedLeading(
        listOf(leading.color?.let { filterSetColor(it) } to localizedSourceName(leading.name)),
    )

    is FilterStatusLeading.MovingRow ->
        plainLeading(filterRowDetailText(leading.row, notationMode))

    is FilterStatusLeading.IdleSummary -> cuedLeading(
        leading.items.map { item ->
            item.color?.let { filterSetColor(it) } to summaryItemText(item)
        },
    )

    FilterStatusLeading.None -> null
}

@Composable
private fun summaryItemText(item: FilterSourceSummaryItem): String {
    val name = localizedSourceName(item.name)
    return if (item.count > 1) stringResource(R.string.filter_summary_count, name, item.count) else name
}

private fun plainLeading(text: String) =
    FilterStatusLeadingContent(AnnotatedString(text), emptyMap(), text)

/** Source names preceded by their user-selected color cue, joined into
 *  one text so truncation, layout, and accessibility stay single-node. */
private fun cuedLeading(pieces: List<Pair<Color?, String>>): FilterStatusLeadingContent {
    val builder = AnnotatedString.Builder()
    val inlineContent = mutableMapOf<String, InlineTextContent>()
    val plain = StringBuilder()
    pieces.forEachIndexed { index, (color, text) ->
        if (index > 0) {
            builder.append(DetailSeparator)
            plain.append(DetailSeparator)
        }
        if (color != null) {
            val id = "source-cue-$index"
            inlineContent[id] = InlineTextContent(
                Placeholder(
                    width = SourceCueTextSize,
                    height = SourceCueTextSize,
                    placeholderVerticalAlign = PlaceholderVerticalAlign.TextCenter,
                ),
            ) {
                SourceCue(color, size = SourceCueSize)
            }
            builder.appendInlineContent(id, "•")
            builder.append(" ")
        }
        builder.append(text)
        plain.append(text)
    }
    return FilterStatusLeadingContent(builder.toAnnotatedString(), inlineContent, plain.toString())
}

private val SourceCueTextSize = 8.sp

/**
 * A Filter Set's source-color cue: a small filled dot with a hairline
 * outline so it stays visible on any card background. Redundant with the
 * source name beside it — never the only identification.
 */
@Composable
internal fun SourceCue(color: Color, modifier: Modifier = Modifier, size: Dp = SourceCueSize) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(color)
            .border(Dp.Hairline, MaterialTheme.colorScheme.outlineVariant, CircleShape),
    )
}
