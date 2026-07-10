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
 * Context-free by design (PTIMER-216): the platform Context lives only in the
 * production [AlarmToneEngine] implementation, constructed once at the
 * app/notify composition boundary — never in this collaborator's signature —
 * so the view-model band that holds a [TimerAlarmPlayer] stays JVM-pure.
 *
 * [soundingTimerId] publishes which timer's alarm is currently sounding (or
 * null), so the UI can show a stop-alarm affordance and stop it on tap.
 */
interface TimerAlarmPlayer {
    val soundingTimerId: StateFlow<UUID?>
    fun playAlarm(timerId: UUID)
    fun stop()
}

/**
 * Alarm-stream targeting for the completion alarm tone (PTIMER-73): alarm
 * usage + sonification content type, so playback survives silent/vibrate
 * mode. Held as plain data (not a built `AudioAttributes`) so the choice is
 * pinned by a JVM unit test without constructing a real `AudioAttributes`
 * off-device (PTIMER-216); [MediaPlayerAlarmToneEngine] is the only caller
 * that turns it into a real `AudioAttributes`.
 */
data class AlarmStreamTarget(val usage: Int, val contentType: Int) {
    companion object {
        val DEFAULT = AlarmStreamTarget(
            usage = AudioAttributes.USAGE_ALARM,
            contentType = AudioAttributes.CONTENT_TYPE_SONIFICATION,
        )
    }
}

/**
 * Seam around the concrete `MediaPlayer` playback [AndroidTimerAlarmPlayer]
 * drives, so its alarm-stream targeting and single-alarm invariant are
 * unit-testable without real playback (PTIMER-216).
 */
interface AlarmToneEngine {
    /** Starts looping the alarm tone on the alarm stream. Returns false if it could not start (e.g. no ringtone URI, or MediaPlayer setup failed). */
    fun start(): Boolean

    /** Stops and releases any currently playing tone; a no-op if nothing is playing. */
    fun stop()
}

/**
 * Applies an [AlarmStreamTarget] to a [MediaPlayer]'s audio attributes.
 * Seamed out of [MediaPlayerAlarmToneEngine] (PTIMER-216 review) so a JVM
 * test can prove the concrete engine actually threads
 * [AlarmStreamTarget.DEFAULT] into player configuration — not just that the
 * constant holds the right values in isolation — without constructing a
 * real `AudioAttributes` off-device (its `Builder` throws under a plain JVM
 * unit test).
 */
fun interface AlarmAudioAttributesApplication {
    fun applyTo(mediaPlayer: MediaPlayer, target: AlarmStreamTarget)
}

/** Production [AlarmAudioAttributesApplication]: the real `AudioAttributes` builder. */
object AndroidAlarmAudioAttributesApplication : AlarmAudioAttributesApplication {
    override fun applyTo(mediaPlayer: MediaPlayer, target: AlarmStreamTarget) {
        val attributes = AudioAttributes.Builder()
            .setUsage(target.usage)
            .setContentType(target.contentType)
            .build()
        mediaPlayer.setAudioAttributes(attributes)
    }
}

/** Production [AlarmToneEngine] backed by [MediaPlayer] + [RingtoneManager]. */
class MediaPlayerAlarmToneEngine(
    context: Context,
    private val target: AlarmStreamTarget = AlarmStreamTarget.DEFAULT,
    private val audioAttributesApplication: AlarmAudioAttributesApplication = AndroidAlarmAudioAttributesApplication,
) : AlarmToneEngine {
    // Lazy so constructing this engine with a test-double Context (PTIMER-216
    // review: createConfiguredPlayer is invoked directly in JVM tests) never
    // touches Context.getApplicationContext(); a real start() call resolves
    // it once, on first actual use.
    private val appContext by lazy { context.applicationContext }
    private var player: MediaPlayer? = null

    override fun start(): Boolean {
        stop()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return false
        return runCatching {
            val mediaPlayer = createConfiguredPlayer()
            mediaPlayer.setDataSource(appContext, uri)
            // Loop so it is a real alarm; the caller bounds it with an auto-stop.
            mediaPlayer.isLooping = true
            mediaPlayer.setOnErrorListener { _, _, _ -> stop(); true }
            // Prepared synchronously: the source is a local content URI, and
            // starting before the caller returns makes playback robust against
            // the receiver's process being torn down right afterwards.
            mediaPlayer.prepare()
            mediaPlayer.start()
            player = mediaPlayer
        }.onFailure { clear() }.isSuccess
    }

    /**
     * Creates a [MediaPlayer] with [target]'s alarm-stream audio attributes
     * applied via [audioAttributesApplication]. Split out from [start]
     * (PTIMER-216 review) so a JVM test can invoke it directly — without the
     * OS-only `RingtoneManager` lookup or a real `Context` — and prove the
     * alarm-stream attributes are actually threaded into the concrete
     * player, not just held as isolated [AlarmStreamTarget] data.
     */
    internal fun createConfiguredPlayer(): MediaPlayer {
        val mediaPlayer = MediaPlayer()
        audioAttributesApplication.applyTo(mediaPlayer, target)
        return mediaPlayer
    }

    override fun stop() = clear()

    private fun clear() {
        player?.let { mediaPlayer ->
            runCatching { if (mediaPlayer.isPlaying) mediaPlayer.stop() }
            runCatching { mediaPlayer.release() }
        }
        player = null
    }
}

