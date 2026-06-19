package com.sangwook.ptimer.ui

/**
 * Stable Compose `testTag`s for instrumented smoke tests. These are selectors
 * only — not user-visible and they do not change layout or behavior.
 */
object TestTags {
    const val SHOOTING_SCREEN = "ShootingScreen"
    const val RESTORING_OVERLAY = "RestoringOverlay"
    const val EXACT_ALARM_NOTICE = "ExactAlarmNotice"
    const val START_ADJUSTED_BUTTON = "StartAdjustedButton"
    const val ACTIVE_TIMER_ROW = "ActiveTimerRow"
    const val ND_PLUS_BUTTON = "NdPlusButton"
}
