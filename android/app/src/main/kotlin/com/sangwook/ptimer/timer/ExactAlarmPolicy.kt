package com.sangwook.ptimer.timer

/** How a completion alarm is delivered when exact scheduling is not used. */
enum class FallbackMode { NONE, INEXACT }

/**
 * Pure decision for completion-alarm exactness and the in-app permission
 * prompt — no Android dependencies, so it is unit-testable on the JVM.
 */
data class ExactAlarmDecision(
    val shouldUseExact: Boolean,
    val shouldShowPermissionPrompt: Boolean,
    val fallbackMode: FallbackMode,
)

object ExactAlarmPolicy {
    /** Android 12 (S). Exact alarms require permission at and above this level. */
    const val API_EXACT_RESTRICTED = 31

    /**
     * @param sdkInt           Build.VERSION.SDK_INT
     * @param canScheduleExact AlarmManager.canScheduleExactAlarms() (only meaningful on API 31+)
     * @param promptDismissed  whether the user already dismissed the in-app prompt this session
     *
     * Below API 31 exact alarms need no permission, so exact is always used and
     * no prompt is shown. On API 31+ exact is used only when permitted; when not
     * permitted we fall back to a best-effort inexact alarm and offer the prompt
     * once (until dismissed).
     */
    fun decide(sdkInt: Int, canScheduleExact: Boolean, promptDismissed: Boolean): ExactAlarmDecision = when {
        sdkInt < API_EXACT_RESTRICTED -> ExactAlarmDecision(true, false, FallbackMode.NONE)
        canScheduleExact -> ExactAlarmDecision(true, false, FallbackMode.NONE)
        else -> ExactAlarmDecision(false, !promptDismissed, FallbackMode.INEXACT)
    }
}
