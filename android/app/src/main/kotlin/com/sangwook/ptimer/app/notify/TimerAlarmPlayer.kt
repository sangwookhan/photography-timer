// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/**
 * Plays an attention-grabbing timer alarm directly on the alarm stream
 * (PTIMER-73). Going through `USAGE_ALARM` rather than a notification-channel
 * sound means the tone plays on the alarm volume, so it stays audible in
 * vibrate mode — the behaviour field shooting needs when the phone is in a
 * pocket or on a tripod.
 *
 * [soundingTimerId] publishes which timer's alarm is currently sounding (or
 * null), so the UI can show a stop-alarm affordance and stop it on tap.
 */
interface TimerAlarmPlayer {
    val soundingTimerId: StateFlow<UUID?>
    fun playAlarm(context: Context, timerId: UUID)
    fun stop()
}

/**
 * Process-wide [MediaPlayer]-backed implementation. It loops the alarm tone so
 * it is a real, hard-to-miss alarm, but **bounds** it with an auto-stop after
 * [MAX_ALARM_DURATION_MS] so it can never run away (the original complaint).
 * The user can also stop it early — from the in-app stop-alarm tap or anywhere
 * that calls [stop]. The single player slot prevents GC mid-playback, and
 * [soundingTimerId] mirrors the active state for the UI.
 */
object AndroidTimerAlarmPlayer : TimerAlarmPlayer {
    private const val MAX_ALARM_DURATION_MS = 8_000L

    private var player: MediaPlayer? = null
    // Lazy so merely referencing this object (e.g. a default constructor arg)
    // off-device does not touch the main Looper.
    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private val autoStop = Runnable { stop() }
    private val _soundingTimerId = MutableStateFlow<UUID?>(null)
    override val soundingTimerId: StateFlow<UUID?> = _soundingTimerId.asStateFlow()

    override fun playAlarm(context: Context, timerId: UUID) {
        stop()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        runCatching {
            val mediaPlayer = MediaPlayer()
            mediaPlayer.setAudioAttributes(attributes)
            mediaPlayer.setDataSource(context, uri)
            // Loop so it is a real alarm; the auto-stop below bounds it.
            mediaPlayer.isLooping = true
            mediaPlayer.setOnErrorListener { _, _, _ -> stop(); true }
            // Prepared synchronously: the source is a local content URI, and
            // starting before onReceive returns makes playback robust against
            // the receiver's process being torn down right afterwards.
            mediaPlayer.prepare()
            mediaPlayer.start()
            player = mediaPlayer
            _soundingTimerId.value = timerId
            handler.removeCallbacks(autoStop)
            handler.postDelayed(autoStop, MAX_ALARM_DURATION_MS)
        }.onFailure { clear() }
    }

    override fun stop() {
        handler.removeCallbacks(autoStop)
        clear()
    }

    private fun clear() {
        player?.let { mediaPlayer ->
            runCatching { if (mediaPlayer.isPlaying) mediaPlayer.stop() }
            runCatching { mediaPlayer.release() }
        }
        player = null
        _soundingTimerId.value = null
    }
}
