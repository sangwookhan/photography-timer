// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.R
import com.sangwook.ptimer.core.exposure.TargetNDSettings
import com.sangwook.ptimer.core.exposure.TargetNDAllowance
import com.sangwook.ptimer.core.exposure.TargetNDMedium

@Composable
fun TargetNDSettingsDialog(settings: TargetNDSettings, onChange: (TargetNDSettings) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.target_shutter_label)) },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.target_nd_done)) } },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.target_nd_suggest), Modifier.weight(1f))
                    Switch(checked = settings.isEnabled, onCheckedChange = { onChange(settings.copy(isEnabled = it)) })
                }
                Text(stringResource(R.string.target_nd_explanation))
                Text(stringResource(R.string.target_nd_allowance), style = MaterialTheme.typography.titleSmall)
                for (medium in TargetNDMedium.entries) {
                    Text(stringResource(when (medium) {
                        TargetNDMedium.negative -> R.string.film_negative
                        TargetNDMedium.positive -> R.string.film_positive
                        TargetNDMedium.digital -> R.string.target_nd_digital
                    }))
                    Row {
                        for (mode in TargetNDAllowance.entries) {
                            val range = when (medium) {
                                TargetNDMedium.negative -> if (mode == TargetNDAllowance.standard) "−0.5…+1" else "−0.5…+2"
                                TargetNDMedium.positive -> if (mode == TargetNDAllowance.standard) "−⅓…+⅓" else "−0.5…+0.5"
                                TargetNDMedium.digital -> if (mode == TargetNDAllowance.standard) "−1…0" else "−2…0"
                            }
                            FilterChip(
                                selected = settings[medium] == mode,
                                onClick = { onChange(settings.changing(medium, mode)) },
                                label = { Text(stringResource(if (mode == TargetNDAllowance.standard) R.string.target_nd_default else R.string.target_nd_extended) + " ($range)") },
                                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                            )
                        }
                    }
                }
                Text(stringResource(R.string.target_nd_caveat))
            }
        },
    )
}
