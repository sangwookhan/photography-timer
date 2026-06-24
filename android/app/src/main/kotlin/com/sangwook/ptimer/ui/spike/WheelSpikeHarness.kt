package com.sangwook.ptimer.ui.spike

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.ExposureScaleMode
import com.sangwook.ptimer.core.exposure.NDStep
import com.sangwook.ptimer.ui.component.SnapWheel

/**
 * THROWAWAY unit-2.5 validation harness for [SnapWheel]. Not shipping UI —
 * the real shooting screen arrives in unit 7. Its only job is to let us feel
 * the wheel on a device and confirm the hard requirement: the adjusted
 * shutter + exposure below must update *while the wheel is still flinging*,
 * not only when it settles. Also the place to compare ND-as-wheel vs a
 * stepper before locking the component's API.
 */
@Composable
fun WheelSpikeHarness(modifier: Modifier = Modifier) {
    val calc = remember { ExposureCalculator() }
    val shutterSteps = remember { ExposureScale.oneThirdStop.shutterSteps }
    val shutterLabels = remember { ExposureScale.oneThirdStopShutterCameraLabels }
    val ndLabels = remember { (0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS).map { it.toString() } }

    var shutterIndex by remember {
        mutableIntStateOf(shutterLabels.indexOf("1/30").coerceAtLeast(0))
    }
    var ndIndex by remember { mutableIntStateOf(0) }

    val baseSeconds = shutterSteps[shutterIndex].seconds
    val resultSeconds = calc.calculate(
        baseShutterSeconds = baseSeconds,
        ndStep = NDStep(ndIndex.toDouble()),
        scaleMode = ExposureScaleMode.ONE_THIRD_STOP,
    )

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "SnapWheel spike",
            style = MaterialTheme.typography.headlineSmall,
        )
        Text(
            text = "Adjusted shutter must update while the wheel is still spinning.",
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(24.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Base shutter", style = MaterialTheme.typography.labelMedium)
                SnapWheel(
                    labels = shutterLabels,
                    selectedIndex = shutterIndex,
                    onSelectedIndexChange = { shutterIndex = it },
                )
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("ND (stops)", style = MaterialTheme.typography.labelMedium)
                SnapWheel(
                    labels = ndLabels,
                    selectedIndex = ndIndex,
                    onSelectedIndexChange = { ndIndex = it },
                )
            }
        }

        Spacer(Modifier.height(32.dp))

        Text(
            text = calc.formatShutter(resultSeconds),
            style = MaterialTheme.typography.displaySmall,
        )
        Text(
            text = calc.formatTimeDisplay(resultSeconds).primary,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = "${shutterLabels[shutterIndex]}  ·  ${ndIndex} stops",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
