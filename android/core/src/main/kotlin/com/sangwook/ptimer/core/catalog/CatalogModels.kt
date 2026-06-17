package com.sangwook.ptimer.core.catalog

import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.core.reciprocity.TableInterpolationRule
import kotlinx.serialization.Serializable

/**
 * Catalog/profile domain modeled against the current catalog JSON shape.
 * Display-only fields the calculation/validation paths do not need
 * (adjustments, source-evidence rows, model-basis, notes) are intentionally
 * not declared and are ignored on decode (see [CatalogJson]); they belong to
 * the deferred Details layer. Mirrors the calc-relevant subset of iOS
 * `FilmIdentity` / `ReciprocityProfile`.
 */
@Serializable
data class FilmIdentity(
    val id: String,
    val kind: String,
    val canonicalStockName: String,
    val manufacturer: String? = null,
    val brandLabel: String? = null,
    val aliases: List<String> = emptyList(),
    val iso: Int,
    val productionStatus: String,
    val profiles: List<ReciprocityProfile> = emptyList(),
    val userMetadata: UserEditableMetadata? = null,
)

/** User-editable metadata; `referenceTableFilmID` (PTIMER-180) is additive/display-only. */
@Serializable
data class UserEditableMetadata(
    val displayNameOverride: String? = null,
    val tags: List<String> = emptyList(),
    val notes: String? = null,
    val customSourceType: String? = null,
    val customManufacturer: String? = null,
    val referenceURL: String? = null,
    val referenceTableFilmID: String? = null,
)

@Serializable
data class ReciprocityProfile(
    val id: String,
    val name: String,
    val source: SourceProvenance,
    val rules: List<RawRule> = emptyList(),
    val selectorLabel: String? = null,
    val userMetadata: UserEditableMetadata? = null,
) {
    /** Typed, calculation-relevant rules (drops anything unrecognized). */
    val typedRules: List<ReciprocityRule> get() = rules.mapNotNull { it.toTyped() }
}

@Serializable
data class SourceProvenance(
    val kind: String,
    val authority: String,
    val confidence: String = "unknown",
    val publisher: String = "",
    val title: String? = null,
    val citation: String? = null,
    val sourceVersion: String? = null,
)

@Serializable
data class TimeRange(
    val minimumSeconds: Double,
    val maximumSeconds: Double? = null,
) {
    fun contains(seconds: Double): Boolean {
        if (seconds < minimumSeconds) return false
        val max = maximumSeconds ?: return true
        return seconds <= max
    }
}

/** Raw rule mirrors the `{ "kind": "...", "<kind>": { ... } }` JSON encoding. */
@Serializable
data class RawRule(
    val kind: String,
    val formula: FormulaRulePayload? = null,
    val tableInterpolation: TableRulePayload? = null,
    val threshold: ThresholdRulePayload? = null,
    val limitedGuidance: LimitedGuidanceRulePayload? = null,
) {
    fun toTyped(): ReciprocityRule? = when (kind) {
        "formula" -> formula?.formula?.let { ReciprocityRule.Formula(it) }
        "tableInterpolation" -> tableInterpolation?.let {
            ReciprocityRule.Table(
                TableInterpolationRule(it.anchors, it.noCorrectionThroughSeconds, it.sourceRangeThroughSeconds)
            )
        }
        "threshold" -> threshold?.let { ReciprocityRule.Threshold(it.noCorrectionRange) }
        "limitedGuidance" -> limitedGuidance?.let { ReciprocityRule.LimitedGuidance(it.appliesWhenMetered) }
        else -> null
    }
}

@Serializable
data class FormulaRulePayload(val formula: ReciprocityFormula)

@Serializable
data class TableRulePayload(
    val anchors: List<TableAnchor> = emptyList(),
    val noCorrectionThroughSeconds: Double,
    val sourceRangeThroughSeconds: Double,
)

@Serializable
data class ThresholdRulePayload(val noCorrectionRange: TimeRange)

@Serializable
data class LimitedGuidanceRulePayload(val appliesWhenMetered: TimeRange? = null)

/** Typed, calculation-relevant reciprocity rule. */
sealed interface ReciprocityRule {
    data class Formula(val formula: ReciprocityFormula) : ReciprocityRule
    data class Table(val rule: TableInterpolationRule) : ReciprocityRule
    data class Threshold(val noCorrectionRange: TimeRange) : ReciprocityRule
    data class LimitedGuidance(val appliesWhenMetered: TimeRange?) : ReciprocityRule
}
