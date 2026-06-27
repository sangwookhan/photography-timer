package com.sangwook.ptimer.app.notify

/** How a completion alarm is scheduled: exactly, or as an inexact fallback. */
enum class AlarmScheduling { EXACT, INEXACT }

/**
 * Pure exact-alarm decisions over an [ExactAlarmAvailability]: schedule exactly
 * when permitted, otherwise fall back to inexact; surface the user warning only
 * when the OS gates the permission and it is currently denied (never on OS
 * versions where exact alarms need no permission).
 */
object ExactAlarmPolicy {
    fun scheduling(availability: ExactAlarmAvailability): AlarmScheduling =
        if (availability.isAllowed()) AlarmScheduling.EXACT else AlarmScheduling.INEXACT

    fun shouldWarn(availability: ExactAlarmAvailability): Boolean =
        availability.isPermissionGated && !availability.isAllowed()
}
