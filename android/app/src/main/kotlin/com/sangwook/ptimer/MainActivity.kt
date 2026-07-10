// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.runtime.produceState
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.sangwook.ptimer.app.notify.TimerNotifications
import com.sangwook.ptimer.app.ui.ShootingApp
import com.sangwook.ptimer.app.ui.ShootingAppBootstrap
import com.sangwook.ptimer.ui.component.DebugBuildRibbon
import com.sangwook.ptimer.ui.theme.PTimerTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

// Brief branded splash shown on cold start (PTIMER-202); the platform's own
// splash-screen API is icon-only and cannot show the full illustration. The
// splash ends only once BOTH this minimum has elapsed AND the app bootstrap
// (catalog parse + initial store reads, on IO) has finished (PTIMER-217), so
// the main UI never composes against incomplete state.
private const val SPLASH_DURATION_MS = 300L

// The DEBUG marker auto-hides so it doesn't linger over screenshots taken
// later in the session (PTIMER-203).
private const val DEBUG_RIBBON_DURATION_MS = 10_000L

class MainActivity : ComponentActivity() {
    // Incremented each time the app is opened from a timer notification so the
    // shell opens the (expanded) timer list. A counter, not a flag, so a repeat
    // tap while the activity is already running still triggers via onNewIntent.
    private val openTimersSignal = mutableIntStateOf(0)
    // The timer id carried by a tapped completion notification, so the shell can
    // focus that finished timer in the list. Read alongside each show-timers tap.
    private val focusTimerId = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        consumeShowTimers(intent)
        setContent {
            // Dark theme only (product decision), dynamic color off to match the
            // iOS dark reference captures.
            PTimerTheme(darkTheme = true, dynamicColor = false) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    // App bootstrap (catalog parse + every initial store read) on
                    // IO, concurrent with the splash minimum (PTIMER-217). On
                    // config-change recreation it re-runs like the old in-
                    // composition reads did, but warm (catalog lazy already
                    // parsed, DataStore caches hot), so the gap is a few ms.
                    val bootstrap by produceState<ShootingAppBootstrap?>(initialValue = null) {
                        value = withContext(Dispatchers.IO) {
                            ShootingAppBootstrap.load(applicationContext)
                        }
                    }
                    // rememberSaveable (not remember): onCreate reruns on every
                    // config-change recreation (rotation, dark/light toggle, font
                    // scale). remember would replay the splash minimum on top of
                    // running app state each time; the saved value survives
                    // recreation so the 300 ms floor applies once per process.
                    var splashMinimumShown by rememberSaveable { mutableStateOf(false) }
                    LaunchedEffect(Unit) {
                        delay(SPLASH_DURATION_MS)
                        splashMinimumShown = true
                    }

                    Box(Modifier.fillMaxSize()) {
                        val readyBootstrap = bootstrap
                        if (!splashMinimumShown || readyBootstrap == null) {
                            Image(
                                painter = painterResource(R.drawable.splash_illustration),
                                contentDescription = null,
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Crop,
                            )
                        } else {
                            ShootingApp(
                                bootstrap = readyBootstrap,
                                openTimersSignal = openTimersSignal.intValue,
                                notificationFocusTimerId = focusTimerId.value,
                            )
                        }
                        if (BuildConfig.DEBUG) {
                            var showDebugRibbon by rememberSaveable { mutableStateOf(true) }
                            LaunchedEffect(Unit) {
                                delay(DEBUG_RIBBON_DURATION_MS)
                                showDebugRibbon = false
                            }
                            if (showDebugRibbon) {
                                DebugBuildRibbon(modifier = Modifier.align(Alignment.TopEnd))
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeShowTimers(intent)
    }

    private fun consumeShowTimers(intent: Intent?) {
        if (intent?.getBooleanExtra(TimerNotifications.EXTRA_SHOW_TIMERS, false) == true) {
            focusTimerId.value = intent.getStringExtra(TimerNotifications.EXTRA_FOCUS_TIMER_ID)
            openTimersSignal.intValue++
        }
    }
}
