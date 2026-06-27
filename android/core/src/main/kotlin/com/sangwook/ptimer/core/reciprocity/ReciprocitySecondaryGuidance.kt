// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

/**
 * Presentation-level secondary guidance derived from a profile's reciprocity
 * adjustments: color-correction filters, development adjustments, warnings, and
 * free-form notes. Exposure adjustments drive the calculation rather than this
 * surface, so they are omitted. Faithful port of iOS PTimerCore
 * ReciprocitySecondaryGuidancePresentation + ReciprocitySecondaryGuidanceFormatter.
 */
enum class SecondaryGuidanceKind { colorCorrection, developmentAdjustment, warning, note }

enum class SecondaryGuidanceSeverity { neutral, caution, stop }

data class ReciprocitySecondaryGuidance(
    val kind: SecondaryGuidanceKind,
    val title: String,
    val valueText: String?,
    val detailText: String,
    val severity: SecondaryGuidanceSeverity,
)

object ReciprocitySecondaryGuidanceFormatter {
    fun format(adjustments: List<ReciprocityAdjustment>): List<ReciprocitySecondaryGuidance> =
        adjustments.mapNotNull { adjustment ->
            when (adjustment.kind) {
                ReciprocityAdjustmentKind.colorFilter -> adjustment.colorFilter?.let { recommendation ->
                    ReciprocitySecondaryGuidance(
                        kind = SecondaryGuidanceKind.colorCorrection,
                        title = "Color correction",
                        valueText = recommendation.filterName,
                        detailText = recommendation.note ?: "",
                        severity = SecondaryGuidanceSeverity.neutral,
                    )
                }
                ReciprocityAdjustmentKind.development -> adjustment.development?.let { dev ->
                    ReciprocitySecondaryGuidance(
                        kind = SecondaryGuidanceKind.developmentAdjustment,
                        title = "Development adjustment",
                        valueText = dev.instruction,
                        detailText = dev.note ?: "",
                        severity = SecondaryGuidanceSeverity.neutral,
                    )
                }
                ReciprocityAdjustmentKind.warning -> adjustment.warning?.let { warning ->
                    ReciprocitySecondaryGuidance(
                        kind = SecondaryGuidanceKind.warning,
                        title = "Warning",
                        valueText = null,
                        detailText = warning.message,
                        severity = if (warning.severity == ReciprocityWarningSeverity.caution) {
                            SecondaryGuidanceSeverity.caution
                        } else {
                            SecondaryGuidanceSeverity.stop
                        },
                    )
                }
                ReciprocityAdjustmentKind.note -> adjustment.note
                    ?.takeIf { it.text.trim().isNotEmpty() }
                    ?.let { note ->
                        ReciprocitySecondaryGuidance(
                            kind = SecondaryGuidanceKind.note,
                            title = "Note",
                            valueText = null,
                            detailText = note.text,
                            severity = SecondaryGuidanceSeverity.caution,
                        )
                    }
                ReciprocityAdjustmentKind.exposure -> null
            }
        }
}
