// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.TargetNDSelectionResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Retained transient owner. Injected monotonic time and scheduler allow real
 * cancellation/old-timeout races to be tested without wall-clock waits. */
class TargetNDProposalModel(
    private val now: () -> Double = { System.nanoTime() / 1_000_000_000.0 },
    private val schedule: ((Double, () -> Unit) -> (() -> Unit))? = null,
    private val evaluate: (TargetNDProposalInput, (TargetNDSelectionResult) -> Unit) -> (() -> Unit) = { input, complete -> complete(input.evaluate()); {} },
) {
    private val session = TargetNDProposalSession()
    data class State(val phase: TargetNDProposalSession.Phase, val input: TargetNDProposalInput?,
                     val result: TargetNDSelectionResult?, val generation: Long, val isActionFocused: Boolean)
    private fun snapshot() = State(session.phase, session.input, session.result, session.generation, session.isActionFocused)
    private val mutable = MutableStateFlow(snapshot())
    val state = mutable.asStateFlow()
    private var context: TargetNDProposalInput? = null
    private var cancelEvaluation: (() -> Unit)? = null
    private var cancelExpiry: (() -> Unit)? = null

    fun begin(input: TargetNDProposalInput?) {
        invalidate()
        if (input == null) return
        context = input
        session.begin(input)
        publish()
    }
    fun preview(input: TargetNDProposalInput?) {
        val old = context ?: return
        if (input == null || old.copy(baseSeconds = input.baseSeconds) != input) { invalidate(); return }
        context = input
        session.preview(input)
        publish()
    }
    fun reconcile(input: TargetNDProposalInput?) { if (context != input) invalidate() }
    fun settle(input: TargetNDProposalInput?, quiet: Boolean) {
        val old = context
        if (input == null || old?.copy(baseSeconds = input.baseSeconds) != input) { invalidate(); return }
        context = input
        val token = session.settle(input, quiet) ?: run { invalidate(); return }
        publish()
        cancelEvaluation = evaluate(input) { result ->
            if (context == input && session.complete(result, input, token, now())) { publish(); scheduleExpiry() }
        }
    }
    fun focusAction(focused: Boolean, generation: Long = session.generation) { if (generation != session.generation) return; session.focusAction(focused, now()); publish(); scheduleExpiry() }
    fun apply(input: TargetNDProposalInput?, quiet: Boolean,
              commit: (TargetNDProposalInput, TargetNDSelectionResult) -> TargetNDApplyFailure?): TargetNDApplyFailure? {
        if (input == null || !quiet) { invalidate(); return TargetNDApplyFailure.stale }
        val result = session.result
        val consumed = session.consume(input, now())
        if (consumed is TargetNDApplyResult.Rejected) { publish(); return consumed.reason }
        val failure = if (result == null) TargetNDApplyFailure.unavailable else commit(input, result)
        if (failure != null) invalidate() else { publish(); scheduleExpiry() }
        return failure
    }
    fun invalidate() {
        cancelEvaluation?.invoke(); cancelEvaluation = null
        cancelExpiry?.invoke(); cancelExpiry = null
        context = null
        session.invalidate()
        publish()
    }
    private fun publish() { mutable.value = snapshot() }
    private fun scheduleExpiry() {
        cancelExpiry?.invoke(); cancelExpiry = null
        val deadline = session.expiresAt ?: return
        val token = session.generation
        cancelExpiry = schedule?.invoke(maxOf(0.0, deadline - now())) expiry@ {
            if (token != session.generation) return@expiry
            session.expire(token, now()); publish()
            // An early wake-up must not strand an offer indefinitely.
            if (session.expiresAt != null && !session.isActionFocused) scheduleExpiry()
        }
    }
    companion object {
        fun inScope(scope: CoroutineScope?, now: () -> Double = { System.nanoTime() / 1_000_000_000.0 }): TargetNDProposalModel =
            TargetNDProposalModel(now, schedule = { seconds, action ->
                val job: Job? = scope?.launch { delay(kotlin.math.ceil(seconds * 1000).toLong()); action() }
                val cancel: () -> Unit = { job?.cancel(); Unit }
                cancel
            }, evaluate = { input, complete ->
                if (scope == null) { complete(input.evaluate()); {} }
                else {
                    val job = scope.launch {
                        val result = withContext(Dispatchers.Default) { input.evaluate() }
                        complete(result)
                    }
                    val cancel: () -> Unit = { job.cancel() }
                    cancel
                }
            })
    }
}
