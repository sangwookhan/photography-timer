// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import org.junit.Assert.assertEquals
import org.junit.Test

/** FILTER-SET-001: the three exit paths of the name field agree. */
class FilterSetRenameCommitTest {

    @Test
    fun aDeletedSetIsANoOp() {
        assertEquals(FilterSetRenameCommit.None, FilterSetRenameCommit.decide("Anything", null))
    }

    @Test
    fun aBlankDraftRestoresTheCurrentName() {
        assertEquals(
            FilterSetRenameCommit.Restore("NiSi kit"),
            FilterSetRenameCommit.decide("   ", "NiSi kit"),
        )
    }

    @Test
    fun anUnchangedDraftDoesNothingEvenWithSurroundingWhitespace() {
        assertEquals(FilterSetRenameCommit.None, FilterSetRenameCommit.decide("NiSi kit", "NiSi kit"))
        assertEquals(FilterSetRenameCommit.None, FilterSetRenameCommit.decide("  NiSi kit  ", "NiSi kit"))
    }

    @Test
    fun anythingElseRenamesToTheTrimmedDraft() {
        assertEquals(
            FilterSetRenameCommit.Rename("Lee holder"),
            FilterSetRenameCommit.decide("  Lee holder ", "NiSi kit"),
        )
    }
}
