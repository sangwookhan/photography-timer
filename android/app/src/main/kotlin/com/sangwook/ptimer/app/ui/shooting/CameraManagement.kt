// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.CameraAnnouncement
import com.sangwook.ptimer.app.vm.CameraPagerNavigation
import com.sangwook.ptimer.core.slots.CameraListEntry
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Everything camera management and the pager's utility page ask of the state
 * layer. Holds no camera state: every action forwards to the camera-list
 * commands. [activeCamera] reads the resulting active camera right after an
 * edit, so the screen can announce it (CAMERA-PAGER-006).
 */
data class CameraManagementActions(
    /** `false` after a storage read that failed: camera state is read-only for the launch. */
    val isEditable: Boolean,
    /** Returns once the add has completed, so the caller can announce the resulting camera. */
    val add: suspend () -> Unit,
    val rename: (CameraSlotId, String) -> Boolean,
    val setDisplayed: (CameraSlotId, Boolean) -> Unit,
    val move: (CameraSlotId, Int) -> Unit,
    val hide: (Set<CameraSlotId>) -> Unit,
    val delete: (Set<CameraSlotId>) -> Unit,
    val activeCamera: () -> CameraSlotIdentity?,
) {
    companion object {
        val None = CameraManagementActions(
            isEditable = true,
            add = {},
            rename = { _, _ -> false },
            setDisplayed = { _, _ -> },
            move = { _, _ -> },
            hide = {},
            delete = {},
            activeCamera = { null },
        )
    }
}

/**
 * Announces a camera-list change through TalkBack (CAMERA-PAGER-006) and
 * leaves TalkBack's focus where the platform puts it: Android announces the
 * resulting camera or the empty state, it does not move accessibility focus.
 */
internal class CameraChangeAnnouncer(private val view: android.view.View, private val resources: android.content.res.Resources) {
    fun announce(before: CameraSlotId?, after: CameraSlotIdentity?, isDeletion: Boolean) {
        val message = when (val result = CameraPagerNavigation.announcementAfter(before, after, isDeletion)) {
            is CameraAnnouncement.ActiveCamera -> resources.getString(R.string.camera_active_announcement, result.name)
            CameraAnnouncement.NoCamerasShown -> resources.getString(R.string.camera_empty_title)
            null -> return
        }
        view.announceForAccessibility(message)
    }
}

@Composable
internal fun rememberCameraChangeAnnouncer(): CameraChangeAnnouncer {
    val view = LocalView.current
    val resources = LocalResources.current
    return remember(view, resources) { CameraChangeAnnouncer(view, resources) }
}

/**
 * The one `Add camera` action every entry point uses (camera management, the
 * trailing utility page, the all-hidden empty state): it starts the add, waits
 * for it to finish (the next number is reserved durably first), then announces
 * the resulting active camera. The owner still runs the add on its own scope.
 */
@Composable
internal fun rememberAddCameraAction(actions: CameraManagementActions): () -> Unit {
    val announcer = rememberCameraChangeAnnouncer()
    val scope = rememberCoroutineScope()
    val current by rememberUpdatedState(actions)
    return remember(announcer, scope) {
        {
            scope.launch {
                val before = current.activeCamera()?.id
                current.add()
                announcer.announce(before, current.activeCamera(), isDeletion = false)
            }
            Unit
        }
    }
}

