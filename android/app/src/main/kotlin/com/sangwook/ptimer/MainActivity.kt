// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.sangwook.ptimer.ui.spike.WheelSpikeHarness
import com.sangwook.ptimer.ui.theme.PTimerTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            // Unit-2.5 spike: the app entry temporarily hosts the SnapWheel
            // validation harness. The real shooting shell replaces this in
            // unit 6. Dark theme only (product decision), dynamic color off
            // so the harness matches the iOS dark reference captures.
            PTimerTheme(darkTheme = true, dynamicColor = false) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    WheelSpikeHarness()
                }
            }
        }
    }
}