/**
 * Schedules/cancels the single pending auto-stop callback
 * [AndroidTimerAlarmPlayer] uses to bound alarm playback, so the bounded-stop
 * contract is unit-testable without a real `Handler`/`Looper` (PTIMER-216).
 */
interface AlarmAutoStopScheduler {
    /** Replaces any pending callback with one that fires [onFire] after [delayMillis]. */
    fun schedule(delayMillis: Long, onFire: () -> Unit)

    /** Cancels any pending callback; a no-op if none is pending. */
    fun cancel()
}

/** Production [AlarmAutoStopScheduler] backed by a main-thread [Handler]. */
class HandlerAlarmAutoStopScheduler : AlarmAutoStopScheduler {
    // Lazy so merely constructing this off-device does not touch the main Looper.
    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private var pending: Runnable? = null

    override fun schedule(delayMillis: Long, onFire: () -> Unit) {
        cancel()
        val runnable = Runnable { onFire() }
        pending = runnable
        handler.postDelayed(runnable, delayMillis)
    }

    override fun cancel() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }
}

/**
 * [TimerAlarmPlayer] implementation, driven by an injected [AlarmToneEngine]
 * and [AlarmAutoStopScheduler] (PTIMER-216). It loops the alarm tone so it is
 * a real, hard-to-miss alarm, but **bounds** it with an auto-stop after
 * [maxDurationMillis] so it can never run away (the original complaint). The
 * user can also stop it early — from the in-app stop-alarm tap or anywhere
 * that calls [stop]. Starting a new alarm always stops any currently sounding
 * one first, so at most one timer's alarm sounds at a time; [soundingTimerId]
 * mirrors the active state for the UI.
 */
class AndroidTimerAlarmPlayer(
    private val engine: AlarmToneEngine,
    private val autoStop: AlarmAutoStopScheduler,
    private val maxDurationMillis: Long = MAX_ALARM_DURATION_MS,
) : TimerAlarmPlayer {
    private val _soundingTimerId = MutableStateFlow<UUID?>(null)
    override val soundingTimerId: StateFlow<UUID?> = _soundingTimerId.asStateFlow()

    override fun playAlarm(timerId: UUID) {
        stop()
        if (engine.start()) {
            _soundingTimerId.value = timerId
            autoStop.schedule(maxDurationMillis) { stop() }
        }
    }

    override fun stop() {
        autoStop.cancel()
        engine.stop()
        _soundingTimerId.value = null
    }

    companion object {
        const val MAX_ALARM_DURATION_MS = 8_000L

        // Process-wide singleton (mirrors the prior `object` instance): every
        // caller shares one player so "at most one timer's alarm sounds at a
        // time" holds across the whole app, not just per instance.
        @Volatile private var instance: AndroidTimerAlarmPlayer? = null

        /** The shared, process-wide alarm player, lazily built from [context]. */
        fun instance(context: Context): AndroidTimerAlarmPlayer =
            instance ?: synchronized(this) {
                instance ?: AndroidTimerAlarmPlayer(
                    engine = MediaPlayerAlarmToneEngine(context),
                    autoStop = HandlerAlarmAutoStopScheduler(),
                ).also { instance = it }
            }
    }
}