/**
 * Camera management: rename, show/hide, delete, add, and — in edit mode —
 * reorder and multi-select hide/delete over the managed camera list. Two
 * explicit modes (CAMERA-PAGER-008): in normal mode the leading action is an X
 * icon named `Close` and the trailing action is `Edit`; in edit mode the
 * leading close action is absent, system back dismissal is blocked, and the
 * trailing action is `Done`, which only leaves edit mode and clears the
 * selection. Confirmed actions apply immediately.
 *
 * Normal rows show the name with `n of N · Shown/Hidden`, an eye / eye-slash
 * control that shows or hides directly, a tap on the name to rename, and a
 * trailing swipe that reveals `Delete` and asks for confirmation. Edit rows
 * add a drag handle for reordering and a checkbox for the bulk actions in the
 * bottom bar (CAMERA-PAGER-005/006).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CameraManagementScreen(
    cameras: List<CameraListEntry>,
    activeId: CameraSlotId?,
    actions: CameraManagementActions,
    onDismiss: () -> Unit,
) {
    var isEditing by rememberSaveable { mutableStateOf(false) }
    var selection by remember { mutableStateOf(emptySet<CameraSlotId>()) }
    var renamingId by remember { mutableStateOf<CameraSlotId?>(null) }
    var pendingDelete by remember { mutableStateOf<Set<CameraSlotId>?>(null) }
    val view = LocalView.current
    val resources = LocalResources.current
    val announcer = rememberCameraChangeAnnouncer()

    // Runs a list edit and, after a confirmed deletion or an active-camera
    // change, announces the resulting camera or the empty state. Android
    // announces through TalkBack and keeps its current focus; it does not move
    // accessibility focus (CAMERA-PAGER-006).
    fun announceResult(before: CameraSlotId?, isDeletion: Boolean) =
        announcer.announce(before, actions.activeCamera(), isDeletion)

    fun performEdit(isDeletion: Boolean = false, edit: () -> Unit) {
        val before = actions.activeCamera()?.id
        edit()
        announceResult(before, isDeletion)
    }

    // Add completes asynchronously, so its result is announced after it finishes
    // by the same action every Add entry point uses.
    val addCamera = rememberAddCameraAction(actions)

    // Moves one camera by [delta] positions and announces where it landed.
    fun moveCamera(id: CameraSlotId, from: Int, delta: Int) {
        actions.move(id, delta)
        view.announceForAccessibility(
            resources.getString(
                R.string.camera_moved_announcement,
                (from + delta).coerceIn(0, cameras.lastIndex) + 1,
                cameras.size,
            ),
        )
    }

    val listState = rememberLazyListState()
    val reorder = remember { RowReorder() }
    // After a drop the dropped order stays on screen until the list reports
    // it, so the row does not flash back to its old slot for a frame.
    var droppedOrder by remember { mutableStateOf<List<CameraSlotId>?>(null) }
    LaunchedEffect(cameras) { droppedOrder = null }
    LaunchedEffect(droppedOrder) {
        if (droppedOrder != null) {
            delay(DropSettleMillis)
            droppedOrder = null
        }
    }
    val dragTarget by remember(cameras) { derivedStateOf { reorder.targetIndex() } }
    val shownCameras = remember(cameras, reorder.draggedId, dragTarget, droppedOrder) {
        when {
            reorder.draggedId != null -> cameras.movedTo(reorder.startIndex, dragTarget)
            droppedOrder != null -> cameras.orderedBy(droppedOrder!!)
            else -> cameras
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        // Edit mode blocks system back and the back gesture (CAMERA-PAGER-008).
        properties = DialogProperties(
            dismissOnBackPress = !isEditing,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        CappedFontScale {
            Surface(modifier = Modifier.fillMaxSize()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.camera_management_title)) },
                            navigationIcon = {
                                if (!isEditing) {
                                    IconButton(
                                        onClick = onDismiss,
                                        modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).testTag("camera-management-close"),
                                    ) {
                                        Icon(
                                            Icons.Filled.Close,
                                            contentDescription = stringResource(R.string.action_close),
                                        )
                                    }
                                }
                            },
                            actions = {
                                TextButton(
                                    onClick = {
                                        selection = emptySet()
                                        isEditing = !isEditing
                                    },
                                    enabled = actions.isEditable && (cameras.isNotEmpty() || isEditing),
                                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface),
                                    modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).testTag("camera-management-edit"),
                                ) {
                                    Text(
                                        stringResource(if (isEditing) R.string.action_done else R.string.action_edit),
                                        fontWeight = if (isEditing) FontWeight.Bold else FontWeight.Medium,
                                    )
                                }
                            },
                        )
                    },
                    bottomBar = {
                        Surface(tonalElevation = 3.dp) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .navigationBarsPadding()
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                if (isEditing) {
                                    val chosen = selection.filter { id -> cameras.any { it.id == id } }.toSet()
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        OutlinedButton(
                                            onClick = {
                                                performEdit { actions.hide(chosen) }
                                                selection = emptySet()
                                            },
                                            enabled = chosen.isNotEmpty(),
                                            modifier = Modifier.weight(1f).testTag("camera-management-bulk-hide"),
                                        ) { Text(stringResource(R.string.action_hide)) }
                                        OutlinedButton(
                                            onClick = { pendingDelete = chosen },
                                            enabled = chosen.isNotEmpty(),
                                            modifier = Modifier.weight(1f).testTag("camera-management-bulk-delete"),
                                        ) {
                                            Text(
                                                stringResource(R.string.action_delete),
                                                color = if (chosen.isNotEmpty()) MaterialTheme.colorScheme.error else Color.Unspecified,
                                            )
                                        }
                                    }
                                } else {
                                    AddCameraButton(
                                        isEnabled = actions.isEditable,
                                        onClick = addCamera,
                                        modifier = Modifier.fillMaxWidth().testTag("camera-management-add"),
                                        legible = true,
                                    )
                                }
                            }
                        }
                    },
                ) { padding ->
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding),
                    ) {
                        if (cameras.isEmpty()) {
                            item(key = "empty") {
                                Text(
                                    stringResource(if (actions.isEditable) R.string.camera_list_empty else R.string.camera_data_load_failed),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(24.dp)
                                        .testTag("camera-management-empty"),
                                )
                            }
                        } else if (activeId == null) {
                            item(key = "status") {
                                Text(
                                    stringResource(R.string.camera_empty_title),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier
                                        .padding(horizontal = 16.dp, vertical = 12.dp)
                                        .testTag("camera-management-empty-status"),
                                )
                            }
                        }
                        itemsIndexed(shownCameras, key = { _, camera -> camera.id.raw }) { index, camera ->
                            val isDragged = reorder.draggedId == camera.id
                            CameraRow(
                                camera = camera,
                                index = index,
                                count = shownCameras.size,
                                isEditing = isEditing,
                                isEditable = actions.isEditable,
                                isSelected = camera.id in selection,
                                modifier = if (isDragged) {
                                    Modifier.zIndex(1f).graphicsLayer {
                                        val top = listState.layoutInfo.visibleItemsInfo
                                            .firstOrNull { it.key == camera.id.raw }?.offset
                                        translationY = if (top == null) reorder.delta else reorder.startTop + reorder.delta - top
                                    }
                                } else {
                                    Modifier.animateItem()
                                },
                                isDragged = isDragged,
                                onToggleSelected = {
                                    selection = if (camera.id in selection) selection - camera.id else selection + camera.id
                                },
                                onRename = { renamingId = camera.id },
                                onToggleDisplayed = { performEdit { actions.setDisplayed(camera.id, !camera.isDisplayed) } },
                                onMove = { delta -> moveCamera(camera.id, index, delta) },
                                onDelete = { pendingDelete = setOf(camera.id) },
                                onDragStart = {
                                    val visible = listState.layoutInfo.visibleItemsInfo
                                    reorder.begin(camera.id, cameras.indexOfFirst { it.id == camera.id }, cameras.mapIndexedNotNull { i, entry ->
                                        visible.firstOrNull { it.key == entry.id.raw }
                                            ?.let { RowSpan(i, it.offset, it.offset + it.size) }
                                    })
                                },
                                onDrag = reorder::dragBy,
                                onDragEnd = {
                                    val from = reorder.startIndex
                                    val target = reorder.targetIndex()
                                    val id = reorder.draggedId
                                    reorder.end()
                                    if (id != null && target != from) {
                                        droppedOrder = cameras.movedTo(from, target).map { it.id }
                                        moveCamera(id, from, target - from)
                                    }
                                },
                            )
                            HorizontalDivider()
                        }
                    }
                }
            }
        }

        renamingId?.let { id ->
            val current = cameras.firstOrNull { it.id == id }
            if (current == null) {
                renamingId = null
            } else {
                RenameCameraDialog(
                    initial = current.name,
                    onConfirm = { name ->
                        actions.rename(id, name)
                        renamingId = null
                    },
                    onDismiss = { renamingId = null },
                )
            }
        }

        pendingDelete?.let { ids ->
            DeleteCamerasDialog(
                names = cameras.filter { it.id in ids }.map { it.name },
                onConfirm = {
                    performEdit(isDeletion = true) { actions.delete(ids) }
                    selection = selection - ids
                    pendingDelete = null
                },
                onDismiss = { pendingDelete = null },
            )
        }
    }
}

/** One camera's original vertical extent in the list, captured when a drag starts. */
private class RowSpan(val index: Int, val top: Int, val bottom: Int)

