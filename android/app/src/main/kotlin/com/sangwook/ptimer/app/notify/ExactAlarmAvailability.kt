// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Exact-alarm capability seam (Android-only). Wraps the OS rules so the
 * scheduler and UI can ask whether exact alarms are gated on this OS version,
 * whether they are currently permitted, and can open the system "Alarms &
 * reminders" settings to request them. Interface-backed so [ExactAlarmPolicy]
 * is unit-testable with a fake.
 */
interface ExactAlarmAvailability {
    /** True when this OS version gates exact alarms behind a user permission (API 31+). */
    val isPermissionGated: Boolean

    /** True when the app may currently schedule exact alarms. */
    fun isAllowed(): Boolean

    /** Opens the system exact-alarm settings for this app (no-op when not gated). */
    fun openSettings()
}

/** Production [ExactAlarmAvailability] backed by [AlarmManager] + system settings. */
class AndroidExactAlarmAvailability(private val context: Context) : ExactAlarmAvailability {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    override val isPermissionGated: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    override fun isAllowed(): Boolean =
        !isPermissionGated || alarmManager.canScheduleExactAlarms()

    override fun openSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }
}
