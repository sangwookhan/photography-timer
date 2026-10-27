// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.exposure.*
import org.junit.Assert.*
import org.junit.Test
import java.util.Locale
import kotlin.math.pow

class TargetNDProposalPresenterTest {
    @Test fun liveRequiredTotalUsesTrailingStatusPlacement() {
        val input = TargetNDProposalInput("a", 1.0, 1024.0, null, FilterInventory.empty,
            emptyList(), FilterStack.single(0.0), TargetNDSettings(), TargetNDMedium.digital)
        val model = TargetNDProposalModel()
        model.begin(input)
        val en = requireNotNull(TargetNDProposalPresenter.display(model.state.value, Locale.ENGLISH))
        val ko = requireNotNull(TargetNDProposalPresenter.display(model.state.value, Locale.KOREAN))
        assertTrue(en.isLive)
        assertEquals("Required ND: 10.0 stops", en.required)
        assertEquals("필요 ND: 10.0 스톱", ko.required)
        assertFalse(en.canApply)
    }

    @Test fun noCombinationHasShortVisibleReasonAndFullDetail() {
        val input = TargetNDProposalInput("a", 1.0, 2.0.pow(31), null, FilterInventory.empty,
            emptyList(), FilterStack.single(0.0), TargetNDSettings(), TargetNDMedium.digital)
        val model = TargetNDProposalModel()
        model.begin(input); model.settle(input, true)
        val en = requireNotNull(TargetNDProposalPresenter.display(model.state.value, Locale.ENGLISH))
        val ko = requireNotNull(TargetNDProposalPresenter.display(model.state.value, Locale.KOREAN))
        assertEquals("No suitable ND combination", en.required)
        assertEquals("No ND combination within allowed error", en.fullText)
        assertEquals("적합한 ND 조합 없음", ko.required)
        assertTrue(en.isNoCombination)
        assertFalse(en.canApply)
    }
    @Test fun realAuxiliaryPhysicalCombinationKeepsFullNamesAndCompactNumericWarning() {
        val nd = listOf(6.0, 3.0, 2.0).map { FilterItem("Long physical landscape filter $it stops", FilterItemBehavior.Fixed(FilterRegisteredValue(it, FilterValueUnit.stops))) }
        val cpl = FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
        val set = FilterSet("Kit", FilterSetColor.purple, nd + cpl)
        val inventory = FilterInventory(listOf(set))
        val mounts = listOf(MountedAuxiliaryFilter(set.id, cpl.id, AuxiliaryFilterChoice.CplLoss(1.5)))
        val current = requireNotNull(FilterStack.validated(listOf(FilterWheel.standard(0.0)), mounts, inventory))
        val profile = LaunchPresetFilmCatalogV2.films.first { it.id == "fujifilm-acros-ii" }.profiles.first()
        val input = TargetNDProposalInput("a", 1.0, 8192.0, profile, inventory, listOf(set.id), current, TargetNDSettings(), TargetNDMedium.negative)
        val model = TargetNDProposalModel()
        model.begin(input); model.settle(input, true)
        val display = requireNotNull(TargetNDProposalPresenter.display(model.state.value, Locale.ENGLISH))
        assertEquals("Required ND: 12.5 stops", display.required)
        assertEquals("ND 6+3+2", display.combination)
        assertEquals("+0.0 st", display.residual)
        assertEquals("Beyond source range", display.warning)
        assertEquals("12.5", display.candidateTotalText)
        assertEquals("Apply total 12.5 stops", display.action)
        assertEquals("합계 12.5 스톱 적용", TargetNDProposalPresenter.display(model.state.value, Locale.KOREAN)?.action)
        assertTrue(display.fullText.contains(nd.first().name))
        assertTrue(display.canApply)
        assertEquals("출처 범위 밖", TargetNDProposalPresenter.display(model.state.value, Locale.KOREAN)?.warning)
    }

    @Test fun oldAccessibilityFocusCallbackDoesNotSuspendNewOffer() {
        val input = TargetNDProposalInput("a", 1.0, 1024.0, null, FilterInventory.empty, emptyList(), FilterStack.single(0.0), TargetNDSettings(), TargetNDMedium.digital)
        val model = TargetNDProposalModel()
        model.begin(input); model.settle(input, true)
        val old = model.state.value.generation
        model.begin(input); model.settle(input, true)
        model.focusAction(true, old)
        assertFalse(model.state.value.isActionFocused)
    }
}