/**
 * The drag-reorder gesture state for one camera at a time. The target slot is
 * decided from the extents captured at the start of the drag and the finger's
 * travel, so rows of different heights (wrapped names) reorder correctly; the
 * list order itself changes once, on drop.
 */
private class RowReorder {
    var draggedId by mutableStateOf<CameraSlotId?>(null)
        private set
    var delta by mutableFloatStateOf(0f)
        private set
    var startIndex = 0
        private set
    var startTop = 0
        private set
    private var startBottom = 0
    private var spans: List<RowSpan> = emptyList()

    fun begin(id: CameraSlotId, index: Int, visible: List<RowSpan>) {
        val own = visible.firstOrNull { it.index == index } ?: return
        spans = visible
        startIndex = index
        startTop = own.top
        startBottom = own.bottom
        delta = 0f
        draggedId = id
    }

    fun dragBy(dy: Float) {
        delta += dy
    }

    /** The camera index the dragged row currently hovers; `-1` when no drag is active. */
    fun targetIndex(): Int {
        if (draggedId == null || spans.isEmpty()) return -1
        val center = (startTop + startBottom) / 2f + delta
        return (spans.firstOrNull { center < it.bottom } ?: spans.last()).index
    }

    fun end() {
        draggedId = null
        delta = 0f
        spans = emptyList()
    }
}

