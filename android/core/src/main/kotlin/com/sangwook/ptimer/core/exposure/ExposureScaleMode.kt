package com.sangwook.ptimer.core.exposure

/**
 * Granularity of one increment along an exposure scale. `ONE_THIRD_STOP`
 * is a first-class step (the shipping shutter ladder), not a display-only
 * choice. `FULL_STOP` is reserved for tests and a future Settings
 * preference. Mirrors iOS `ExposureScaleMode`.
 */
enum class ExposureScaleMode {
    FULL_STOP,
    ONE_THIRD_STOP;

    /** Stops covered by one step on this scale. */
    val stopsPerStep: Double
        get() = when (this) {
            FULL_STOP -> 1.0
            ONE_THIRD_STOP -> 1.0 / 3.0
        }
}
