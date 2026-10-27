// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.sangwook.ptimer.app.vm.TargetNDProposalDisplayState

/** Replaces content inside the ordinary status row, preserving its metrics.
 * The legacy review selector never changes geometry. */
@Composable
internal fun TargetNDReviewRegion(proposal: TargetNDProposalDisplayState?,
    totalStyle: TextStyle, currentTotal: String, currentTotalValue: String, onApply: () -> Unit, onFocus: (Boolean) -> Unit,
    ordinary: @Composable () -> Unit) {
    val rowHeight = filterStatusRegionHeight(totalStyle)
    Box(Modifier.fillMaxWidth().height(rowHeight).clipToBounds().testTag("target-nd-review-region")) {
        if (proposal == null) { ordinary(); return@Box }
        Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val warning = proposal.warning
            val color = if (warning == null) MaterialTheme.colorScheme.primary else Color(0xffffb74d)
            if (proposal.canApply && proposal.action != null && proposal.candidateTotalText != null) {
                if (warning != null) Text(warning, style = MaterialTheme.typography.labelSmall,
                    color = color, maxLines = 1, modifier = Modifier.weight(1f).testTag("target-nd-review-guidance"))
                else Spacer(Modifier.weight(1f))
                val focus by rememberUpdatedState(onFocus)
                val apply by rememberUpdatedState(onApply)
                Box(Modifier.height(rowHeight)) {
                    Box(Modifier.matchParentSize().padding(top = 4.dp).border(0.5.dp, color, RoundedCornerShape(3.dp)))
                    Text(prominentTotal(proposal.action, proposal.candidateTotalText, totalStyle),
                        style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1,
                        modifier = Modifier.align(Alignment.Center).padding(horizontal = 3.dp).clearAndSetSemantics {})
                    // Native focus lifecycle without a native Button's minimum
                    // size or an invisible expansion into adjacent wheel space.
                    AndroidView(modifier = Modifier.matchParentSize().padding(top = 4.dp).testTag("target-nd-review-apply"), factory = { context ->
                        TextView(context).apply {
                            isClickable = true; isFocusable = true; minimumHeight = 0; minimumWidth = 0
                            setPadding(0, 0, 0, 0); setTextColor(android.graphics.Color.TRANSPARENT)
                            setOnClickListener { apply() }
                            accessibilityDelegate = object : View.AccessibilityDelegate() {
                                override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                                    super.onInitializeAccessibilityNodeInfo(host, info)
                                    info.className = "android.widget.Button"
                                }
                                override fun sendAccessibilityEvent(host: View, eventType: Int) {
                                    if (eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) focus(true)
                                    if (eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED) focus(false)
                                    super.sendAccessibilityEvent(host, eventType)
                                }
                                override fun sendAccessibilityEventUnchecked(host: View, event: AccessibilityEvent) {
                                    if (event.eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) focus(true)
                                    if (event.eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED) focus(false)
                                    super.sendAccessibilityEventUnchecked(host, event)
                                }
                            }
                        }
                    }, update = { button ->
                        button.text = proposal.action
                        button.contentDescription = listOfNotNull(proposal.action, warning, proposal.fullText).joinToString(". ")
                    })
                }
            } else {
                if (proposal.isLive) Spacer(Modifier.weight(1f))
                Text(proposal.required, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface, maxLines = 1,
                    modifier = (if (proposal.isLive) Modifier else Modifier.weight(1f))
                        .semantics { contentDescription = proposal.fullText }.testTag("target-nd-review-guidance"))
                if (proposal.isNoCombination) Text(prominentTotal(currentTotal, currentTotalValue, totalStyle),
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1, modifier = Modifier.testTag("target-nd-current-total"))
            }
        }
    }
}