private fun List<CameraListEntry>.movedTo(from: Int, to: Int): List<CameraListEntry> {
    if (from !in indices || to !in indices || from == to) return this
    return toMutableList().also { it.add(to, it.removeAt(from)) }
}

private fun List<CameraListEntry>.orderedBy(ids: List<CameraSlotId>): List<CameraListEntry> {
    val byId = associateBy { it.id }
    val ordered = ids.mapNotNull { byId[it] }
    return if (ordered.size == size) ordered else this
}

/**
 * One camera row. The name wraps instead of truncating so long names stay
 * readable at large font scales. Position and state stay visible so cameras
 * with the same name remain distinguishable (CAMERA-NAME-003); the raw
 * identity is never shown. The accessibility label is `name, state, n of N`.
 *
 * Normal mode: tap the name to rename, the trailing eye / eye-slash control
 * shows or hides, a trailing swipe reveals `Delete` and asks to confirm. Edit
 * mode: a checkbox selects the row and a drag handle reorders it; TalkBack
 * keeps `Move up` / `Move down` actions so no gesture is required
 * (CAMERA-PAGER-005/006/008).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CameraRow(
    camera: CameraListEntry,
    index: Int,
    count: Int,
    isEditing: Boolean,
    isEditable: Boolean,
    isSelected: Boolean,
    isDragged: Boolean,
    modifier: Modifier,
    onToggleSelected: () -> Unit,
    onRename: () -> Unit,
    onToggleDisplayed: () -> Unit,
    onMove: (Int) -> Unit,
    onDelete: () -> Unit,
    onDragStart: () -> Unit,
    onDrag: (Float) -> Unit,
    onDragEnd: () -> Unit,
) {
    val state = stringResource(if (camera.isDisplayed) R.string.camera_state_shown else R.string.camera_state_hidden)
    val label = stringResource(R.string.camera_row_cd, camera.name, state, index + 1, count)
    val hideShowLabel = stringResource(if (camera.isDisplayed) R.string.camera_hide else R.string.camera_show)
    val renameLabel = stringResource(R.string.rename_camera_title)
    val deleteLabel = stringResource(R.string.camera_delete)
    val moveUpLabel = stringResource(R.string.camera_move_up)
    val moveDownLabel = stringResource(R.string.camera_move_down)
    val selectLabel = stringResource(R.string.camera_select_cd, camera.name)
    val currentDragStart by rememberUpdatedState(onDragStart)
    val currentDrag by rememberUpdatedState(onDrag)
    val currentDragEnd by rememberUpdatedState(onDragEnd)

    // The trailing swipe only reveals the `Delete` background; passing the
    // threshold opens the confirmation and the row settles back, so nothing is
    // removed without confirming (CAMERA-006).
    val swipe = rememberSwipeToDismissBoxState(
        confirmValueChange = { target ->
            if (target == SwipeToDismissBoxValue.EndToStart) onDelete()
            false
        },
        positionalThreshold = { total -> total * SwipeDeleteThreshold },
    )
    SwipeToDismissBox(
        state = swipe,
        modifier = modifier,
        enableDismissFromStartToEnd = false,
        enableDismissFromEndToStart = !isEditing && isEditable,
        backgroundContent = {
            if (swipe.dismissDirection == SwipeToDismissBoxValue.EndToStart) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.error)
                        .padding(horizontal = 24.dp),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.action_delete),
                        color = MaterialTheme.colorScheme.onError,
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.testTag("camera-row-swipe-delete-$index"),
                    )
                }
            }
        },
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = if (isDragged) 6.dp else 0.dp,
            shadowElevation = if (isDragged) 6.dp else 0.dp,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 64.dp)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
                    .testTag("camera-row-$index"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isEditing) {
                    // Visual only: the row's own node carries the select action and
                    // the checked state, so assistive technology meets one Select
                    // node per row, not a checkbox beside the name.
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clickable(enabled = isEditable, onClick = onToggleSelected)
                            .clearAndSetSemantics { testTag = "camera-row-select-$index" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Checkbox(checked = isSelected, onCheckedChange = null)
                    }
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable(enabled = isEditable, onClick = if (isEditing) onToggleSelected else onRename)
                        .padding(horizontal = 8.dp, vertical = 6.dp)
                        .clearAndSetSemantics {
                            contentDescription = label
                            if (isEditing) {
                                role = Role.Checkbox
                                toggleableState = ToggleableState(isSelected)
                            }
                            onClick(label = if (isEditing) selectLabel else renameLabel) {
                                if (isEditing) onToggleSelected() else onRename()
                                true
                            }
                            val rowActions = mutableListOf<CustomAccessibilityAction>()
                            if (!isEditing) {
                                rowActions += CustomAccessibilityAction(hideShowLabel) { onToggleDisplayed(); true }
                                rowActions += CustomAccessibilityAction(renameLabel) { onRename(); true }
                                rowActions += CustomAccessibilityAction(deleteLabel) { onDelete(); true }
                            } else {
                                // Reordering and its non-drag alternatives belong to
                                // edit mode (CAMERA-PAGER-006/008).
                                if (index > 0) rowActions += CustomAccessibilityAction(moveUpLabel) { onMove(-1); true }
                                if (index < count - 1) rowActions += CustomAccessibilityAction(moveDownLabel) { onMove(1); true }
                            }
                            customActions = rowActions
                        },
                ) {
                    Text(
                        camera.name,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (camera.isDisplayed) {
                            MaterialTheme.colorScheme.onSurface
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                    Text(
                        stringResource(R.string.camera_row_detail, index + 1, count, state),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (isEditing) {
                    // Hidden from accessibility: TalkBack reorders through the
                    // row's Move up / Move down actions.
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .pointerInput(camera.id, isEditable) {
                                if (!isEditable) return@pointerInput
                                detectDragGestures(
                                    onDragStart = { currentDragStart() },
                                    onDrag = { change, amount ->
                                        change.consume()
                                        currentDrag(amount.y)
                                    },
                                    onDragEnd = { currentDragEnd() },
                                    onDragCancel = { currentDragEnd() },
                                )
                            }
                            .clearAndSetSemantics { testTag = "camera-row-handle-$index" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            DragHandleIcon,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    IconButton(
                        onClick = onToggleDisplayed,
                        enabled = isEditable,
                        modifier = Modifier
                            .semantics { contentDescription = hideShowLabel }
                            .testTag("camera-row-visibility-$index"),
                    ) {
                        Icon(
                            if (camera.isDisplayed) EyeIcon else EyeSlashIcon,
                            contentDescription = null,
                            tint = if (camera.isDisplayed) {
                                MaterialTheme.colorScheme.onSurface
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                }
            }
        }
    }
}

internal const val SwipeDeleteThreshold = 0.4f
private const val DropSettleMillis = 400L


/**
 * Delete confirmation. The single-camera message explains that a camera with
 * the same name will not reconnect state or timers (CAMERA-006); a bulk
 * deletion asks once and names the count (CAMERA-007).
 */
