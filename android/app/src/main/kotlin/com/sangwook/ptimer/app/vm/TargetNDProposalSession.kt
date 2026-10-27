// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.TargetNDSettings
import com.sangwook.ptimer.core.exposure.TargetNDMedium
import com.sangwook.ptimer.core.exposure.TargetNDSelection
import com.sangwook.ptimer.core.exposure.TargetNDSelectionContext
import com.sangwook.ptimer.core.exposure.TargetNDSelectionResult
import com.sangwook.ptimer.core.exposure.TargetNDSelectionFailure
import com.sangwook.ptimer.core.reciprocity.FilmColor
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile

/** Immutable input identity, including same-ID profile/inventory edits. */
data class TargetNDProposalInput(
    val cameraId: String,
    val baseSeconds: Double,
    val targetSeconds: Double,
    val profile: ReciprocityProfile?,
    val inventory: FilterInventory,
    val selectedSets: List<FilterSetId>,
    val current: FilterStack,
    val settings: TargetNDSettings,
    val medium: TargetNDMedium,
    val filmId: String? = null,
    val filmColor: FilmColor? = null,
) {
    fun evaluate(): TargetNDSelectionResult = TargetNDSelection().evaluate(baseSeconds, targetSeconds, profile, inventory, TargetNDSelectionContext(selectedSets, current, settings[medium].interval(medium)))
}

enum class TargetNDApplyFailure { expired, stale, unavailable, duplicate }
sealed interface TargetNDApplyResult {
    data class Accepted(val stack: FilterStack) : TargetNDApplyResult
    data class Rejected(val reason: TargetNDApplyFailure) : TargetNDApplyResult
}

/** Pure transient lifecycle. Platform supplies monotonic time and final commitment. */
class TargetNDProposalSession {
    enum class Phase { idle, interacting, evaluating, result, applied }
    var phase = Phase.idle; private set
    var generation = 0L; private set
    var input: TargetNDProposalInput? = null; private set
    var result: TargetNDSelectionResult? = null; private set
    var expiresAt: Double? = null; private set
    var isActionFocused = false; private set
    private var remainingLifetime = 5.0

    fun begin(input: TargetNDProposalInput): Long {
        invalidate()
        if (!input.settings.isEnabled) return generation
        this.input = input
        phase = Phase.interacting
        return generation
    }
    fun preview(input: TargetNDProposalInput) {
        if (phase == Phase.interacting && input.settings.isEnabled) this.input = input
    }
    fun settle(input: TargetNDProposalInput, filtersAreQuiet: Boolean): Long? {
        if (phase != Phase.interacting || !input.settings.isEnabled || !filtersAreQuiet) return null
        this.input = input
        phase = Phase.evaluating
        return generation
    }
    fun complete(result: TargetNDSelectionResult, input: TargetNDProposalInput, generation: Long, now: Double): Boolean {
        if (phase != Phase.evaluating || generation != this.generation || input != this.input) return false
        this.result = result
        phase = Phase.result
        remainingLifetime = if (result is TargetNDSelectionResult.Unavailable && result.reason == TargetNDSelectionFailure.NoCombination) 2.0 else 5.0
        expiresAt = now + remainingLifetime
        return true
    }
    fun invalidate() {
        generation++
        input = null
        result = null
        phase = Phase.idle
        expiresAt = null
        isActionFocused = false
        remainingLifetime = 5.0
    }
    fun expire(generation: Long, now: Double) {
        val deadline = expiresAt ?: return
        if (generation == this.generation && !isActionFocused && now >= deadline) invalidate()
    }
    fun focusAction(focused: Boolean, now: Double) {
        expire(generation, now)
        val candidate = (result as? TargetNDSelectionResult.Available)?.candidate ?: return
        if (phase != Phase.result || focused == isActionFocused || candidate.isCurrent) return
        if (focused) {
            remainingLifetime = maxOf(0.0, (expiresAt ?: now) - now)
            expiresAt = null
        } else expiresAt = now + remainingLifetime
        isActionFocused = focused
    }
    fun consume(current: TargetNDProposalInput, now: Double): TargetNDApplyResult {
        if (phase == Phase.applied) return TargetNDApplyResult.Rejected(TargetNDApplyFailure.duplicate)
        expire(generation, now)
        if (phase != Phase.result) return TargetNDApplyResult.Rejected(TargetNDApplyFailure.expired)
        if (input != current || !current.settings.isEnabled) {
            invalidate()
            return TargetNDApplyResult.Rejected(TargetNDApplyFailure.stale)
        }
        val candidate = (result as? TargetNDSelectionResult.Available)?.candidate
        if (candidate == null || candidate.isCurrent || current.evaluate() != result) {
            invalidate()
            return TargetNDApplyResult.Rejected(TargetNDApplyFailure.unavailable)
        }
        phase = Phase.applied
        result = null
        isActionFocused = false
        expiresAt = now + 1.5
        return TargetNDApplyResult.Accepted(candidate.stack)
    }
}
