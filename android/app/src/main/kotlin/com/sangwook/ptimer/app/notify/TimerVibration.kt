// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Haptic-first delivery for timer pre-alerts (PTIMER-73). pre1 is a single
 * gentle buzz ("completion approaching"); pre2 is a stronger double-buzz
 * ("finishing soon"). The completion alert keeps its own sound + system
 * vibration via the high-importance channel, so [AlertStage.MAIN] is a no-op
 * here.
 */
object TimerVibration {
    fun vibrate(context: Context, stage: AlertStage) {
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return

        val effect = when (stage) {
            AlertStage.PRE1 -> VibrationEffect.createOneShot(150, VibrationEffect.DEFAULT_AMPLITUDE)
            AlertStage.PRE2 -> VibrationEffect.createWaveform(longArrayOf(0, 250, 150, 250), -1)
            AlertStage.MAIN -> return
        }
        runCatching { vibrator.vibrate(effect) }
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
}