@Composable
private fun DeleteCamerasDialog(names: List<String>, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val many = names.size > 1
    // AlertDialog composes each slot inside its own dialog window, which
    // re-derives LocalDensity from the system Configuration — every slot needs
    // its own CappedFontScale wrap.
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            CappedFontScale {
                Text(stringResource(if (many) R.string.camera_delete_title_many else R.string.camera_delete_title_one))
            }
        },
        text = {
            CappedFontScale {
                Text(
                    if (many) {
                        stringResource(R.string.camera_delete_message_many, names.size)
                    } else {
                        stringResource(R.string.camera_delete_message_one, names.firstOrNull().orEmpty())
                    },
                )
            }
        },
        confirmButton = {
            CappedFontScale {
                TextButton(onClick = onConfirm, modifier = Modifier.testTag("camera-management-confirm-delete")) {
                    Text(stringResource(R.string.action_delete), color = MaterialTheme.colorScheme.error)
                }
            }
        },
        dismissButton = {
            CappedFontScale {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
            }
        },
    )
}

/**
 * Renames a camera. The name is trimmed by the state layer; a blank name is
 * rejected (CAMERA-NAME-001), so Save stays disabled until there is text.
 */
@Composable
internal fun RenameCameraDialog(
    initial: String,
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    // AlertDialog composes each slot inside its own dialog window, which
    // re-derives LocalDensity from the system Configuration rather than
    // inheriting ShootingApp's font-scale cap (PTIMER-219) — every slot
    // needs its own CappedFontScale wrap, not just the AlertDialog call site.
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { CappedFontScale { Text(stringResource(R.string.rename_camera_title)) } },
        text = {
            CappedFontScale {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    label = { Text(stringResource(R.string.camera_name)) },
                )
            }
        },
        confirmButton = {
            CappedFontScale {
                TextButton(onClick = { onConfirm(text) }, enabled = text.isNotBlank()) {
                    Text(stringResource(R.string.action_save))
                }
            }
        },
        dismissButton = {
            CappedFontScale {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
            }
        },
    )
}

