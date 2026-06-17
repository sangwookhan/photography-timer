package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.catalog.FilmIdentity
import com.sangwook.ptimer.core.catalog.FormulaRulePayload
import com.sangwook.ptimer.core.catalog.RawRule
import com.sangwook.ptimer.core.catalog.ReciprocityProfile
import com.sangwook.ptimer.core.catalog.SourceProvenance
import com.sangwook.ptimer.core.catalog.TableRulePayload
import com.sangwook.ptimer.core.catalog.UserEditableMetadata
import com.sangwook.ptimer.core.reciprocity.CustomFilmFormulaGuard
import com.sangwook.ptimer.core.reciprocity.ReciprocityFormula
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.core.reciprocity.TableInterpolationRule

/** Outcome of building/validating a custom film. */
sealed interface CustomFilmResult {
    data class Success(val film: FilmIdentity) : CustomFilmResult
    data class Failure(val reason: String) : CustomFilmResult
}

/**
 * Builds and validates custom-film [FilmIdentity]s (formula XOR table, fixed
 * at creation). Enforces the no-shortening guard for formulas and the
 * safe-table contract for tables. Android-free / JVM-testable. Mirrors the
 * build/validate intent of iOS `CustomFilmEditorFormState`.
 */
object CustomFilmFactory {

    private fun userSource() = SourceProvenance(kind = "userDefined", authority = "userDefined", publisher = "User")

    fun buildFormula(
        id: String,
        name: String,
        iso: Int,
        coefficientSeconds: Double = 1.0,
        referenceMeteredTimeSeconds: Double = 1.0,
        exponent: Double,
        offsetSeconds: Double = 0.0,
        noCorrectionThroughSeconds: Double,
        sourceRangeThroughSeconds: Double? = null,
        referenceTableFilmId: String? = null,
    ): CustomFilmResult {
        if (name.isBlank()) return CustomFilmResult.Failure("Name is required.")
        if (iso <= 0) return CustomFilmResult.Failure("ISO must be positive.")
        val formula = ReciprocityFormula(
            coefficientSeconds = coefficientSeconds,
            referenceMeteredTimeSeconds = referenceMeteredTimeSeconds,
            exponent = exponent,
            offsetSeconds = offsetSeconds,
            noCorrectionThroughSeconds = noCorrectionThroughSeconds,
            sourceRangeThroughSeconds = sourceRangeThroughSeconds,
        )
        if (!formula.hasValidParameters) return CustomFilmResult.Failure("Formula parameters are invalid.")
        val passes = CustomFilmFormulaGuard.passesUsableRangeCheck(
            CustomFilmFormulaGuard.UsableRangeInput(
                exponent = exponent,
                referenceMeteredTimeSeconds = referenceMeteredTimeSeconds,
                coefficientSeconds = coefficientSeconds,
                offsetSeconds = offsetSeconds,
                noCorrectionThroughSeconds = noCorrectionThroughSeconds,
                sourceRangeThroughSeconds = sourceRangeThroughSeconds,
            ),
        )
        if (!passes) return CustomFilmResult.Failure("Formula would shorten the exposure (Tc < Tm).")

        return CustomFilmResult.Success(
            FilmIdentity(
                id = id, kind = "custom", canonicalStockName = name.trim(), iso = iso, productionStatus = "current",
                userMetadata = referenceTableFilmId?.let { UserEditableMetadata(referenceTableFilmID = it) },
                profiles = listOf(
                    ReciprocityProfile(
                        id = "$id-profile", name = "Custom formula", source = userSource(),
                        selectorLabel = "Custom formula",
                        rules = listOf(RawRule(kind = "formula", formula = FormulaRulePayload(formula))),
                    ),
                ),
            ),
        )
    }

    fun buildTable(
        id: String,
        name: String,
        iso: Int,
        anchors: List<TableAnchor>,
        noCorrectionThroughSeconds: Double? = null,
    ): CustomFilmResult {
        if (name.isBlank()) return CustomFilmResult.Failure("Name is required.")
        if (iso <= 0) return CustomFilmResult.Failure("ISO must be positive.")
        val sorted = anchors.sortedBy { it.meteredSeconds }
        if (sorted.size < 2) return CustomFilmResult.Failure("At least two anchors are required.")
        val firstMetered = sorted.first().meteredSeconds
        val noCorrection = noCorrectionThroughSeconds ?: minOf(0.5, firstMetered / 2.0)
        if (noCorrection <= 0 || noCorrection >= firstMetered) {
            return CustomFilmResult.Failure("No-correction must be positive and below the first anchor.")
        }
        val rule = TableInterpolationRule(
            anchors = sorted,
            noCorrectionThroughSeconds = noCorrection,
            sourceRangeThroughSeconds = sorted.last().meteredSeconds,
        )
        if (!rule.hasValidParameters) return CustomFilmResult.Failure("Table anchors violate the safe-table contract.")

        return CustomFilmResult.Success(
            FilmIdentity(
                id = id, kind = "custom", canonicalStockName = name.trim(), iso = iso, productionStatus = "current",
                profiles = listOf(
                    ReciprocityProfile(
                        id = "$id-profile", name = "Custom table", source = userSource(),
                        selectorLabel = "Custom table",
                        rules = listOf(
                            RawRule(
                                kind = "tableInterpolation",
                                tableInterpolation = TableRulePayload(sorted, noCorrection, sorted.last().meteredSeconds),
                            ),
                        ),
                    ),
                ),
            ),
        )
    }
}
