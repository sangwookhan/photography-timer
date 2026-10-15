// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import com.sangwook.ptimer.app.vm.CameraAnnouncement
import com.sangwook.ptimer.app.vm.CameraPagerNavigation
import com.sangwook.ptimer.core.slots.CameraListEntry
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity

/**
 * Everything camera management and the pager's utility page ask of the state
 * layer. Holds no camera state: every action forwards to the camera-list
 * commands. [activeCamera] reads the resulting active camera right after an
 * edit, so the screen can announce it (CAMERA-PAGER-006).
 */
data class CameraManagementActions(
    /** `false` after a storage read that failed: camera state is read-only for the launch. */
    val isEditable: Boolean,
    val add: () -> Unit,
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
 * Camera management: rename, show/hide, delete, add, and — in edit mode —
 * reorder and multi-select hide/delete over the managed camera list. Two
 * explicit modes (CAMERA-PAGER-008): in normal mode the leading action is an X
 * icon named `Close` and the trailing action is `Edit`; in edit mode the
 * leading close action is absent, system back dismissal is blocked, and the
 * trailing action is `Done`, which only leaves edit mode and clears the
 * selection. Confirmed actions apply immediately.
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
    fun performEdit(isDeletion: Boolean = false, edit: () -> Unit) {
        val before = actions.activeCamera()?.id
        edit()
        announcer.announce(before, actions.activeCamera(), isDeletion)
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
                                    IconButton(onClick = onDismiss, modifier = Modifier.testTag("camera-management-close")) {
                                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.action_close))
                                    }
                                }
                            },
                            actions = {
                                TextButton(
                                    onClick = {
                                        selection = emptySet()
                                        isEditing = !isEditing
                                    },
                                    enabled = cameras.isNotEmpty() || isEditing,
                                    modifier = Modifier.testTag("camera-management-edit"),
                                ) {
                                    Text(stringResource(if (isEditing) R.string.action_done else R.string.action_edit))
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
                                        onClick = { performEdit { actions.add() } },
                                        modifier = Modifier.fillMaxWidth().testTag("camera-management-add"),
                                    )
                                }
                            }
                        }
                    },
                ) { padding ->
                    LazyColumn(
                        modifier = Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding),
                    ) {
                        if (cameras.isEmpty()) {
                            item(key = "empty") {
                                Text(
                                    stringResource(R.string.camera_list_empty),
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
                        itemsIndexed(cameras, key = { _, camera -> camera.id.raw }) { index, camera ->
                            CameraRow(
                                camera = camera,
                                index = index,
                                count = cameras.size,
                                isEditing = isEditing,
                                isSelected = camera.id in selection,
                                onToggleSelected = {
                                    selection = if (camera.id in selection) selection - camera.id else selection + camera.id
                                },
                                onRename = { renamingId = camera.id },
                                onToggleDisplayed = { performEdit { actions.setDisplayed(camera.id, !camera.isDisplayed) } },
                                onMove = { delta ->
                                    actions.move(camera.id, delta)
                                    view.announceForAccessibility(
                                        resources.getString(
                                            R.string.camera_moved_announcement,
                                            (index + delta).coerceIn(0, cameras.lastIndex) + 1,
                                            cameras.size,
                                        ),
                                    )
                                },
                                onDelete = { pendingDelete = setOf(camera.id) },
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

/**
 * One camera row. The name wraps instead of truncating so long names stay
 * readable at large font scales. Position and state stay visible so cameras
 * with the same name remain distinguishable (CAMERA-NAME-003); the raw
 * identity is never shown. The accessibility label is `name, state, n of N`.
 */
@Composable
private fun CameraRow(
    camera: CameraListEntry,
    index: Int,
    count: Int,
    isEditing: Boolean,
    isSelected: Boolean,
    onToggleSelected: () -> Unit,
    onRename: () -> Unit,
    onToggleDisplayed: () -> Unit,
    onMove: (Int) -> Unit,
    onDelete: () -> Unit,
) {
    val state = stringResource(if (camera.isDisplayed) R.string.camera_state_shown else R.string.camera_state_hidden)
    val label = stringResource(R.string.camera_row_cd, camera.name, state, index + 1, count)
    val hideShowLabel = stringResource(if (camera.isDisplayed) R.string.camera_hide else R.string.camera_show)
    val renameLabel = stringResource(R.string.rename_camera_title)
    val deleteLabel = stringResource(R.string.camera_delete)
    val moveUpLabel = stringResource(R.string.camera_move_up)
    val moveDownLabel = stringResource(R.string.camera_move_down)
    val selectLabel = stringResource(R.string.camera_select_cd, camera.name)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp)
            .testTag("camera-row-$index"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isEditing) {
            Checkbox(
                checked = isSelected,
                onCheckedChange = { onToggleSelected() },
                modifier = Modifier
                    .semantics { contentDescription = selectLabel }
                    .testTag("camera-row-select-$index"),
            )
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .clickable(onClick = if (isEditing) onToggleSelected else onRename)
                .padding(horizontal = 8.dp, vertical = 6.dp)
                .clearAndSetSemantics {
                    contentDescription = label
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
            IconButton(onClick = { onMove(-1) }, enabled = index > 0, modifier = Modifier.testTag("camera-row-up-$index")) {
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = moveUpLabel)
            }
            IconButton(onClick = { onMove(1) }, enabled = index < count - 1, modifier = Modifier.testTag("camera-row-down-$index")) {
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = moveDownLabel)
            }
        } else {
            TextButton(
                onClick = onToggleDisplayed,
                modifier = Modifier
                    .semantics { contentDescription = hideShowLabel }
                    .testTag("camera-row-visibility-$index"),
            ) {
                Text(stringResource(if (camera.isDisplayed) R.string.action_hide else R.string.action_show))
            }
            IconButton(onClick = onDelete, modifier = Modifier.testTag("camera-row-delete-$index")) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = deleteLabel,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

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

/** `Add camera`: always visible; disabled only while the camera list is read-only. */
@Composable
internal fun AddCameraButton(isEnabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Button(onClick = onClick, enabled = isEnabled, modifier = modifier) {
        Text(stringResource(R.string.action_add_camera), textAlign = TextAlign.Center)
    }
}

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

