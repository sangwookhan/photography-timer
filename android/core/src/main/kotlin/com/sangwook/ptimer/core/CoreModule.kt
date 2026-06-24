package com.sangwook.ptimer.core

import kotlinx.serialization.Serializable

/**
 * Marker for the pure-Kotlin core module — the Android analogue of iOS
 * PTimerCore. Real domain types (exposure, reciprocity, timer, persistence)
 * are added in later units; this exists so unit 1 can prove the module is
 * wired and free of any Android dependency.
 */
object CoreModule {
    const val NAME: String = "PTimerCore"
}

/** Smoke type proving the kotlinx.serialization plugin is active in :core. */
@Serializable
internal data class CoreModuleInfo(val name: String, val schemaVersion: Int)
