// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import com.sangwook.ptimer.app.notify.TimerNotifications
import com.sangwook.ptimer.app.ui.ShootingApp
import com.sangwook.ptimer.ui.theme.PTimerTheme

class MainActivity : ComponentActivity() {
    // Incremented each time the app is opened from a timer notification so the
    // shell opens the (expanded) timer list. A counter, not a flag, so a repeat
    // tap while the activity is already running still triggers via onNewIntent.
    private val openTimersSignal = mutableIntStateOf(0)
    // The timer id carried by a tapped completion notification, so the shell can
    // focus that finished timer in the list. Read alongside each show-timers tap.
    private val focusTimerId = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
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
                    ShootingApp(
                        openTimersSignal = openTimersSignal.intValue,
                        notificationFocusTimerId = focusTimerId.value,
                    )
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
