// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.RequiredNDEvaluator
import com.sangwook.ptimer.core.exposure.RequiredNDResult
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile

/** Transient presentation only; never serialized with shooting inputs. */
data class RequiredNDGuidanceState(
    val result: RequiredNDResult? = null,
    val phase: Phase = Phase.Ordinary,
    val generation: Int = 0,
) {
    enum class Phase { Ordinary, Tracking, Crossfading }
}

class RequiredNDGuidanceModel {
    var state = RequiredNDGuidanceState()
        private set
    private var target = 0.0
    private var profile: ReciprocityProfile? = null

    fun begin(base: Double, target: Double, profile: ReciprocityProfile?) {
        invalidate()
        this.target = target
        this.profile = profile
        state = state.copy(phase = RequiredNDGuidanceState.Phase.Tracking)
        update(base)
    }

    fun update(base: Double) {
        if (state.phase == RequiredNDGuidanceState.Phase.Tracking)
            state = state.copy(result = RequiredNDEvaluator().evaluate(base, target, profile))
    }

    fun settle(base: Double) {
        if (state.phase != RequiredNDGuidanceState.Phase.Tracking) return
        update(base)
        state = state.copy(phase = RequiredNDGuidanceState.Phase.Crossfading)
    }

    fun complete(token: Int) {
        if (token == state.generation && state.phase == RequiredNDGuidanceState.Phase.Crossfading)
            state = state.copy(result = null, phase = RequiredNDGuidanceState.Phase.Ordinary)
    }

    fun invalidate() {
        target = 0.0
        profile = null
        state = RequiredNDGuidanceState(generation = state.generation + 1)
    }
}
