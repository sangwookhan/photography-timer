// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager

/**
 * Plays a short, attention-grabbing timer alarm directly on the alarm stream
 * (PTIMER-73). Going through `USAGE_ALARM` rather than a notification-channel
 * sound means the tone is loud in vibrate mode and bypasses Do-Not-Disturb —
 * the behaviour field shooting needs when the phone is in a pocket or on a
 * tripod.
 */
interface TimerAlarmPlayer {
    fun playAlarm(context: Context)
    fun stop()
}

/**
 * Process-wide [MediaPlayer]-backed implementation. The player is held in a
 * single slot (so it is not garbage-collected mid-playback) and releases itself
 * on completion/error, so playback is one-shot and self-cleaning — there is no
 * looping alarm to leave running. The AlarmManager schedule is the lifecycle
 * owner: cancel/remove cancels the pending alarm before it fires, so a stale
 * alarm never plays; [stop] is available for an in-flight tone.
 */
object AndroidTimerAlarmPlayer : TimerAlarmPlayer {
    private var player: MediaPlayer? = null

    override fun playAlarm(context: Context) {
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
            mediaPlayer.isLooping = false
            mediaPlayer.setOnCompletionListener { release(it) }
            mediaPlayer.setOnErrorListener { player, _, _ -> release(player); true }
            // Prepared synchronously: the source is a local content URI, and
            // starting before onReceive returns makes playback robust against
            // the receiver's process being torn down right afterwards.
            mediaPlayer.prepare()
            mediaPlayer.start()
            player = mediaPlayer
        }.onFailure { player = null }
    }

    override fun stop() {
        player?.let { mediaPlayer ->
            runCatching { if (mediaPlayer.isPlaying) mediaPlayer.stop() }
            runCatching { mediaPlayer.release() }
        }
        player = null
    }

    private fun release(mediaPlayer: MediaPlayer) {
        runCatching { mediaPlayer.release() }
        if (player === mediaPlayer) player = null
    }
}
