package com.sangwook.ptimer.customfilm

import com.sangwook.ptimer.core.reciprocity.TableAnchor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Custom-film id sequencing must never reuse an id that still exists after a
 * delete/relaunch — deriving the next sequence from list size (the old
 * behavior) could re-mint and overwrite a persisted profile.
 */
class CustomFilmIdSequencerTest {

    @Test
    fun nextSequenceClearsTheHighestSuffixEvenWithGaps() {
        // formula-0 was deleted; only formula-1 survives (size == 1).
        assertEquals(2, CustomFilmIdSequencer.nextSequence(listOf("custom-formula-1")))
        assertEquals("custom-formula-2", CustomFilmIdSequencer.id("formula", 2))
    }

    @Test
    fun formulaAndTableShareOneMonotonicSequence() {
        assertEquals(2, CustomFilmIdSequencer.nextSequence(listOf("custom-table-1")))
        assertEquals(3, CustomFilmIdSequencer.nextSequence(listOf("custom-formula-0", "custom-table-2")))
    }

    @Test
    fun emptyLibraryStartsAtZeroAndNonMatchingIdsAreIgnored() {
        assertEquals(0, CustomFilmIdSequencer.nextSequence(emptyList()))
        assertEquals(0, CustomFilmIdSequencer.nextSequence(listOf("weird", "custom-x-5", "custom-formula-abc")))
    }

    @Test
    fun mintedIdDoesNotOverwriteAnExistingFilmAfterRestore() {
        // Restore a library that holds custom-formula-1 (formula-0 deleted).
        val existing = (CustomFilmFactory.buildFormula(
            "custom-formula-1", "Existing", 100, exponent = 1.30, noCorrectionThroughSeconds = 1.0,
        ) as CustomFilmResult.Success).film
        val lib = CustomFilmLibrary(listOf(existing))

        val seq = CustomFilmIdSequencer.nextSequence(lib.all.map { it.id })
        val newId = CustomFilmIdSequencer.id("formula", seq)
        assertEquals("custom-formula-2", newId)

        val fresh = (CustomFilmFactory.buildFormula(
            newId, "Fresh", 100, exponent = 1.40, noCorrectionThroughSeconds = 1.0,
        ) as CustomFilmResult.Success).film
        assertTrue(lib.upsert(fresh))

        assertEquals(2, lib.all.size) // original survives — not overwritten
        assertNotNull(lib.film("custom-formula-1"))
        assertEquals("Existing", lib.film("custom-formula-1")!!.canonicalStockName)
    }

    @Test
    fun tableIdsAlsoAvoidCollisionAfterRestore() {
        val table = (CustomFilmFactory.buildTable(
            "custom-table-1", "T", 100, listOf(TableAnchor(1.0, 2.0), TableAnchor(10.0, 80.0)),
        ) as CustomFilmResult.Success).film
        val lib = CustomFilmLibrary(listOf(table))
        val newId = CustomFilmIdSequencer.id("table", CustomFilmIdSequencer.nextSequence(lib.all.map { it.id }))
        assertEquals("custom-table-2", newId)
    }
}
