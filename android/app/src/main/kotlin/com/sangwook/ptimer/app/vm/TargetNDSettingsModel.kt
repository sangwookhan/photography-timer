// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.core.exposure.TargetNDSettings
import com.sangwook.ptimer.core.persistence.PersistentTargetNDSettings
import com.sangwook.ptimer.core.persistence.TargetNDSettingsStoring
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Retained with the app owner across camera changes and Activity recreation. */
class TargetNDSettingsModel(initial: TargetNDSettings, private val store: TargetNDSettingsStoring, private val writer: PersistenceWriter) {
    private val mutable = MutableStateFlow(initial)
    val settings: StateFlow<TargetNDSettings> = mutable.asStateFlow()
    fun update(settings: TargetNDSettings) {
        if (settings == mutable.value) return
        mutable.value = settings
        val snapshot = PersistentTargetNDSettings(settings)
        writer.submit { store.saveSettings(snapshot) }
    }
}
