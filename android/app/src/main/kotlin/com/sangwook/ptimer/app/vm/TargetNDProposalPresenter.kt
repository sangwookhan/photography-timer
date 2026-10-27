// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.*
import com.sangwook.ptimer.core.reciprocity.ReciprocityInverse
import com.sangwook.ptimer.core.reciprocity.ReciprocityInverseResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityInverseFailure
import java.util.Locale
import kotlin.math.log2

/** Real-value review presentation. Full physical names remain explicit in
 * accessibility; numerical combination is a proposed compact visible policy. */
data class TargetNDProposalDisplayState(val required: String, val combination: String? = null,
    val residual: String? = null, val warning: String? = null, val fullText: String = required, val canApply: Boolean = false, val candidateTotalText: String? = null, val action: String? = null, val isNoCombination: Boolean = false, val isLive: Boolean = false)

object TargetNDProposalPresenter {
    fun display(state: TargetNDProposalModel.State, locale: Locale): TargetNDProposalDisplayState? {
        val ko = locale.language == "ko"
        fun message(en: String, kr: String) = TargetNDProposalDisplayState(if (ko) kr else en)
        if (state.phase == TargetNDProposalSession.Phase.idle) return null
        if (state.phase == TargetNDProposalSession.Phase.applied) return message("ND applied", "ND 적용 완료")
        val input = state.input ?: return null
        val metered = input.profile?.let {
            val inverse = ReciprocityInverse().evaluate(it, input.targetSeconds)
            (inverse as? ReciprocityInverseResult.Available)?.meteredSeconds
                ?: return when ((inverse as? ReciprocityInverseResult.Unavailable)?.reason) {
                    ReciprocityInverseFailure.multipleSolutions -> message("Required ND unavailable: multiple inverse solutions", "필요 ND 계산 불가: 역산 해가 여러 개입니다")
                    ReciprocityInverseFailure.noQuantifiedSolution -> message("Required ND unavailable: no quantified inverse", "필요 ND 계산 불가: 정량 역산값이 없습니다")
                    ReciprocityInverseFailure.numericalFailure -> message("Required ND unavailable: numerical inverse failed", "필요 ND 계산 불가: 수치 역산 실패")
                    else -> message("Required ND unavailable: invalid calculation input", "필요 ND 계산 불가: 유효하지 않은 계산 입력")
                }
        } ?: input.targetSeconds
        val required = log2(metered) - log2(input.baseSeconds)
        if (!required.isFinite()) return message("Required ND unavailable: invalid input", "필요 ND 계산 불가: 유효하지 않은 입력")
        if (required < 0) return message("Attenuation cannot reach this Target", "감광으로 이 Target에 도달할 수 없습니다")
        val heading = (if (ko) "필요 ND: " else "Required ND: ") + String.format(Locale.ROOT, "%.1f", required) + if (ko) " 스톱" else " stops"
        val result = state.result ?: return TargetNDProposalDisplayState(heading, isLive = true)
        val candidate = (result as? TargetNDSelectionResult.Available)?.candidate
            ?: return if (result is TargetNDSelectionResult.Unavailable && result.reason == TargetNDSelectionFailure.NoCombination) {
                message("No suitable ND combination", "적합한 ND 조합 없음").copy(
                    fullText = if (ko) "허용 오차 내 ND 조합이 없습니다" else "No ND combination within allowed error",
                    isNoCombination = true,
                )
            } else message("Required ND unavailable", "필요 ND 계산 불가")
        if (candidate.isCurrent) return message("Current filters are suitable", "현재 필터가 적정합니다")
        val rows = candidate.stack.wheels.mapNotNull { FilterStack.resolvedRow(it, input.inventory) }
        val values = rows.joinToString("+") { NDNotationFormatter.display(it.contributionStops, NDNotationMode.STOPS).value }
        val names = rows.joinToString(" + ") { it.item?.name ?: "ND ${NDNotationFormatter.display(it.contributionStops, NDNotationMode.STOPS).value}" }
        val residual = String.format(Locale.ROOT, "%+.1f", (if (kotlin.math.abs(candidate.remainingError) < 0.05) 0.0 else candidate.remainingError)).replace("-", "−") + " st"
        val warning = if (candidate.requiresSourceWarning) (if (ko) "출처 범위 밖" else "Beyond source range") else null
        val totalText = formatFilterTotalStops(candidate.stack.effectiveStops)
        val action = if (ko) "합계 $totalText 스톱 적용" else "Apply total $totalText stops"
        return TargetNDProposalDisplayState(heading, "ND $values", residual, warning,
            listOfNotNull(heading, names, (if (ko) "오차 " else "Error ") + residual, warning).joinToString(" · "), true, totalText, action)
    }
}