/**
 * `Add camera`: always visible; disabled only while the camera list is read-only.
 *
 * [legible] is the camera management normal-mode treatment (CAMERA-PAGER-011,
 * CAMERA-PAGER-012): an outlined button with no fill, a 1 dp `outline` token border
 * (measured above 3:1 against the bottom bar surface), an `onSurface` label, a
 * primary-color plus glyph only, and a 48 dp visible height. Its secondary emphasis
 * comes from the outlined color treatment only; no alpha reduction is applied
 * anywhere, so it never looks disabled. The other entry points keep the tonal
 * treatment.
 */
@Composable
internal fun AddCameraButton(
    isEnabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    legible: Boolean = false,
) {
    // The legible treatment colors the label (onSurface) and the plus (primary) explicitly:
    // the theme's text styles carry their own color, which would otherwise win over the button's.
    val plusTint = if (legible && isEnabled) MaterialTheme.colorScheme.primary else Color.Unspecified
    val labelColor = if (legible && isEnabled) MaterialTheme.colorScheme.onSurface else Color.Unspecified
    val content: @Composable RowScope.() -> Unit = {
        // Decorative: the accessible name stays "Add camera" (CAMERA-PAGER-010).
        Icon(
            Icons.Filled.Add,
            contentDescription = null,
            tint = if (plusTint == Color.Unspecified) LocalContentColor.current else plusTint,
            modifier = Modifier.size(18.dp).testTag("camera-add-plus"),
        )
        Spacer(Modifier.width(8.dp))
        Text(stringResource(R.string.action_add_camera), color = labelColor, textAlign = TextAlign.Center)
    }
    if (legible) {
        OutlinedButton(
            onClick = onClick,
            enabled = isEnabled,
            modifier = modifier.heightIn(min = AddCameraVisibleHeight),
            border = if (isEnabled) BorderStroke(1.dp, MaterialTheme.colorScheme.outline) else ButtonDefaults.outlinedButtonBorder(false),
            content = content,
        )
    } else {
        FilledTonalButton(onClick = onClick, enabled = isEnabled, modifier = modifier, content = content)
    }
}

