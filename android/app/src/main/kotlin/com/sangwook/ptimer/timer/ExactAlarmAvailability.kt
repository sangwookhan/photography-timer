package com.sangwook.ptimer.timer

import android.app.AlarmManager
import android.content.Context
import android.os.Build

/**
 * Whether the OS currently lets this app schedule exact alarms. Abstracted so
 * the ViewModel's permission-prompt logic is JVM-testable with a fake.
 */
interface ExactAlarmAvailability {
    /** True when exact alarms can be scheduled now (always true below API 31). */
    fun canScheduleExact(): Boolean
}

/** Safe default / test stand-in: reports exact alarms as available (no prompt). */
object AlwaysExactAlarmAvailability : ExactAlarmAvailability {
    override fun canScheduleExact(): Boolean = true
}

/** Production: queries AlarmManager (with the API 31 cutoff). */
class AndroidExactAlarmAvailability(context: Context) : ExactAlarmAvailability {
    private val alarmManager = context.applicationContext.getSystemService(AlarmManager::class.java)
    override fun canScheduleExact(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager?.canScheduleExactAlarms() == true
}
