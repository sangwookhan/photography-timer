// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.notify

import android.content.ContextWrapper
import android.media.AudioAttributes
import android.media.MediaPlayer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * PTIMER-216: concrete alarm-player contracts through the [AlarmToneEngine] /
 * [AlarmAutoStopScheduler] seams — no real MediaPlayer playback involved.
 */
class AndroidTimerAlarmPlayerTest {

    private class FakeEngine(private val startSucceeds: Boolean = true) : AlarmToneEngine {
        var startCount = 0
        var stopCount = 0

        /** Ordered "start"/"stop" event log, to check no two starts are adjacent. */
        val events = mutableListOf<String>()

        override fun start(): Boolean {
            startCount++
            events.add("start")
            return startSucceeds
        }

        override fun stop() {
            stopCount++
            events.add("stop")
        }
    }

    /** Records the scheduled delay and lets the test fire the callback manually. */
    private class FakeScheduler : AlarmAutoStopScheduler {
        var scheduledDelayMillis: Long? = null
        var cancelCount = 0
        private var pendingFire: (() -> Unit)? = null

        override fun schedule(delayMillis: Long, onFire: () -> Unit) {
            scheduledDelayMillis = delayMillis
            pendingFire = onFire
        }

        override fun cancel() {
            cancelCount++
            pendingFire = null
        }

        fun fire() = pendingFire?.invoke()
    }

    /** Records the [AlarmStreamTarget]s it was asked to apply; touches no real android.media API. */
    private class FakeAudioAttributesApplication : AlarmAudioAttributesApplication {
        val appliedTargets = mutableListOf<AlarmStreamTarget>()

        override fun applyTo(mediaPlayer: MediaPlayer, target: AlarmStreamTarget) {
            appliedTargets.add(target)
        }
    }

    @Test
    fun alarmTargetsTheAlarmStreamWithSonificationContentType() {
        // Pins the stream-targeting contract (PTIMER-73): alarm usage so
        // playback survives silent/vibrate mode.
        assertEquals(AudioAttributes.USAGE_ALARM, AlarmStreamTarget.DEFAULT.usage)
        assertEquals(AudioAttributes.CONTENT_TYPE_SONIFICATION, AlarmStreamTarget.DEFAULT.contentType)
    }

    @Test
    fun concretePlaybackPathAppliesTheAlarmStreamTargetToTheMediaPlayer() {
        // The check above pins AlarmStreamTarget.DEFAULT's values in
        // isolation; this proves MediaPlayerAlarmToneEngine's concrete
        // player-creation step actually threads that same target into the
        // audio-attribute application call. If a future change stopped
        // applying USAGE_ALARM/CONTENT_TYPE_SONIFICATION here (e.g. bypassed
        // audioAttributesApplication or passed a different target),
        // appliedTargets would come back empty or wrong and this would fail.
        val fakeApplication = FakeAudioAttributesApplication()
        val engine = MediaPlayerAlarmToneEngine(
            context = ContextWrapper(null),
            audioAttributesApplication = fakeApplication,
        )

        engine.createConfiguredPlayer()

        assertEquals(listOf(AlarmStreamTarget.DEFAULT), fakeApplication.appliedTargets)
    }

    @Test
    fun playAlarmStartsTheEngineAndPublishesTheSoundingTimerId() {
        val engine = FakeEngine()
        val scheduler = FakeScheduler()
        val player = AndroidTimerAlarmPlayer(engine, scheduler)
        val id = UUID.randomUUID()

        player.playAlarm(id)

        assertEquals(1, engine.startCount)
        assertEquals(id, player.soundingTimerId.value)
    }

    @Test
    fun boundedAutoStopIsScheduledAtConstructionMaxDurationAndFiringItStopsAndClearsSoundingState() {
        val engine = FakeEngine()
        val scheduler = FakeScheduler()
        val player = AndroidTimerAlarmPlayer(engine, scheduler, maxDurationMillis = 8_000L)

        player.playAlarm(UUID.randomUUID())
        assertEquals(8_000L, scheduler.scheduledDelayMillis)

        scheduler.fire()

        // One stop from playAlarm's own defensive stop-before-start, one from
        // the auto-stop firing.
        assertEquals(2, engine.stopCount)
        assertNull(player.soundingTimerId.value)
    }

    @Test
    fun explicitStopCancelsThePendingAutoStopAndClearsSoundingState() {
        val engine = FakeEngine()
        val scheduler = FakeScheduler()
        val player = AndroidTimerAlarmPlayer(engine, scheduler)
        player.playAlarm(UUID.randomUUID())

        player.stop()

        // One cancel/stop from playAlarm's own defensive stop-before-start, one
        // from the explicit stop() call.
        assertEquals(2, scheduler.cancelCount)
        assertEquals(2, engine.stopCount)
        assertNull(player.soundingTimerId.value)
    }

    @Test
    fun startingANewAlarmStopsThePreviousOneFirstSoAtMostOneSoundsAtOnce() {
        val engine = FakeEngine()
        val scheduler = FakeScheduler()
        val player = AndroidTimerAlarmPlayer(engine, scheduler)
        val first = UUID.randomUUID()
        val second = UUID.randomUUID()

        player.playAlarm(first)
        player.playAlarm(second)

        // Never two starts back-to-back without an intervening stop — every
        // "start" event in the log is immediately preceded by a "stop".
        val starts = engine.events.withIndex().filter { it.value == "start" }
        assertTrue(starts.all { (index, _) -> index > 0 && engine.events[index - 1] == "stop" })
        assertEquals(2, engine.startCount)
        assertEquals(second, player.soundingTimerId.value)
    }

    @Test
    fun engineFailureToStartLeavesNoSoundingTimerAndSchedulesNoAutoStop() {
        val engine = FakeEngine(startSucceeds = false)
        val scheduler = FakeScheduler()
        val player = AndroidTimerAlarmPlayer(engine, scheduler)

        player.playAlarm(UUID.randomUUID())

        assertNull(player.soundingTimerId.value)
        assertNull(scheduler.scheduledDelayMillis)
    }

    @Test
    fun stoppingWithNothingSoundingIsSafe() {
        val engine = FakeEngine()
        val scheduler = FakeScheduler()
        val player = AndroidTimerAlarmPlayer(engine, scheduler)

        player.stop()

        assertTrue(engine.stopCount >= 1)
        assertNull(player.soundingTimerId.value)
    }
}
