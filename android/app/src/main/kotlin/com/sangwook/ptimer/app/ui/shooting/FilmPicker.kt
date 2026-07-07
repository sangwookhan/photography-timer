// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.res.stringResource
import com.sangwook.ptimer.R
import com.sangwook.ptimer.app.ui.CappedFontScale
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import com.sangwook.ptimer.app.vm.FilmOption

// Film picker bottom sheet + its rows, extracted from ShootingScreen. The sheet
// drives the shooting screen's local state through lambdas (select / create /
// edit / delete / dismiss); the row composables stay private to this file.

/** Film picker bottom sheet: "No film", custom "My films", then catalog groups. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FilmPickerSheet(
    filmOptions: List<FilmOption>,
    selectedFilmId: String?,
    onSelect: (String?) -> Unit,
    onCreateNew: () -> Unit,
    onEditFilm: (String) -> Unit,
    onDeleteFilm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var showCreateMenu by remember { mutableStateOf(false) }
    val customFilms = filmOptions.filter { it.id != null && it.isCustom }
    val grouped = filmOptions
        .filter { it.id != null && !it.isCustom }
        .groupBy { it.manufacturer?.takeIf { m -> m.isNotBlank() } ?: "Other" }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        // ModalBottomSheet hosts its own dialog window, which re-derives
        // LocalDensity from the system Configuration rather than inheriting
        // ShootingApp's font-scale cap (PTIMER-219) — reapply it here.
        CappedFontScale {
        LazyColumn {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.films_title),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f, fill = false),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Box {
                        IconButton(onClick = { showCreateMenu = true }) {
                            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.filmpicker_add_cd))
                        }
                        DropdownMenu(expanded = showCreateMenu, onDismissRequest = { showCreateMenu = false }) {
                            // DropdownMenu is Popup-based, which hosts its own
                            // dialog window and re-derives LocalDensity from the
                            // system Configuration rather than inheriting the
                            // ModalBottomSheet's font-scale cap (PTIMER-219).
                            CappedFontScale {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.create_custom_film)) },
                                leadingIcon = { Icon(Icons.Filled.Add, contentDescription = null) },
                                onClick = { showCreateMenu = false; onCreateNew() },
                            )
                            }
                        }
                    }
                }
            }
            item {
                FilmPickerRow(
                    option = FilmOption(null, stringResource(R.string.no_film)),
                    selected = selectedFilmId == null,
                    onClick = { onSelect(null) },
                )
            }
            if (customFilms.isNotEmpty()) {
                item { FilmManufacturerHeader(stringResource(R.string.my_films)) }
                items(customFilms, key = { it.id!! }) { option ->
                    FilmPickerRow(
                        option = option,
                        selected = option.id == selectedFilmId,
                        onClick = { onSelect(option.id) },
                        onEdit = { onEditFilm(option.id!!) },
                        onDelete = { onDeleteFilm(option.id!!) },
                    )
                }
            }
            grouped.forEach { (manufacturer, options) ->
                item { FilmManufacturerHeader(manufacturer) }
                items(options, key = { it.id!! }) { option ->
                    FilmPickerRow(
                        option = option,
                        selected = option.id == selectedFilmId,
                        onClick = { onSelect(option.id) },
                    )
                }
            }
            item { Spacer(Modifier.height(16.dp)) }
        }
        }
    }
}

@Composable
private fun FilmManufacturerHeader(name: String) {
    Text(
        name.uppercase(),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
    )
}

/**
 * One film row in the picker: name, a selected check, and trailing metadata —
 * an UNOFFICIAL badge, a reciprocity-curve glyph, and the ISO (mirrors iOS).
 */
@Composable
private fun FilmPickerRow(
    option: FilmOption,
    selected: Boolean,
    onClick: () -> Unit,
    onEdit: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(option.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingContent = if (selected) {
            { Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.common_selected_cd), tint = MaterialTheme.colorScheme.primary) }
        } else {
            null
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (option.isUnofficial) Pill("UNOFFICIAL")
                if (option.hasReciprocityCurve) CurveGlyph()
                option.iso?.let {
                    Text(
                        "ISO $it",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (onEdit != null || onDelete != null) {
                    var menu by remember { mutableStateOf(false) }
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.filmpicker_actions_cd))
                        }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            // DropdownMenu is Popup-based, which hosts its own
                            // dialog window and re-derives LocalDensity from the
                            // system Configuration rather than inheriting the
                            // ModalBottomSheet's font-scale cap (PTIMER-219).
                            CappedFontScale {
                            onEdit?.let { edit ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.action_edit)) },
                                    leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                                    onClick = { menu = false; edit() },
                                )
                            }
                            onDelete?.let { del ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.action_delete)) },
                                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                                    onClick = { menu = false; del() },
                                )
                            }
                            }
                        }
                    }
                }
            }
        },
        modifier = Modifier.clickable { onClick() },
    )
}

/** Tiny rising log-log curve glyph marking films that carry reciprocity data. */
@Composable
private fun CurveGlyph() {
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    Canvas(Modifier.size(16.dp)) {
        val path = Path()
        path.moveTo(size.width * 0.1f, size.height * 0.85f)
        path.cubicTo(
            size.width * 0.45f, size.height * 0.82f,
            size.width * 0.55f, size.height * 0.22f,
            size.width * 0.9f, size.height * 0.15f,
        )
        drawPath(path, color, style = Stroke(width = 1.5.dp.toPx()))
    }
}


