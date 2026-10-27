// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.exposure.TargetNDAllowance
import com.sangwook.ptimer.core.exposure.TargetNDSettings
import kotlinx.serialization.Serializable

@Serializable
data class PersistentTargetNDSettings(
    val isEnabled: Boolean? = null,
    val negativeRaw: String? = null,
    val positiveRaw: String? = null,
    val digitalRaw: String? = null,
) {
    constructor(settings: TargetNDSettings) : this(settings.isEnabled, settings.negative.name, settings.positive.name, settings.digital.name)
    val restored: TargetNDSettings get() = TargetNDSettings(
        isEnabled ?: true, allowance(negativeRaw), allowance(positiveRaw), allowance(digitalRaw),
    )
    private fun allowance(raw: String?): TargetNDAllowance = TargetNDAllowance.entries.firstOrNull { it.name == raw } ?: TargetNDAllowance.standard
}

interface TargetNDSettingsStoring {
    fun loadSettings(): PersistentTargetNDSettings?
    fun saveSettings(settings: PersistentTargetNDSettings)
}
class NoOpTargetNDSettingsStore : TargetNDSettingsStoring {
    override fun loadSettings(): PersistentTargetNDSettings? = null
    override fun saveSettings(settings: PersistentTargetNDSettings) = Unit
}
