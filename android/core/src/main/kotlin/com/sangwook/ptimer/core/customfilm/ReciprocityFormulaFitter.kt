// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.customfilm

import com.sangwook.ptimer.core.reciprocity.TableAnchor
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln

/**
 * Fits a two-parameter power law `Tc = a × Tm^p` to reciprocity table anchors
 * by ordinary least squares on `(ln Tm, ln Tc)`. Deterministic and dependency-
 * free; the offset (`b`) and reference (`Tref`) degrees of freedom are
 * deliberately omitted (`b = 0`, `Tref = 1`), matching the shipped app-derived
 * shape. (iOS: ReciprocityFormulaFitter.)
 */
object ReciprocityFormulaFitter {
    data class PowerLawFit(val coefficient: Double, val exponent: Double)

    enum class UnavailableReason { insufficientAnchors, nonPositiveAnchors, degenerateAnchors, nonFiniteResult }

    sealed interface FitResult {
        data class Success(val fit: PowerLawFit) : FitResult
        data class Failure(val reason: UnavailableReason) : FitResult
    }

    fun fit(anchors: List<TableAnchor>): FitResult {
        if (anchors.size < 2) return FitResult.Failure(UnavailableReason.insufficientAnchors)
        anchors.forEach {
            if (!(it.meteredSeconds.isFinite() && it.meteredSeconds > 0 &&
                    it.correctedSeconds.isFinite() && it.correctedSeconds > 0)
            ) {
                return FitResult.Failure(UnavailableReason.nonPositiveAnchors)
            }
        }
        val xs = anchors.map { ln(it.meteredSeconds) }
        val ys = anchors.map { ln(it.correctedSeconds) }
        val n = anchors.size.toDouble()
        val sx = xs.sum()
        val sy = ys.sum()
        val sxx = xs.sumOf { it * it }
        val sxy = xs.indices.sumOf { xs[it] * ys[it] }
        val denominator = n * sxx - sx * sx
        if (abs(denominator) <= Math.ulp(1.0)) return FitResult.Failure(UnavailableReason.degenerateAnchors)
        val exponent = (n * sxy - sx * sy) / denominator
        val coefficient = exp((sy - exponent * sx) / n)
        if (!exponent.isFinite() || !coefficient.isFinite()) return FitResult.Failure(UnavailableReason.nonFiniteResult)
        return FitResult.Success(PowerLawFit(coefficient, exponent))
    }
}
