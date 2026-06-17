package com.sangwook.ptimer.calculator

import kotlinx.serialization.Serializable

/** Per-slot calculator/film/model/target state. Mirrors the calc-relevant
 * subset of iOS `PersistentCameraSlotCalculatorSnapshot`. */
@Serializable
data class SlotCalculatorSnapshot(
    val baseShutterSeconds: Double,
    val ndStops: Int,
    val selectedFilmId: String? = null,
    val selectedProfileId: String? = null,
    val targetShutterSeconds: Double? = null,
)
