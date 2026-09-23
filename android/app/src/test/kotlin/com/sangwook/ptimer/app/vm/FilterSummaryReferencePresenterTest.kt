// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * FILTER-PERSIST-003: the descriptive reference string generated once at
 * start time. Items group under their Filter Set with their registered
 * representation and mode; Standard segments carry their contribution.
 * The vocabulary is a parameter, so the same algorithm serves the start
 * capture in the user's language and the canonical-English default.
 */
class FilterSummaryReferencePresenterTest {

    private fun standard(stops: Double) = FilterSummaryEntry(
        sourceKind = FilterSummaryEntry.SourceKind.standard,
        canonicalStops = stops,
        contributedStops = stops,
    )

    private fun item(
        setName: String,
        itemName: String,
        kind: FilterItemKind,
        value: Double?,
        unit: FilterValueUnit?,
        canonicalStops: Double,
        mode: FilterSummaryEntry.CalculationMode,
        contributedStops: Double,
    ) = FilterSummaryEntry(
        sourceKind = FilterSummaryEntry.SourceKind.filterSet,
        filterSetId = setName,
        filterSetName = setName,
        itemId = itemName,
        itemName = itemName,
        itemKind = kind,
        originalValue = value,
        originalUnit = unit,
        canonicalStops = canonicalStops,
        calculationMode = mode,
        contributedStops = contributedStops,
    )

    @Test
    fun groupsItemsBySetWithRepresentationAndMode() {
        val summary = listOf(
            standard(2.0),
            item("Lee holder", "Big Stopper", FilterItemKind.fixed, 1000.0, FilterValueUnit.filterFactor, 10.0, FilterSummaryEntry.CalculationMode.fixed, 10.0),
            item("Lee holder", "Lee GND 0.9", FilterItemKind.gnd, 0.9, FilterValueUnit.opticalDensity, 3.0, FilterSummaryEntry.CalculationMode.gndRecordOnly, 0.0),
            item("NiSi kit", "NiSi CPL", FilterItemKind.cpl, null, null, 1.5, FilterSummaryEntry.CalculationMode.cplLoss, 1.5),
        )
        assertEquals(
            "Standard 2 stops · Lee holder: Big Stopper ND1000 + Lee GND 0.9 OD 0.9 (Record only) · " +
                "NiSi kit: NiSi CPL 1.5 stops",
            FilterSummaryReferencePresenter.referenceText(summary),
        )
    }

    @Test
    fun applyFullValueIsNamedAndAStandardZeroIsOmitted() {
        val summary = listOf(
            standard(0.0),
            item("Lee holder", "Lee GND 0.9", FilterItemKind.gnd, 0.9, FilterValueUnit.opticalDensity, 3.0, FilterSummaryEntry.CalculationMode.gndApplyFullValue, 3.0),
        )
        assertEquals(
            "Lee holder: Lee GND 0.9 OD 0.9 (Apply full value)",
            FilterSummaryReferencePresenter.referenceText(summary),
        )
    }

    @Test
    fun aStandardOnlyZeroStackHasNoReferenceText() {
        assertNull(FilterSummaryReferencePresenter.referenceText(listOf(standard(0.0))))
        assertNull(FilterSummaryReferencePresenter.referenceText(emptyList()))
    }

    @Test
    fun interleavedSourcesFlushEachGroupInStackOrder() {
        val summary = listOf(
            item("Lee holder", "A", FilterItemKind.fixed, 3.0, FilterValueUnit.stops, 3.0, FilterSummaryEntry.CalculationMode.fixed, 3.0),
            standard(1.0),
            item("Lee holder", "B", FilterItemKind.fixed, 2.0, FilterValueUnit.stops, 2.0, FilterSummaryEntry.CalculationMode.fixed, 2.0),
        )
        assertEquals(
            "Lee holder: A 3 stops · Standard 1 stop · Lee holder: B 2 stops",
            FilterSummaryReferencePresenter.referenceText(summary),
        )
    }

    @Test
    fun theSuppliedVocabularyIsTheOneWritten() {
        val korean = FilterReferenceVocabulary.canonicalEnglish.copy(
            standardSource = "표준",
            oneStop = "1 스톱",
            stopsFormat = "%1\u0024s 스톱",
            recordOnlyMode = "기록만",
        )
        val summary = listOf(
            standard(2.0),
            item("Lee holder", "Big Stopper", FilterItemKind.gnd, 0.9, FilterValueUnit.opticalDensity, 3.0, FilterSummaryEntry.CalculationMode.gndRecordOnly, 0.0),
        )
        assertEquals(
            "표준 2 스톱 · Lee holder: Big Stopper OD 0.9 (기록만)",
            FilterSummaryReferencePresenter.referenceText(summary, korean),
        )
        assertEquals(
            "The English default is unaffected by the call above.",
            "Standard 2 stops · Lee holder: Big Stopper OD 0.9 (Record only)",
            FilterSummaryReferencePresenter.referenceText(summary),
        )
    }

    @Test
    fun missingNamesFallBackToTheSuppliedFallbackTokens() {
        val summary = listOf(
            FilterSummaryEntry(
                sourceKind = FilterSummaryEntry.SourceKind.filterSet,
                canonicalStops = 4.0,
                calculationMode = FilterSummaryEntry.CalculationMode.fixed,
                contributedStops = 4.0,
            ),
        )
        assertEquals("Filter Set: Filter 4 stops", FilterSummaryReferencePresenter.referenceText(summary))
        assertEquals(
            "필터 세트: 필터 4 stops",
            FilterSummaryReferencePresenter.referenceText(
                summary,
                FilterReferenceVocabulary.canonicalEnglish.copy(
                    fallbackFilterSet = "필터 세트",
                    fallbackItem = "필터",
                ),
            ),
        )
    }
}
