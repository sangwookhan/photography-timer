// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.app.persistence.PersistenceWriter
import com.sangwook.ptimer.app.vm.*
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.exposure.*
import com.sangwook.ptimer.ui.component.ManualWheelEvent
import com.sangwook.ptimer.ui.theme.PTimerTheme
import kotlinx.coroutines.*
import org.junit.*
import org.junit.Assert.*
import java.io.File
import java.util.Locale
import kotlin.math.pow

/** Real controller and full production shooting page with touchscreen events. */
class TargetNDConnectedFlowTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val caseName = org.junit.rules.TestName()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var controller: CalculatorController
    private lateinit var before: TargetNDProposalInput
    private val settings = TargetNDSettings()

    @After fun cleanup() {
        if (::controller.isInitialized) {
            println("FINAL_PHASE ${controller.targetNDProposal.state.value}")
            capture("final-state")
        }
        scope.cancel()
    }

    private fun show(aux: Boolean = false) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val nd = listOf(6.0, 3.0, 2.0, 1.0, 6.6).mapIndexed { i, n ->
                FilterItem("Long registered landscape physical filter item ${i+1} ND $n stops", FilterItemBehavior.Fixed(FilterRegisteredValue(n, FilterValueUnit.stops)))
            }
            val cpl = FilterItem("Retained CPL", FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, 2.0))))
            val gnd = FilterItem("Retained record GND", FilterItemBehavior.Gnd(FilterRegisteredValue(3.0, FilterValueUnit.stops)))
            val set = FilterSet("Long landscape collection", FilterSetColor.purple, nd + listOf(cpl, gnd))
            val inventory = FilterInventory(listOf(set))
            controller = CalculatorController(films = LaunchPresetFilmCatalogV2.films, ndCleanupScope = scope,
                inventoryModel = FilterInventoryModel(initial = inventory, persistenceWriter = PersistenceWriter { it() }))
            val mounts = if (aux) listOf(MountedAuxiliaryFilter(set.id, cpl.id, AuxiliaryFilterChoice.CplLoss(1.5)),
                MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly))) else emptyList()
            assertNull(controller.applyShootingFilters(listOf(set.id), mounts))
            val wanted = if (aux) listOf(nd[0], nd[1], nd[4]) else listOf(nd[0], nd[1], nd[2], nd[4])
            wanted.forEachIndexed { index, item ->
                controller.addFilterWheel(FilterSource.FilterSet(set.id))
                val wheel = controller.state.value.filterWheels.last { it.source == FilterSource.FilterSet(set.id) && it.rows[it.selectedIndex].isCleanable }
                val row = wheel.rows.indexOfFirst { it.selection.itemId == item.id }
                require(row >= 0)
                controller.setNdWheelActive(wheel.id, true); controller.setNdWheelValue(wheel.id, row); controller.setNdWheelActive(wheel.id, false)
                if (index == 0) controller.state.value.filterWheels.firstOrNull { it.source == FilterSource.Standard }?.let { controller.removeNdWheelFromOverscroll(it.id) }
            }
            controller.setShutterIndex(ExposureScale.oneThirdStop.shutterSteps.indexOfFirst { it.seconds == 1.0 })
            controller.selectFilm("fujifilm-acros-ii")
            controller.setTargetShutter(if (aux) 8192.0 else 4096.0 * kotlin.math.sqrt(2.0))
            before = requireNotNull(controller.targetNDInput(settings))
        }
        compose.setContent {
            val state by controller.state.collectAsState()
            val proposal by controller.targetNDProposal.state.collectAsState()
            PTimerTheme(darkTheme = true) {
                androidx.compose.foundation.layout.Box {
                ShootingScreen(state = state, onShutterIndex = controller::setShutterIndex,
                    onNdWheelActive = controller::setNdWheelActive, onNdWheelValue = controller::setNdWheelValue,
                    onAddFilterWheel = controller::addFilterWheel, onAdjustFilterWheel = controller::adjustFilterWheel,
                    onRemoveNdWheelOverscroll = controller::removeNdWheelFromOverscroll, onOpenShootingFilters = {},
                    onSelectNotation = controller::setNotationMode, onSelectFilm = controller::selectFilm,
                    onSelectProfile = controller::selectProfile, onSelectSlot = controller::selectSlot, onRenameSlot = {},
                    onSetTarget = controller::setTargetShutter, onStartTarget = controller::startFromTarget,
                    onStartAdjusted = controller::startFromAdjusted, onStartCorrected = controller::startFromCorrected,
                    onOpenDetails = {}, onResetSettings = {}, onCreateCustomFilm = { _, _ -> true }, onCreateCustomTableFilm = { _, _ -> true },
                    onEditCustomFilm = { null }, onDeleteCustomFilm = {}, onPreviewCustomFilm = { null }, onPreviewCustomTableFilm = { null },
                    onFormulaCheckpoints = { emptyList() }, onTableCheckpoints = { emptyList() }, onCalculationBasis = { "" },
                    onPreviewTableFit = { null }, onCreateFormulaFromTable = { _, _ -> true }, onReferencePoints = { _, _ -> emptyList() },
                    onOpenAbout = {}, onOpenFilterManagement = {}, showExactAlarmSettingsAction = false, onOpenExactAlarmSettings = {},
                    onLeaveMain = controller.targetNDProposal::invalidate, reviewLayout = null,
                    targetNDProposal = TargetNDProposalPresenter.display(proposal, androidx.compose.ui.platform.LocalConfiguration.current.locales[0]),
                    onApplyTargetND = { controller.applyPendingTargetNDProposal() },
                    onTargetNDFocus = { controller.targetNDProposal.focusAction(it, proposal.generation) },
                    onManualBaseEvent = { event -> when(event) {
                        ManualWheelEvent.Started -> controller.beginManualBase()
                        is ManualWheelEvent.Preview -> controller.previewManualBase(event.index)
                        is ManualWheelEvent.Committed -> controller.commitManualBase(event.index)
                        ManualWheelEvent.Cancelled -> controller.targetNDProposal.invalidate()
                    } })
                androidx.compose.material3.Text("Single row · Real controller/test inventory",
                    color = androidx.compose.ui.graphics.Color.Yellow,
                    style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
                    modifier = androidx.compose.ui.Modifier.align(androidx.compose.ui.Alignment.TopCenter))
                }
            }
        }
        compose.waitForIdle()
        assertEquals(TargetNDProposalSession.Phase.idle, controller.targetNDProposal.state.value.phase)
    }

    private fun sameValueTouch() {
        compose.onNodeWithContentDescription(InstrumentationRegistry.getInstrumentation().targetContext.getString(com.sangwook.ptimer.R.string.shooting_base_shutter)).performTouchInput {
            down(center); moveBy(Offset(0f, 1f)); advanceEventTime(100); up()
        }
        compose.waitUntil(3_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.result }
        compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).assertExists()
        compose.waitForIdle()
    }

    @Test fun liveRequiredNDUsesTrailingStatusArea() {
        show()
        val rowBefore = compose.onNodeWithTag("target-nd-review-region", useUnmergedTree = true).getUnclippedBoundsInRoot()
        compose.runOnIdle { controller.beginManualBase() }
        val row = compose.onNodeWithTag("target-nd-review-region", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val live = compose.onNodeWithTag("target-nd-review-guidance", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertEquals(rowBefore, row)
        assertTrue("Required ND should sit under the ND wheels", live.left.value + live.right.value > row.left.value + row.right.value)
        assertTrue(live.right <= row.right)
        capture("live-trailing")
    }

    private fun capture(name: String) {
        val artifact = "${caseName.methodName}-$name"
        val output = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "target-nd-review").apply { mkdirs() }
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(output, "$artifact.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        File(output, "$artifact.txt").writeText("state=${controller.state.value}\nproposal=${controller.targetNDProposal.state.value}\ninput=${controller.targetNDInput(settings)}")
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val shared = "/sdcard/Download/ptimer-242-review"
        android.os.ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("mkdir -p $shared")).use { it.readBytes() }
        val arguments = InstrumentationRegistry.getArguments()
        val manifest = org.json.JSONObject().apply {
            put("sourceHead", arguments.getString("source_head", "unspecified"))
            put("sourceTree", arguments.getString("source_tree", "unspecified"))
            put("case", caseName.methodName); put("capture", name); put("reviewLayout", "production")
            put("dummyPreview", false); put("inputType", "actual controller with registered physical test inventory")
            put("elapsedRealtimeMillis", SystemClock.elapsedRealtime()); put("api", android.os.Build.VERSION.SDK_INT)
            put("widthPixels", bitmap.width); put("heightPixels", bitmap.height)
            val config = InstrumentationRegistry.getInstrumentation().targetContext.resources.configuration
            put("language", config.locales[0].toLanguageTag()); put("fontScale", config.fontScale)
            put("theme", "dark")
            fun bounds(tag: String): String? = runCatching { compose.onNodeWithTag(tag, useUnmergedTree = true).getUnclippedBoundsInRoot().toString() }.getOrNull()
            put("rowBoundsDp", bounds("target-nd-review-region"))
            put("actionBoundsDp", bounds("target-nd-review-apply"))
            put("cardBoundsDp", bounds("target-nd-input-card"))
            put("density", InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density)
            put("phase", controller.targetNDProposal.state.value.phase.name)
            put("focused", controller.targetNDProposal.state.value.isActionFocused)
        }
        File(output, "$artifact.json").writeText(manifest.toString(2))
        listOf("png", "txt", "json").forEach { extension ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("cp ${File(output, "$artifact.$extension").absolutePath} $shared/$artifact.$extension")).use { it.readBytes() }
        }
    }

    @Test fun fourPhysicalFiltersSameValueEdgeTapApplyAndPreservation() {
        show(); capture("four-ordinary")
        val priorIds = controller.state.value.filterWheels.map { it.id }.toSet()
        val cardBefore = compose.onNodeWithTag("target-nd-input-card").getUnclippedBoundsInRoot()
        val baseBefore = compose.onNodeWithContentDescription(InstrumentationRegistry.getInstrumentation().targetContext.getString(com.sangwook.ptimer.R.string.shooting_base_shutter)).getUnclippedBoundsInRoot()
        sameValueTouch(); capture("four-settled")
        assertEquals(cardBefore, compose.onNodeWithTag("target-nd-input-card").getUnclippedBoundsInRoot())
        assertEquals(baseBefore, compose.onNodeWithContentDescription(InstrumentationRegistry.getInstrumentation().targetContext.getString(com.sangwook.ptimer.R.string.shooting_base_shutter)).getUnclippedBoundsInRoot())
        val row = compose.onNodeWithTag("target-nd-review-region").getUnclippedBoundsInRoot()
        val action = compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue(action.top > row.top)
        val offered = requireNotNull(TargetNDProposalPresenter.display(controller.targetNDProposal.state.value, Locale.ENGLISH)?.candidateTotalText).toDouble()
        val button = compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true)
        button.performTouchInput { click(Offset(width - 2f, height - 2f)) }
        compose.waitForIdle()
        println("EDGE_PHASE ${controller.targetNDProposal.state.value.phase} total=${controller.targetNDInput(settings)?.current?.effectiveStops}")
        capture("four-applied")
        compose.runOnIdle {
            val after = requireNotNull(controller.targetNDInput(settings))
            assertEquals(before.copy(current = after.current), after)
            assertEquals(12.0, after.current.effectiveStops, 1e-9)
            assertEquals(offered, after.current.effectiveStops, 1e-9)
            assertEquals(4, after.current.wheels.size)
            assertEquals(3, controller.state.value.filterWheels.count { it.id in priorIds })
            assertNotNull(controller.applyPendingTargetNDProposal())
        }
    }

    @Test fun standardSamePositionApplyKeepsIdentityAndEmphasizesValue() {
        show()
        compose.runOnIdle {
            assertNull(controller.applyShootingFilters(emptyList(), emptyList()))
            controller.selectFilm(null)
            controller.setTargetShutter(1024.0)
            before = requireNotNull(controller.targetNDInput(settings))
        }
        val prior = controller.state.value.filterWheels.single()
        capture("standard-before")
        sameValueTouch(); capture("standard-offer")
        compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).performTouchInput { click(center) }
        SystemClock.sleep(100)
        capture("standard-applied-pulse")
        compose.waitForIdle()
        assertEquals(prior.id, controller.state.value.filterWheels.single().id)
        assertNotEquals(prior.committedIndex, controller.state.value.filterWheels.single().committedIndex)
        assertEquals(10.0, requireNotNull(controller.targetNDInput(settings)).current.effectiveStops, 0.0)
        capture("standard-after")
    }

    @Test fun ordinaryCandidateReplacesCurrentTotalInOneRow() {
        show()
        compose.runOnIdle {
            controller.selectFilm(null); controller.setTargetShutter(4096.0)
            before = requireNotNull(controller.targetNDInput(settings))
        }
        capture("ordinary-before")
        sameValueTouch(); capture("ordinary-proposal")
        assertNull(TargetNDProposalPresenter.display(controller.targetNDProposal.state.value, Locale.ENGLISH)?.warning)
        assertEquals("12", TargetNDProposalPresenter.display(controller.targetNDProposal.state.value, Locale.ENGLISH)?.candidateTotalText)
    }

    @Test fun unavailableCombinationHasReasonAndNoAction() {
        show()
        compose.runOnIdle { controller.selectFilm(null); controller.setTargetShutter(1048576.0) }
        compose.onNodeWithContentDescription(InstrumentationRegistry.getInstrumentation().targetContext.getString(com.sangwook.ptimer.R.string.shooting_base_shutter)).performTouchInput {
            down(center); moveBy(Offset(0f, 1f)); advanceEventTime(100); up()
        }
        compose.waitUntil(3_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.result }
        compose.waitUntil(3_000) { controller.targetNDProposal.state.value.result is TargetNDSelectionResult.Unavailable }
        compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("target-nd-review-guidance", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("target-nd-current-total", useUnmergedTree = true).assertExists()
        assertTrue(controller.state.value.filterStatus.totalStopsText.isNotEmpty())
        capture("no-combination")
        compose.waitUntil(3_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.idle }
        capture("no-combination-expired")
    }

    @Test fun standardNoCombinationKeepsZeroAndNonzeroCurrentTotals() {
        show()
        compose.runOnIdle {
            assertNull(controller.applyShootingFilters(emptyList(), emptyList()))
            controller.selectFilm(null)
            controller.setTargetShutter(2.0.pow(31))
        }
        fun settle() {
            compose.onNodeWithContentDescription(InstrumentationRegistry.getInstrumentation().targetContext.getString(com.sangwook.ptimer.R.string.shooting_base_shutter)).performTouchInput {
                down(center); moveBy(Offset(0f, 1f)); advanceEventTime(100); up()
            }
            compose.waitUntil(3_000) { controller.targetNDProposal.state.value.result ==
                TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.NoCombination) }
        }
        settle()
        assertEquals("0", controller.state.value.filterStatus.totalStopsText)
        compose.onNodeWithTag("target-nd-current-total", useUnmergedTree = true).assertExists()
        capture("zero-total")
        compose.waitUntil(3_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.idle }
        compose.runOnIdle {
            val wheel = controller.state.value.filterWheels.single()
            val ten = wheel.rows.indexOfFirst { it.compactValueText == "10" }
            require(ten >= 0)
            controller.setNdWheelActive(wheel.id, true)
            controller.setNdWheelValue(wheel.id, ten)
            controller.setNdWheelActive(wheel.id, false)
        }
        settle()
        assertEquals("10", controller.state.value.filterStatus.totalStopsText)
        compose.onNodeWithTag("target-nd-current-total", useUnmergedTree = true).assertExists()
        capture("nonzero-total")
    }

    @Test fun readinessExpiresWithoutChangingThePhysicalStack() {
        show(); sameValueTouch(); capture("ready-before-expiry")
        compose.waitUntil(6_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.idle }
        compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).assertDoesNotExist()
        assertEquals(before, controller.targetNDInput(settings))
        capture("expired-ordinary")
    }

    @Test fun nativeAccessibilityActionFocusSuspendsRealExpiryThenResumes() {
        show(aux = true); sameValueTouch(); capture("aux-settled")
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.className == "android.widget.Button" && node.text?.toString()?.startsWith("Apply total") == true) return node
            for (i in 0 until node.childCount) find(node.getChild(i))?.let { return it }
            return null
        }
        var found: AccessibilityNodeInfo? = null
        val deadline = SystemClock.uptimeMillis() + 1_500
        while (found == null && SystemClock.uptimeMillis() < deadline) {
            val root = automation.rootInActiveWindow
            root?.refresh()
            found = find(root)
            if (found == null) SystemClock.sleep(50)
        }
        val action = requireNotNull(found)
        val service = automation.serviceInfo
        service.flags = service.flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE
        automation.serviceInfo = service
        compose.waitUntil(2_000) {
            (InstrumentationRegistry.getInstrumentation().targetContext.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE) as android.view.accessibility.AccessibilityManager).isTouchExplorationEnabled
        }
        assertTrue(action.isAccessibilityFocused || action.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS))
        compose.waitUntil(2_000) { controller.targetNDProposal.state.value.isActionFocused }
        SystemClock.sleep(5_200)
        assertEquals(TargetNDProposalSession.Phase.result, controller.targetNDProposal.state.value.phase)
        capture("aux-focused-after-five-seconds")
        assertTrue(action.performAction(AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS))
        compose.waitUntil(6_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.idle }
        capture("aux-expired")
        assertEquals(before, controller.targetNDInput(settings))
    }
    @Test fun auxiliaryEdgeApplyKeepsExactChoicesAndCameraInputs() {
        show(aux = true); sameValueTouch()
        val offered = requireNotNull(TargetNDProposalPresenter.display(controller.targetNDProposal.state.value, Locale.ENGLISH)?.candidateTotalText).toDouble()
        compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).performTouchInput { click(Offset(2f, 2f)) }
        compose.waitUntil(2_000) { controller.targetNDInput(settings)?.current?.effectiveStops == 12.5 }
        capture("aux-applied")
        compose.runOnIdle {
            val after = requireNotNull(controller.targetNDInput(settings))
            assertEquals(before.copy(current = after.current), after)
            assertEquals(before.current.auxiliaryFilters, after.current.auxiliaryFilters)
            assertEquals(offered, after.current.effectiveStops, 1e-9)
            assertEquals(3, after.current.wheels.size)
        }
    }

    @Test fun cameraSwipeAndSettingsDisableDiscardTheVisibleOffer() {
        show(); sameValueTouch()
        compose.onRoot().performTouchInput { swipeLeft() }
        compose.waitUntil(3_000) { controller.targetNDInput(settings)?.cameraId != before.cameraId }
        compose.runOnIdle { assertEquals(TargetNDProposalSession.Phase.idle, controller.targetNDProposal.state.value.phase) }
        compose.onRoot().performTouchInput { swipeRight() }
        compose.waitUntil(3_000) { controller.targetNDInput(settings)?.cameraId == before.cameraId }
        compose.runOnIdle { assertEquals(TargetNDProposalSession.Phase.idle, controller.targetNDProposal.state.value.phase) }
        sameValueTouch()
        compose.runOnIdle { controller.updateTargetNDSettings(settings.copy(isEnabled = false)) }
        compose.onNodeWithTag("target-nd-review-apply", useUnmergedTree = true).assertDoesNotExist()
        compose.runOnIdle {
            controller.updateTargetNDSettings(settings)
            assertEquals(before, controller.targetNDInput(settings))
            assertEquals(TargetNDProposalSession.Phase.idle, controller.targetNDProposal.state.value.phase)
        }
        capture("camera-settings-invalidated")
    }

    @Test fun liveTouchAndFinalSnapUseTheRealWheelAndTarget() {
        show()
        val base = compose.onNodeWithContentDescription(InstrumentationRegistry.getInstrumentation().targetContext.getString(com.sangwook.ptimer.R.string.shooting_base_shutter))
        base.performTouchInput { down(Offset(centerX, height * 0.8f)); moveTo(Offset(centerX, height * 0.2f), delayMillis = 200) }
        compose.runOnIdle { assertEquals(TargetNDProposalSession.Phase.interacting, controller.targetNDProposal.state.value.phase) }
        capture("base-live")
        base.performTouchInput { up() }
        compose.waitUntil(3_000) { controller.targetNDProposal.state.value.phase == TargetNDProposalSession.Phase.result }
        compose.waitForIdle()
        capture("base-settled")
        compose.runOnIdle {
            val input = requireNotNull(controller.targetNDInput(settings))
            assertEquals(before.targetSeconds, input.targetSeconds, 0.0)
            assertEquals(before.current, input.current)
        }
    }

}
