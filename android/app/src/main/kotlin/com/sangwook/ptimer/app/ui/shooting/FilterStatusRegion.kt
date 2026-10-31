// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.platform.testTag
import com.sangwook.ptimer.app.vm.RequiredNDGuidanceState
import com.sangwook.ptimer.core.exposure.RequiredNDResult
import java.util.Locale
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
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

/** MINIMUM height reserved for the one-row status region
 *  (FILTER-STACK-008). The region never grows or disappears with its
 *  CONTENT, so a state change cannot move a picker or its touch center;
 *  [filterStatusRegionHeight] grows it with the text size. */
internal val FilterStatusRegionHeight = 20.dp

/**
 * The height the one-row status region reserves at the current system
 * font scale: [FilterStatusRegionHeight], or the line its own style
 * renders if that is taller.
 *
 * FILTER-STACK-008 reserves "only the height required for one visual
 * row plus its normal vertical padding" and asks for the total to stay
 * "visible and untruncated". A fixed 20dp is the height that row needs
 * at the DEFAULT text size only. Measured on the rendered screen at
 * 360dp in Korean, the row's line box was 55px at 1.3x and 84px at 2.0x
 * inside 52px of reserved height — and the card clips its content, so
 * the total lost the bottom of its glyphs. The row follows its rendered
 * metrics instead and the card grows, exactly as the wheels' rows
 * already do.
 *
 * Measured from a fixed probe rather than from the text on screen, so
 * the height stays the same in every state and in every language: the
 * probe carries a Latin ascender, a Latin descender and a Hangul
 * syllable, which is the tallest line either shipping language can put
 * in this row.
 */
@Composable
internal fun filterStatusRegionHeight(totalValueStyle: TextStyle = MaterialTheme.typography.labelSmall): Dp {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    // The row's tallest glyphs: the caption probe, or the Total's
    // numerals drawn at the ND value size (FILTER-STACK-008).
    val line = maxOf(
        measurer.measure(StatusRowProbe, MaterialTheme.typography.labelSmall, maxLines = 1, softWrap = false).size.height,
        measurer.measure("0123456789.", totalValueStyle, maxLines = 1, softWrap = false).size.height,
    )
    return maxOf(FilterStatusRegionHeight, with(density) { line.toDp() })
}

