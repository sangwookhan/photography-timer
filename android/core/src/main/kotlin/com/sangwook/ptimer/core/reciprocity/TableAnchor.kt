package com.sangwook.ptimer.core.reciprocity

import kotlinx.serialization.Serializable

/** A published metered→corrected reciprocity point. Mirrors iOS `TableAnchor`. */
@Serializable
data class TableAnchor(
    val meteredSeconds: Double,
    val correctedSeconds: Double,
)
