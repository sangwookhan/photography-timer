package com.sangwook.ptimer.core.timer

/** Where a timer's exposure value originated. Mirrors iOS `ExposureTimerSource`. */
enum class ExposureTimerSource {
    DIGITAL_RESULT,
    FILM_ADJUSTED_SHUTTER,
    FILM_CORRECTED_EXPOSURE,
    TARGET_SHUTTER,
    MANUAL,
}

/**
 * Immutable identity captured once when a timer starts: the active camera
 * slot (id + label as it stood at start), the film descriptor, the
 * exposure source, the selected reciprocity-model label, and a
 * custom-profile descriptor. Frozen thereafter. Mirrors iOS
 * `ExposureTimerIdentitySnapshot`.
 *
 * A MANUAL timer captures no calculator identity.
 */
data class ExposureTimerIdentitySnapshot(
    val exposureSource: ExposureTimerSource,
    val cameraSlotId: String? = null,
    val cameraSlotLabel: String? = null,
    val filmDescriptor: String? = null,
    val selectedModelLabel: String? = null,
    val customProfileDescriptor: String? = null,
) {
    companion object {
        val MANUAL = ExposureTimerIdentitySnapshot(ExposureTimerSource.MANUAL)
    }
}