private const val StatusRowProbe = "Agp합" 

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
    /** The Total's numeric stops value (`13.2`), drawn at [totalValueStyle]
     *  inside the localized total so the numerals read at least at the
     *  ND value size of the same layout (FILTER-STACK-008). */
    totalValueText: String? = null,
    totalValueStyle: TextStyle = MaterialTheme.typography.labelSmall,
    requiredND: RequiredNDGuidanceState = RequiredNDGuidanceState(),
    onRequiredNDComplete: (Int) -> Unit = {},
    actualTotal: String = "",
    guidanceSourceSummary: List<FilterSourceSummaryItem>? = null,
) {
    var visible by remember { mutableStateOf(content) }
    var lastWheelCount by remember { mutableIntStateOf(wheelCount) }

    LaunchedEffect(content, wheelCount, requiredND.phase) {
        val added = wheelCount > lastWheelCount
        lastWheelCount = wheelCount
        val current = visible
        if (content == null) {
            visible = null
            return@LaunchedEffect
        }
        // Keep current ordinary content mounted while guidance owns the
        // row; restart the existing lifetime when the crossfade completes.
        if (requiredND.phase != RequiredNDGuidanceState.Phase.Ordinary) {
            visible = content
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

    val shown = if (requiredND.result != null) content else visible
    val progress = remember(requiredND.generation) { Animatable(if (requiredND.phase == RequiredNDGuidanceState.Phase.Ordinary) 1f else 0f) }
    LaunchedEffect(requiredND.phase, requiredND.generation) {
        when (requiredND.phase) {
            RequiredNDGuidanceState.Phase.Ordinary -> progress.snapTo(1f)
            RequiredNDGuidanceState.Phase.Tracking -> progress.snapTo(0f)
            RequiredNDGuidanceState.Phase.Crossfading -> {
                progress.animateTo(1f, tween(500, easing = LinearEasing))
                onRequiredNDComplete(requiredND.generation)
            }
        }
    }
    Box(modifier = modifier.fillMaxWidth().height(filterStatusRegionHeight(totalValueStyle))) {
        if (requiredND.result != null) {
            RequiredNDRow(requiredND.result, guidanceSourceSummary, actualTotal, notationMode, totalValueStyle,
                Modifier.fillMaxWidth().align(Alignment.Center).alpha(1f - progress.value))
        }
        if (shown != null) {
            val leading = leadingContent(shown.leading, notationMode)
            Row(
                modifier = Modifier.fillMaxWidth().align(Alignment.Center).alpha(progress.value)
                    .then(if (requiredND.result != null) Modifier.clearAndSetSemantics {} else Modifier),
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
                    text = prominentTotal(shown.total, totalValueText, totalValueStyle),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
        }
}

@Composable
private fun RequiredNDRow(
    result: RequiredNDResult,
    sourceSummary: List<FilterSourceSummaryItem>?,
    actualTotal: String,
    notationMode: NDNotationMode,
    valueStyle: TextStyle,
    modifier: Modifier,
) {
    val reason = when (result) {
        is RequiredNDResult.Value -> if (result.beyondSourceRange) stringResource(R.string.required_nd_beyond) else null
        is RequiredNDResult.Unavailable -> stringResource(when (result.reason) {
            RequiredNDResult.Reason.InvalidInput -> R.string.required_nd_invalid
            RequiredNDResult.Reason.NoQuantifiedInverse -> R.string.required_nd_no_inverse
            RequiredNDResult.Reason.MultipleSolutions -> R.string.required_nd_multiple
            RequiredNDResult.Reason.NumericalFailure -> R.string.required_nd_numerical
            RequiredNDResult.Reason.NegativeAttenuation -> R.string.required_nd_negative
        })
    }
    val value = if (result is RequiredNDResult.Value) {
        String.format(Locale.ROOT, "%.1f", result.stops).removeSuffix(".0")
    } else "—"
    val label = stringResource(R.string.required_nd_label)
    val valueText = if (result is RequiredNDResult.Value) stringResource(R.string.required_nd_stops, value) else value
    val spoken = listOfNotNull(reason, "$label $valueText", actualTotal).joinToString(". ")
    val source = if (reason == null) sourceSummary?.let {
        leadingContent(FilterStatusLeading.IdleSummary(it), notationMode)
    } else null
    val compactReason = when (result) {
        is RequiredNDResult.Value -> if (result.beyondSourceRange) stringResource(R.string.required_nd_beyond_short) else null
        is RequiredNDResult.Unavailable -> when (result.reason) {
            RequiredNDResult.Reason.NegativeAttenuation -> stringResource(R.string.required_nd_negative_short)
            else -> reason
        }
    }
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val reasonStyle = MaterialTheme.typography.labelSmall
    val warning = reason != null
    val color = if (warning) Color(0xFFB35A00) else Color(0xFF0085FF)
    Row(modifier.clearAndSetSemantics { contentDescription = spoken }
        .testTag("required-nd-guidance"), verticalAlignment = Alignment.CenterVertically) {
        if (reason != null) {
            BoxWithConstraints(Modifier.weight(1f)) {
                val fits = measurer.measure(reason, reasonStyle, maxLines = 1, softWrap = false).size.width <= with(density) { maxWidth.toPx() }
                Text(if (fits) reason else compactReason ?: reason, style = reasonStyle, color = color,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        } else if (source != null) {
            Text(source.annotated, inlineContent = source.inlineContent, style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        } else Spacer(Modifier.weight(1f))
        Spacer(Modifier.width(10.dp))
        Text(buildAnnotatedString {
            append("$label ")
            withStyle(SpanStyle(fontSize = valueStyle.fontSize, fontWeight = FontWeight.SemiBold)) { append(value) }
            if (result is RequiredNDResult.Value) append(valueText.removePrefix(value))
        }, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1, softWrap = false)
    }
}

/**
 * The localized total with its numeric value set in [valueStyle] and the
 * primary color: `Total` and `stops` stay caption words around a value
 * that reads directly in the field (FILTER-STACK-008).
 */
@Composable
private fun prominentTotal(total: String, value: String?, valueStyle: TextStyle): AnnotatedString {
    val start = value?.let { total.indexOf(it) } ?: -1
    if (value == null || start < 0) return AnnotatedString(total)
    val color = MaterialTheme.colorScheme.onSurface
    return buildAnnotatedString {
        append(total.substring(0, start))
        withStyle(SpanStyle(fontSize = valueStyle.fontSize, fontWeight = FontWeight.SemiBold, color = color)) {
            append(value)
        }
        append(total.substring(start + value.length))
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
