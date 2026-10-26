// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.persistence

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.sangwook.ptimer.app.vm.CustomFilmEditingPresenter
import com.sangwook.ptimer.core.customfilm.CustomFilmBuilder
import com.sangwook.ptimer.core.customfilm.CustomFilmLibrary
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.persistence.ManagedCameraListLoadResult
import com.sangwook.ptimer.core.persistence.PersistentManagedCameraList
import com.sangwook.ptimer.core.reciprocity.FilmColor
import com.sangwook.ptimer.core.reciprocity.FilmPolarity
import com.sangwook.ptimer.core.timer.TimerState
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.core.timer.status
import com.sangwook.ptimer.core.timer.remainingTime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant

/**
 * Restores anonymized Preferences payloads captured from predecessor 1.1.2
 * production stores. Keep this separate from codec-only tests: it traverses
 * the concrete DataStore adapters and the custom-film edit/save model path.
 */
class PTIMER243PredecessorRestoreTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private data class StoreHandle(
        val store: DataStore<Preferences>,
        val scope: CoroutineScope,
        val file: File,
    ) {
        fun close() = scope.cancel()
    }

    private fun newDataStore(fileName: String): StoreHandle {
        val file = File(tempFolder.root, fileName)
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        return StoreHandle(
            PreferenceDataStoreFactory.create(scope = scope, produceFile = { file }),
            scope,
            file,
        )
    }

    private fun fixturePayload(key: String): String {
        val fixture = checkNotNull(javaClass.getResource("/fixtures/PTIMER-243-android-1.1.2.fixture")).readText()
        val marker = "===== $key =====\n"
        val start = fixture.indexOf(marker)
        check(start >= 0) { "Missing fixture section: $key" }
        val contentStart = start + marker.length
        val nextSection = fixture.indexOf("\n===== ", contentStart).takeIf { it >= 0 } ?: fixture.length
        return fixture.substring(contentStart, nextSection).trim()
    }

    @Test
    fun restoresPredecessorFilmsCamerasAndTimersAndPersistsAnEditedLinkedFormula() {
        val filmsHandle = newDataStore("predecessor-films.preferences_pb")
        val camerasHandle = newDataStore("predecessor-cameras.preferences_pb")
        val timersHandle = newDataStore("predecessor-timers.preferences_pb")
        try {
            runBlocking {
                filmsHandle.store.edit {
                    it[stringPreferencesKey("custom_film_library_json")] = fixturePayload("custom_film_library_json")
                }
                camerasHandle.store.edit {
                    it[stringPreferencesKey("managed_camera_list_json")] = fixturePayload("managed_camera_list_json")
                }
                timersHandle.store.edit {
                    it[stringPreferencesKey("workspace_snapshot_json")] = fixturePayload("workspace_snapshot_json")
                }
            }

            val filmsStore = DataStoreCustomFilmLibraryStore(filmsHandle.store)
            val originalFilms = checkNotNull(filmsStore.loadSnapshot()).films
            val formulaId = "custom-film-134f9da2-6b95-4db5-a1b1-a062fa975d9a"
            val tableId = "custom-film-b195d4f0-0e4f-414b-b9e0-1cf7965722e1"
            val linkedFormulaId = "custom-film-7c08dbe5-0376-4610-8bd4-b00b1ef96488"
            val linkedProfileId = "custom-profile-87693259-30a8-463a-91da-2ecd261e3cfa"
            assertEquals(listOf(formulaId, tableId, linkedFormulaId), originalFilms.map { it.id })

            val legacyFormula = originalFilms.single { it.id == formulaId }
            assertEquals(FilmPolarity.negative, legacyFormula.polarity)
            assertEquals(FilmColor.blackAndWhite, legacyFormula.color)
            assertEquals("custom-profile-26aeed7b-23b0-4b80-92cc-67491fabe523", legacyFormula.profiles.single().id)
            assertEquals("userDefined", legacyFormula.profiles.single().source.kind.name)
            assertEquals("userDefined", legacyFormula.profiles.single().source.authority.name)
            val legacyRule = legacyFormula.profiles.single().rules.single().formula!!.formula
            assertEquals(1.0, legacyRule.coefficientSeconds, 0.0)
            assertEquals(1.0, legacyRule.referenceMeteredTimeSeconds, 0.0)
            assertEquals(1.3, legacyRule.exponent, 0.0)
            assertEquals(0.0, legacyRule.offsetSeconds, 0.0)
            assertEquals(1.0, legacyRule.noCorrectionThroughSeconds, 0.0)
            assertEquals(null, legacyRule.sourceRangeThroughSeconds)

            val legacyTable = originalFilms.single { it.id == tableId }
            assertEquals(FilmPolarity.negative, legacyTable.polarity)
            assertEquals(FilmColor.blackAndWhite, legacyTable.color)
            assertEquals("custom-profile-813f8ce5-6efe-400e-8079-b3f9c9c67411", legacyTable.profiles.single().id)
            assertEquals("userDefined", legacyTable.profiles.single().source.kind.name)
            assertEquals("userDefined", legacyTable.profiles.single().source.authority.name)
            val tableRule = legacyTable.profiles.single().rules.single().tableInterpolation!!
            assertEquals(listOf(1.0 to 2.0, 2.0 to 4.0), tableRule.anchors.map { it.meteredSeconds to it.correctedSeconds })
            assertEquals(0.1, tableRule.noCorrectionThroughSeconds, 0.0)
            assertEquals(2.0, tableRule.sourceRangeThroughSeconds, 0.0)

            val linkedFormula = originalFilms.single { it.id == linkedFormulaId }
            assertEquals(FilmPolarity.negative, linkedFormula.polarity)
            assertEquals(FilmColor.blackAndWhite, linkedFormula.color)
            val linkedProfile = linkedFormula.profiles.single()
            assertEquals(linkedProfileId, linkedProfile.id)
            assertEquals("userDefined", linkedProfile.source.kind.name)
            assertEquals("userDefined", linkedProfile.source.authority.name)
            assertEquals(tableId, linkedProfile.userMetadata!!.referenceTableFilmID)
            val linkedRule = linkedProfile.rules.single().formula!!.formula
            assertEquals(1.9999999999999998, linkedRule.coefficientSeconds, 0.0)
            assertEquals(1.0, linkedRule.referenceMeteredTimeSeconds, 0.0)
            assertEquals(1.0000000000000002, linkedRule.exponent, 0.0)
            assertEquals(0.0, linkedRule.offsetSeconds, 0.0)
            assertEquals(0.1, linkedRule.noCorrectionThroughSeconds, 0.0)
            assertEquals(2.0, linkedRule.sourceRangeThroughSeconds!!, 0.0)

            val cameraResult = DataStoreManagedCameraListStore(camerasHandle.store).load()
            assertTrue(cameraResult is ManagedCameraListLoadResult.Loaded)
            val cameraList = (cameraResult as ManagedCameraListLoadResult.Loaded).list
            assertEquals("camera1", cameraList.activeCameraId)
            val camera1 = cameraList.cameras.single { it.id == "camera1" }.calculator!!
            assertEquals(tableId, camera1.selectedFilmId)
            assertEquals("custom-profile-813f8ce5-6efe-400e-8079-b3f9c9c67411", camera1.selectedProfileId)
            val camera2 = cameraList.cameras.single { it.id == "camera2" }.calculator!!
            assertEquals(formulaId, camera2.selectedFilmId)
            assertEquals("custom-profile-26aeed7b-23b0-4b80-92cc-67491fabe523", camera2.selectedProfileId)

            val workspace = checkNotNull(DataStoreTimerWorkspaceStore(timersHandle.store).loadSnapshot())
            assertEquals(3, workspace.timers.size)
            val timerById = workspace.timers.associateBy { it.snapshot.id.toString() }
            val running = checkNotNull(timerById["b3db0385-fd10-4eed-a86a-bb1eadd8597a"])
            val paused = checkNotNull(timerById["e218f1b3-fe4e-4301-9036-1a945d9277a1"])
            val completed = checkNotNull(timerById["6870512b-b6f8-4b14-a20c-20b1f3c52306"])
            assertEquals("Camera 2 · LegacyFormula", running.identity.title)
            assertEquals("camera2", running.identity.cameraId)
            assertEquals("LegacyFormula", running.identity.filmName)
            assertEquals(20.158736798317975, running.snapshot.duration, 0.0)
            assertEquals(Instant.parse("2026-10-26T15:43:41.536615Z"), running.snapshot.startDate)
            assertEquals(Instant.parse("2026-10-26T15:44:01.695351798Z"), running.snapshot.expectedCompletionAt)
            val beforeCompletion = Instant.parse("2026-10-26T15:43:50Z")
            val runningState = running.restore(beforeCompletion).state
            assertEquals(TimerStatus.running, runningState.status)
            assertEquals(11.695351798, (runningState as TimerState.Running).remainingTime(beforeCompletion), 0.000001)
            assertEquals(TimerStatus.completed, running.restore(Instant.parse("2026-10-26T15:44:02Z")).state.status)
            assertEquals("camera2", paused.identity.cameraId)
            assertEquals("LegacyFormula", paused.identity.filmName)
            assertEquals(20.158736798317975, paused.snapshot.duration, 0.0)
            assertEquals(Instant.parse("2026-10-26T15:43:08.274243Z"), paused.snapshot.startDate)
            assertEquals(Instant.parse("2026-10-26T15:43:27.579414Z"), paused.snapshot.pausedAt)
            assertEquals(0.853565798, paused.snapshot.pausedRemainingDuration!!, 0.0)
            val pausedState = paused.restore(beforeCompletion).state
            assertEquals(TimerStatus.paused, pausedState.status)
            assertEquals(0.853565798, (pausedState as TimerState.Paused).remainingTime(beforeCompletion), 0.000001)
            assertEquals("camera2", completed.identity.cameraId)
            assertEquals("LegacyFormula", completed.identity.filmName)
            assertEquals(1.0, completed.snapshot.duration, 0.0)
            assertEquals(Instant.parse("2026-10-26T15:42:21.603906Z"), completed.snapshot.startDate)
            assertEquals(Instant.parse("2026-10-26T15:42:22.603906Z"), completed.snapshot.completedAt)
            assertEquals(TimerStatus.completed, completed.restore(beforeCompletion).state.status)

            val editDraft = CustomFilmEditingPresenter.customFilmDraft(originalFilms, linkedFormulaId)!!
            assertEquals(FilmPolarity.negative, editDraft.polarity)
            assertEquals(FilmColor.blackAndWhite, editDraft.color)
            assertEquals(listOf(1.0 to 2.0, 2.0 to 4.0), editDraft.linkedTableAnchors)
            val editedFilm = CustomFilmBuilder.buildFormulaFilm(
                CustomFormulaFilmInput(
                    filmLabel = editDraft.label,
                    profileName = linkedProfile.name,
                    iso = editDraft.iso.toInt(),
                    coefficientSeconds = editDraft.tc0.toDouble(),
                    referenceMeteredTimeSeconds = editDraft.tm0.toDouble(),
                    exponent = editDraft.exponent.toDouble(),
                    offsetSeconds = editDraft.offset.toDouble(),
                    noCorrectionThroughSeconds = editDraft.noCorrection.toDouble(),
                    sourceRangeThroughSeconds = editDraft.sourceThrough.toDouble(),
                    sourceType = editDraft.sourceType,
                    referenceUrl = editDraft.referenceUrl.ifBlank { null },
                    referenceTableFilmId = editDraft.referenceTableFilmId,
                    polarity = FilmPolarity.positive,
                    color = FilmColor.color,
                ),
                filmId = linkedFormulaId,
                profileId = linkedProfileId,
            )
            assertNotNull(editedFilm)
            val library = CustomFilmLibrary(filmsStore, originalFilms)
            library.add(checkNotNull(editedFilm))
            val savedPayload = checkNotNull(
                runBlocking { filmsHandle.store.data.first()[stringPreferencesKey("custom_film_library_json")] },
            )
            assertTrue(savedPayload.contains("\"polarity\":\"positive\""))
            assertTrue(savedPayload.contains("\"color\":\"color\""))

            filmsHandle.close()
            // DataStore has no public close API. Reopen an exact copy of the
            // saved Preferences bytes through a fresh file and DataStore instance.
            val reopenedFile = File(tempFolder.root, "reopened-films.preferences_pb")
            filmsHandle.file.copyTo(reopenedFile)
            val reopenedHandle = newDataStore("reopened-films.preferences_pb")
            try {
                val reopened = checkNotNull(DataStoreCustomFilmLibraryStore(reopenedHandle.store).loadSnapshot()).films
                assertEquals(originalFilms.map { it.id }, reopened.map { it.id })
                val savedFormula = reopened.single { it.id == linkedFormulaId }
                assertEquals(FilmPolarity.positive, savedFormula.polarity)
                assertEquals(FilmColor.color, savedFormula.color)
                assertEquals(linkedProfileId, savedFormula.profiles.single().id)
                assertEquals(linkedProfile.source, savedFormula.profiles.single().source)
                assertEquals(tableId, savedFormula.profiles.single().userMetadata!!.referenceTableFilmID)
                val savedRule = savedFormula.profiles.single().rules.single().formula!!.formula
                assertEquals(1.9999, savedRule.coefficientSeconds, 0.0001)
                assertEquals(1.0, savedRule.exponent, 0.0001)
                val savedTable = reopened.single { it.id == tableId }
                assertEquals(FilmPolarity.negative, savedTable.polarity)
                assertEquals(FilmColor.blackAndWhite, savedTable.color)
                assertEquals(listOf(1.0 to 2.0, 2.0 to 4.0), savedTable.profiles.single().rules.single().tableInterpolation!!.anchors.map { it.meteredSeconds to it.correctedSeconds })
            } finally {
                reopenedHandle.close()
            }
        } finally {
            filmsHandle.close()
            camerasHandle.close()
            timersHandle.close()
        }
    }
}
