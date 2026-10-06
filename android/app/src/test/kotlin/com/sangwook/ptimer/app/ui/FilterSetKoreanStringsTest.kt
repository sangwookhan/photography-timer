// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

/**
 * L10N-015 / L10N-011: Korean Filter Set vocabulary reads 필터 세트, the
 * Color kind reads 컬러 while a Filter Set's color field stays 색상, and the
 * example Set names are not string resources, so they stay English in every
 * locale. Reads the source resource files from the module directory.
 */
class FilterSetKoreanStringsTest {

    private fun strings(dir: String): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File("src/main/res/$dir/strings.xml"))
        val nodes = document.getElementsByTagName("string")
        return (0 until nodes.length).map { nodes.item(it) as Element }.associate { it.getAttribute("name") to it.textContent }
    }

    @Test
    fun koreanFilterSetVocabularyColorKindAndExampleNames() {
        val korean = strings("values-ko")
        assertEquals(emptyMap<String, String>(), korean.filterValues { "Filter Set" in it || "필터셋" in it })
        assertEquals("필터 세트 추가", korean["filter_add_filter_set"])
        assertEquals("예시 필터 세트 추가", korean["filter_add_example_filter_sets"])
        assertEquals("컬러", korean["filter_kind_color"])
        assertEquals("색상", korean["filter_set_section_color"])
        val exampleNames = listOf("Digital Magnetic Filters", "Film Square ND/GND", "Film Color Filters")
        assertEquals(emptyList<String>(), (strings("values") + korean).values.filter { it in exampleNames })
    }
}
