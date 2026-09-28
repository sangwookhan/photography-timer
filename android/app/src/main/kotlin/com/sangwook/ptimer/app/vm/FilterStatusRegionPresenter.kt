// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterSetColor

/**
 * Leading content of the one-row status region (FILTER-STACK-008).
 * Structured, not text: the display layer localizes the reason, the
 * item detail, and the summary, and draws the source-color cues.
 * (iOS: the `primaryText` / `idleSourceSummary` pair of
 * `FilterStatusRegionContent`.)
 */
sealed class FilterStatusLeading {
    /** A refused change or addition; rendered in the warning color. */
    data class Rejection(val notice: FilterRejectionNotice) : FilterStatusLeading()

    /** The Plus wheel's current browsing candidate. */
    data class BrowsingSource(val name: String, val color: FilterSetColor?) : FilterStatusLeading()

    /** The displayed row of the wheel under a finger. */
    data class MovingRow(
        val row: FilterWheelRowUiState,
        val sourceName: String,
    ) : FilterStatusLeading()

    /** The persistent idle summary of a stack holding any Filter Set wheel. */
    data class IdleSummary(val items: List<FilterSourceSummaryItem>) : FilterStatusLeading()

    /** Total only (the Standard-only stack's existing behavior). */
    data object None : FilterStatusLeading()
}

/**
 * The single stable status region of the mixed-stack interaction
 * (FILTER-STACK-008): exactly one visual row in every state. The
 * leading content is the idle source summary, the moving wheel's row,
 * the Plus browsing candidate, or a rejection reason; [total] is the
 * localized total, which always stays complete while the leading
 * content yields space and truncates at its trailing edge.
 * (iOS: `FilterStatusRegionContent`.)
 */
data class FilterStatusRegionContent(
    val leading: FilterStatusLeading,
    val total: String,
    /** True for a rejection reason; the view tints the leading text. */
    val isWarning: Boolean = false,
    /** True while the content stays until it changes: an interaction in
     *  progress, or the persistent idle source summary. False for the
     *  Standard-only idle total, which fades after a short interval
     *  while the region keeps its geometry. */
    val isHeld: Boolean,
    /** True for the persistent idle source summary: rendered at
     *  secondary emphasis so moving and rejection content reads as the
     *  active state. */
    val isSecondaryEmphasis: Boolean = false,
) {
    /** The persistent idle state: held, secondary, never a warning. */
    val isPersistentIdle: Boolean get() = isHeld && isSecondaryEmphasis
}

/**
 * Pure composition of the region content from the interaction facts.
 * Priority: a rejection replaces movement (reason, unchanged total);
 * Plus browsing shows the candidate source; a moving wheel shows its
 * expanded information; otherwise the persistent source summary for a
 * stack holding any Filter Set wheel (FILTER-STACK-008), or the
 * Standard-only idle total when two or more wheels are stacked
 * (ND-INTERACT-020).
 *
 * [totalText] arrives already localized — Android localizes at the
 * display boundary, so this value stays a pure arrangement.
 * (iOS: `FilterStatusRegionPresenter`.)
 */
object FilterStatusRegionPresenter {

    fun content(
        moving: FilterStatusLeading.MovingRow?,
        browsing: FilterStatusLeading.BrowsingSource?,
        rejection: FilterRejectionNotice?,
        totalText: String,
        idleSourceSummary: List<FilterSourceSummaryItem>?,
        isStandardTotalVisible: Boolean,
    ): FilterStatusRegionContent? {
        if (rejection != null) {
            return FilterStatusRegionContent(
                leading = FilterStatusLeading.Rejection(rejection),
                total = totalText,
                isWarning = true,
                isHeld = true,
            )
        }
        if (browsing != null) {
            return FilterStatusRegionContent(leading = browsing, total = totalText, isHeld = true)
        }
        if (moving != null) {
            return FilterStatusRegionContent(leading = moving, total = totalText, isHeld = true)
        }
        if (!idleSourceSummary.isNullOrEmpty()) {
            return FilterStatusRegionContent(
                leading = FilterStatusLeading.IdleSummary(idleSourceSummary),
                total = totalText,
                isHeld = true,
                isSecondaryEmphasis = true,
            )
        }
        if (!isStandardTotalVisible) return null
        return FilterStatusRegionContent(
            leading = FilterStatusLeading.None,
            total = totalText,
            isHeld = false,
        )
    }
}
