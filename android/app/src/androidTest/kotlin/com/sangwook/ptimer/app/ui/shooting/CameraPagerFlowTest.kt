// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import com.sangwook.ptimer.app.persistence.OrderedPersistenceWriter
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.CameraListManager
import com.sangwook.ptimer.app.vm.FilterWheelAdjustmentOutcome
import com.sangwook.ptimer.core.persistence.CameraListPersistenceController
import com.sangwook.ptimer.core.persistence.InMemoryManagedCameraListStore
import com.sangwook.ptimer.core.persistence.ManagedCameraListLoadResult
import com.sangwook.ptimer.core.slots.CameraListSnapshot
import com.sangwook.ptimer.ui.theme.PTimerTheme
import androidx.compose.ui.graphics.asAndroidBitmap
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * The shooting pager's camera pages driven through the real calculator
 * controller, camera-list manager, and ShootingScreen (CAMERA-PAGER-004/007):
 * the utility page changes nothing, and closing management returns to where it
 * was opened from.
 */
class CameraPagerFlowTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private object ImmediateWriter : OrderedPersistenceWriter {
        override fun submit(write: () -> Unit) = write()
        override suspend fun <T> readOrdered(read: () -> T): T = read()
    }

    private var started = 0
    private lateinit var controller: CalculatorController
    private lateinit var manager: CameraListManager

    private fun showShootingScreen(storageReadFails: Boolean = false) {
        val persistence = CameraListPersistenceController(
            managedStore = InMemoryManagedCameraListStore(
                if (storageReadFails) ManagedCameraListLoadResult.ReadFailed else ManagedCameraListLoadResult.Absent,
            ),
        )
        val restored = persistence.restore()
        controller = CalculatorController(
            films = emptyList(),
            onStart = { _, _ -> started++ },
            initialCameraList = if (storageReadFails) restored.list else CameraListSnapshot.seeded { "Camera $it" },
        )
        manager = CameraListManager(controller, persistence, ImmediateWriter) { "Camera $it" }
        val actions = CameraManagementActions(
            isEditable = manager.isEditable,
            add = { runBlocking { manager.addCamera() } },
            rename = manager::renameCamera,
            setDisplayed = manager::setCameraDisplayed,
            move = manager::moveCamera,
            hide = manager::hideCameras,
            delete = manager::deleteCameras,
            activeCamera = {
                controller.state.value.slots.firstOrNull { it.isActive }?.let { controller.cameraIdentity(it.id) }
            },
        )
        composeTestRule.setContent {
            val state by controller.state.collectAsState()
            PTimerTheme {
                ShootingScreen(
                    state = state,
                    onShutterIndex = {},
                    onNdWheelActive = { _, _ -> },
                    onNdWheelValue = { _, _ -> },
                    onAddFilterWheel = {},
                    onAdjustFilterWheel = { _, _ -> FilterWheelAdjustmentOutcome.Boundary },
                    onRemoveNdWheelOverscroll = {},
                    onOpenShootingFilters = {},
                    onSelectNotation = {},
                    onSelectFilm = {},
                    onSelectProfile = {},
                    onSelectSlot = controller::selectSlot,
                    onRenameSlot = {},
                    onSetTarget = {},
                    onStartTarget = {},
                    onStartAdjusted = {},
                    onStartCorrected = {},
                    onOpenDetails = {},
                    onResetSettings = {},
                    onCreateCustomFilm = { _, _ -> true },
                    onCreateCustomTableFilm = { _, _ -> true },
                    onEditCustomFilm = { null },
                    onDeleteCustomFilm = {},
                    onPreviewCustomFilm = { null },
                    onPreviewCustomTableFilm = { null },
                    onFormulaCheckpoints = { emptyList() },
                    onTableCheckpoints = { emptyList() },
                    onCalculationBasis = { "" },
                    onPreviewTableFit = { null },
                    onCreateFormulaFromTable = { _, _ -> true },
                    onReferencePoints = { _, _ -> emptyList() },
                    onOpenAbout = {},
                    onOpenFilterManagement = {},
                    showExactAlarmSettingsAction = false,
                    onOpenExactAlarmSettings = {},
                    cameraActions = actions,
                )
            }
        }
    }

    private fun swipeLeftTimes(count: Int) = repeat(count) {
        composeTestRule.onRoot().performTouchInput { swipeLeft() }
        composeTestRule.waitForIdle()
    }

    private fun swipeToUtilityPage() {
        swipeLeftTimes(4)
        composeTestRule.onNodeWithTag("camera-utility-page").assertIsDisplayed()
    }

    @Test
    fun reachingAndLeavingTheUtilityPageChangesNoCameraCalculatorOrTimer() {
        showShootingScreen()
        // Settle on the last camera first; only the step onto the utility page is under test.
        swipeLeftTimes(3)
        composeTestRule.onNodeWithText("Camera 4").assertIsDisplayed()
        val before = controller.exportCameraList()

        swipeLeftTimes(1)
        composeTestRule.onNodeWithTag("camera-utility-page").assertIsDisplayed()
        assertEquals(before, controller.exportCameraList())
        assertEquals(0, started)

        composeTestRule.onRoot().performTouchInput { swipeRight() }
        composeTestRule.waitForIdle()
        // Reversing returns to the last displayed camera, unchanged.
        composeTestRule.onNodeWithText("Camera 4").assertIsDisplayed()
        assertEquals(before, controller.exportCameraList())
        assertEquals(0, started)
    }

    @Test
    fun managementOpenedFromTheUtilityPageReturnsToTheUtilityPageAfterEdits() {
        showShootingScreen()
        swipeToUtilityPage()
        composeTestRule.onNodeWithTag("utility-page-manage-cameras").performClick()
        composeTestRule.onNodeWithText("Cameras").assertIsDisplayed()

        // Another management edit first: hide Camera 1.
        composeTestRule.onNodeWithTag("camera-row-visibility-0").performClick()
        composeTestRule.onNodeWithContentDescription("Close").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("camera-utility-page").assertIsDisplayed()
    }

    @Test
    fun managementOpenedFromSettingsReturnsToTheActiveCamera() {
        showShootingScreen()
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.onNodeWithText("Manage cameras").performClick()
        composeTestRule.onNodeWithText("Cameras").assertIsDisplayed()

        // Hiding the active Camera 1 makes Camera 2 active.
        composeTestRule.onNodeWithTag("camera-row-visibility-0").performClick()
        composeTestRule.onNodeWithContentDescription("Close").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onAllNodesWithTag("camera-utility-page").assertCountEquals(0)
        composeTestRule.onNodeWithText("Camera 2").assertIsDisplayed()
    }

    @Test
    fun hidingEveryCameraAndClosingShowsTheEmptyState() {
        showShootingScreen()
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.onNodeWithText("Manage cameras").performClick()
        composeTestRule.onNodeWithText("Edit").performClick()
        (0..3).forEach { composeTestRule.onNodeWithTag("camera-row-select-$it").performClick() }
        composeTestRule.onNodeWithTag("camera-management-bulk-hide").performClick()
        composeTestRule.onNodeWithText("Done").performClick()
        composeTestRule.onNodeWithContentDescription("Close").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("empty-camera-pager").assertIsDisplayed()
        composeTestRule.onNodeWithText("No cameras shown").assertIsDisplayed()
    }

    @Test
    fun aFailedStorageReadShowsTheExplanationAndDisablesEveryCameraEntryPoint() {
        showShootingScreen(storageReadFails = true)

        composeTestRule.onNodeWithText("Camera data couldn't be loaded. Restart the app.").assertIsDisplayed()
        composeTestRule.onNodeWithTag("empty-pager-add-camera").assertIsNotEnabled()
        composeTestRule.onNodeWithTag("empty-pager-manage-cameras").assertIsNotEnabled()
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.onNodeWithTag("shooting-settings-manage-cameras").assertIsNotEnabled()
        // The calculator-bound start is refused without a camera; nothing started.
        assertEquals(0, started)
    }

    /**
     * Reproducible capture of the failed-read screen: an injected failing store
     * (no real data is touched) renders the real shooting screen, and the frame
     * is written as a PNG to the app's external files directory for review.
     */
    @Test
    fun aFailedStorageReadScreenIsCapturedForReview() {
        showShootingScreen(storageReadFails = true)
        composeTestRule.onNodeWithText("Camera data couldn't be loaded. Restart the app.").assertIsDisplayed()

        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        val directory = java.io.File(requireNotNull(context.getExternalFilesDir("evidence")), "failed-read").apply { mkdirs() }
        val bitmap = composeTestRule.onRoot().captureToImage().asAndroidBitmap()
        val file = java.io.File(directory, "failed-read-shooting-screen.png")
        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue(file.length() > 0)
    }
}
