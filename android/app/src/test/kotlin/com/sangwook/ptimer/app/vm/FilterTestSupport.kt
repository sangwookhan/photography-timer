// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter

/**
 * Applies [mounts] as the complete auxiliary selection through the
 * production Apply (FILTER-AUX-003), keeping the selected Filter Sets and
 * adding the sets the mounts come from.
 */
internal fun CalculatorController.applyMounts(mounts: List<MountedAuxiliaryFilter>): FilterStackRejection? {
    val selected = state.value.candidateFilterSetIds.toMutableList()
    mounts.map { it.filterSetId }.forEach { if (it !in selected) selected += it }
    return applyShootingFilters(selected, mounts)
}