/** Visible height of the camera management `Add camera` button (CAMERA-PAGER-011: 44 to 48 dp). */
internal val AddCameraVisibleHeight = 48.dp

/**
 * The pager's trailing utility page (CAMERA-PAGER-007): not a camera, so it
 * changes no camera, calculator, or timer state. On arrival accessibility
 * identifies it as `Camera management`.
 */
@Composable
internal fun CameraManagementUtilityPage(
    isEditable: Boolean,
    onManageCameras: () -> Unit,
    onAddCamera: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val title = stringResource(R.string.camera_management_page_title)
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp)
            .semantics { paneTitle = title }
            .testTag("camera-utility-page"),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CameraPageIcon()
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            stringResource(R.string.camera_management_page_message),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        CameraPageActions(
            isEditable = isEditable,
            onManageCameras = onManageCameras,
            onAddCamera = onAddCamera,
            tagPrefix = "utility-page",
        )
    }
}

/**
 * Shown in place of the pager when no camera is displayed (CAMERA-PAGER-004).
 * Existing timers stay available in the timer sheet; a calculator-bound timer
 * needs a displayed camera.
 */
@Composable
internal fun EmptyCameraPager(
    isEditable: Boolean,
    onManageCameras: () -> Unit,
    onAddCamera: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp)
            .testTag("empty-camera-pager"),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CameraPageIcon()
        if (isEditable) {
            Text(
                stringResource(R.string.camera_empty_title),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                stringResource(R.string.camera_empty_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        } else {
            // A failed storage read: the camera surface explains it and every
            // camera action is disabled for this launch (CAMERA-PERSIST-006).
            Text(
                stringResource(R.string.camera_data_load_failed),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() }.testTag("camera-data-load-failed"),
            )
        }
        CameraPageActions(
            isEditable = isEditable,
            onManageCameras = onManageCameras,
            onAddCamera = onAddCamera,
            tagPrefix = "empty-pager",
        )
    }
}

/** The camera icon both pages share; decorative, so hidden from accessibility. */
@Composable
private fun CameraPageIcon() {
    Icon(
        CameraIcon,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.size(48.dp),
    )
}

/**
 * `Manage cameras`, then `Add camera`, in this order on both pages
 * (CAMERA-PAGER-004/007). Both are disabled only while the camera list is
 * read-only after a failed storage read.
 */
@Composable
private fun CameraPageActions(
    isEditable: Boolean,
    onManageCameras: () -> Unit,
    onAddCamera: () -> Unit,
    tagPrefix: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
    ) {
        OutlinedButton(
            onClick = onManageCameras,
            enabled = isEditable,
            modifier = Modifier.weight(1f, fill = false).testTag("$tagPrefix-manage-cameras"),
        ) {
            Text(stringResource(R.string.action_manage_cameras), textAlign = TextAlign.Center)
        }
        AddCameraButton(
            isEnabled = isEditable,
            onClick = onAddCamera,
            modifier = Modifier.weight(1f, fill = false).testTag("$tagPrefix-add-camera"),
        )
    }
}

