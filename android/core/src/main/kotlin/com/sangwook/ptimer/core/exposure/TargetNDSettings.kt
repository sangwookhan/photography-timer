// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

/** App-global selection policy; never part of a camera snapshot. */
data class TargetNDSettings(
    val isEnabled: Boolean = true,
    val negative: TargetNDAllowance = TargetNDAllowance.standard,
    val positive: TargetNDAllowance = TargetNDAllowance.standard,
    val digital: TargetNDAllowance = TargetNDAllowance.standard,
) {
    operator fun get(medium: TargetNDMedium): TargetNDAllowance = when (medium) {
        TargetNDMedium.negative -> negative
        TargetNDMedium.positive -> positive
        TargetNDMedium.digital -> digital
    }
    fun changing(medium: TargetNDMedium, allowance: TargetNDAllowance): TargetNDSettings = when (medium) {
        TargetNDMedium.negative -> copy(negative = allowance)
        TargetNDMedium.positive -> copy(positive = allowance)
        TargetNDMedium.digital -> copy(digital = allowance)
    }
}
