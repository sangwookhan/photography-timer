// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.reciprocity

/**
 * Derives the short legend glossary shown beneath the reciprocity details: the
 * meaning of any color-correction filters, development adjustments, and
 * stop-signal warnings the active profile carries. Faithful port of iOS
 * FilmModeDetailsLegendPresenter, minus the graph-sampled-row provenance line
 * (Android has no source-evidence classifier yet).
 */
object ReciprocityDetailsLegendPresenter {
    fun legendLines(profile: ReciprocityProfile): List<String> {
        val ruleAdjustments = profile.rules.flatMap { rule ->
            when (rule.kind) {
                ReciprocityRuleKind.threshold -> rule.threshold?.adjustments.orEmpty()
                ReciprocityRuleKind.formula -> rule.formula?.additionalAdjustments.orEmpty()
                ReciprocityRuleKind.limitedGuidance -> rule.limitedGuidance?.adjustments.orEmpty()
                ReciprocityRuleKind.tableInterpolation -> rule.tableInterpolation?.additionalAdjustments.orEmpty()
            }
        }
        val evidenceAdjustments = profile.sourceEvidence.flatMap { it.adjustments }
        val presentations = ReciprocitySecondaryGuidanceFormatter.format(ruleAdjustments + evidenceAdjustments)
        if (presentations.isEmpty()) return emptyList()

        val lines = mutableListOf<String>()

        val colorValues = presentations
            .filter { it.kind == SecondaryGuidanceKind.colorCorrection }
            .mapNotNull { it.valueText }
        if (colorValues.isNotEmpty()) {
            colorCorrectionLegendLine(colorValues)?.let { lines.add(it) }
        }

        if (presentations.any { it.kind == SecondaryGuidanceKind.developmentAdjustment }) {
            lines.add("Development adjustment: Dev -10% means adjust development time by -10%.")
        }

        if (presentations.any {
                it.kind == SecondaryGuidanceKind.warning && it.severity == SecondaryGuidanceSeverity.stop
            }
        ) {
            lines.add("Warning: Not recommended marks a manufacturer stop-signal.")
        }

        return lines
    }

    private fun colorCorrectionLegendLine(filterNames: List<String>): String? {
        filterNames.firstOrNull { it.uppercase().startsWith("CC") }?.let { kodakName ->
            val description = colorChannelDescription(trailingChannelLetter(kodakName))
            return "Color correction: $kodakName = color-compensating $description filtration."
        }

        val trailingLetters = filterNames.mapNotNull { trailingChannelLetter(it) }.toSet()
        if (trailingLetters.size == 1) {
            val letter = trailingLetters.first()
            return "Color correction: $letter = ${colorChannelDescription(letter)} filtration."
        }

        return null
    }

    private fun trailingChannelLetter(filterName: String): String? {
        val last = filterName.lastOrNull() ?: return null
        if (!last.isLetter()) return null
        return last.uppercase()
    }

    private fun colorChannelDescription(channel: String?): String = when (channel?.uppercase()) {
        "M" -> "magenta"
        "G" -> "green"
        "B" -> "blue"
        "Y" -> "yellow"
        "C" -> "cyan"
        "R" -> "red"
        else -> "color"
    }
}
