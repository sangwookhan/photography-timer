// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * The Filter Set management mark: stacked layers, the same idea iOS uses
 * beside its `ND 필터` title (FILTER-SET-001).
 *
 * It replaces a general settings gear, which said "settings" without
 * saying WHAT is being managed — the owner's 3rd-pass review called that
 * out. Layers read as a stack of physical filters and tie the control to
 * the title it sits beside.
 *
 * Drawn here rather than taken from `material-icons-extended`: the app
 * depends on `material-icons-core` only, and one glyph is not worth a
 * dependency that ships thousands.
 */
internal val FilterSetsMark: ImageVector by lazy {
    ImageVector.Builder(
        name = "FilterSetsMark",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        // The top sheet, face on.
        path(fill = SolidColor(Color.Black)) {
            moveTo(12f, 3.2f)
            lineTo(21.2f, 8.4f)
            lineTo(12f, 13.6f)
            lineTo(2.8f, 8.4f)
            close()
        }
        // The two sheets under it, as their leading edges only.
        path(
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 1.7f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        ) {
            moveTo(2.8f, 12.4f)
            lineTo(12f, 17.6f)
            lineTo(21.2f, 12.4f)
        }
        path(
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 1.7f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        ) {
            moveTo(2.8f, 16.4f)
            lineTo(12f, 21.6f)
            lineTo(21.2f, 16.4f)
        }
    }.build()
}
