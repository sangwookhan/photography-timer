package com.sangwook.ptimer.ui.component

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sangwook.ptimer.core.reciprocity.ReciprocityGraph
import com.sangwook.ptimer.ui.theme.StatusDanger
import com.sangwook.ptimer.ui.theme.StatusSuccess
import com.sangwook.ptimer.ui.theme.StatusWarning

/**
 * Log-log reciprocity curve: green no-correction band, red beyond-source band,
 * grid + duration ticks, the calculation curve, table anchor dots, and the
 * current-result marker. Reads the normalized geometry from [ReciprocityGraph].
 * Shared by the reciprocity details screen and the custom-film editor previews.
 */
@Composable
fun ReciprocityGraphView(graph: ReciprocityGraph, modifier: Modifier) {
    val curveColor = MaterialTheme.colorScheme.primary
    val anchorColor = StatusSuccess
    val gridColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f)
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val greenBand = StatusSuccess.copy(alpha = 0.2f)
    val redBand = StatusDanger.copy(alpha = 0.2f)
    val measurer = rememberTextMeasurer()

    Canvas(modifier) {
        val rightPad = 8.dp.toPx()
        val topPad = 8.dp.toPx()
        val bottomPad = 16.dp.toPx()
        val plotLeft = 36.dp.toPx()
        val plotTop = topPad
        val plotW = size.width - plotLeft - rightPad
        val plotH = size.height - plotTop - bottomPad
        if (plotW <= 0f || plotH <= 0f) return@Canvas
        fun px(x: Double) = plotLeft + x.toFloat() * plotW
        fun py(y: Double) = plotTop + (1f - y.toFloat()) * plotH
        val tickStyle = TextStyle(fontSize = 8.sp, color = labelColor)

        graph.noCorrectionFraction?.let { f ->
            drawRect(greenBand, topLeft = Offset(plotLeft, plotTop), size = Size(f.toFloat() * plotW, plotH))
        }
        graph.sourceRangeFraction?.let { f ->
            drawRect(redBand, topLeft = Offset(px(f), plotTop), size = Size((1f - f.toFloat()) * plotW, plotH))
        }
        // Not-recommended manufacturer boundary: a vertical danger line (iOS marks
        // the metered exposure its stop-signal flags).
        graph.notRecommendedBoundaryFraction?.let { f ->
            val x = px(f)
            drawLine(StatusDanger, Offset(x, plotTop), Offset(x, plotTop + plotH), strokeWidth = 1.5.dp.toPx())
        }

        graph.xTicks.forEach { t ->
            val x = px(t.position)
            drawLine(gridColor, Offset(x, plotTop), Offset(x, plotTop + plotH), strokeWidth = 1f)
            val layout = measurer.measure(t.label, tickStyle)
            drawText(layout, topLeft = Offset(x - layout.size.width / 2f, plotTop + plotH + 2.dp.toPx()))
        }
        graph.yTicks.forEach { t ->
            val y = py(t.position)
            drawLine(gridColor, Offset(plotLeft, y), Offset(plotLeft + plotW, y), strokeWidth = 1f)
            val layout = measurer.measure(t.label, tickStyle)
            drawText(layout, topLeft = Offset(plotLeft - layout.size.width - 3.dp.toPx(), y - layout.size.height / 2f))
        }

        if (graph.curve.size >= 2) {
            val path = Path()
            graph.curve.forEachIndexed { i, p ->
                if (i == 0) path.moveTo(px(p.x), py(p.y)) else path.lineTo(px(p.x), py(p.y))
            }
            drawPath(path, curveColor, style = Stroke(width = 2.dp.toPx()))
        }
        graph.anchors.forEach { p ->
            drawCircle(anchorColor, radius = 3.5.dp.toPx(), center = Offset(px(p.x), py(p.y)))
        }
        graph.referenceMarkers.forEach { p ->
            drawCircle(anchorColor, radius = 3.5.dp.toPx(), center = Offset(px(p.x), py(p.y)))
        }
        graph.current?.let { p ->
            val cx = px(p.x)
            val cy = py(p.y)
            if (graph.currentOutOfRange) {
                // The result is outside the fixed plot range — draw an amber
                // triangle on the border pointing the way the value lies (i.e.
                // "out here, beyond the trustworthy range").
                val s = 6.dp.toPx()
                val tri = Path()
                when {
                    p.x >= 0.999 -> { tri.moveTo(cx, cy); tri.lineTo(cx - 2 * s, cy - s); tri.lineTo(cx - 2 * s, cy + s) }
                    p.x <= 0.001 -> { tri.moveTo(cx, cy); tri.lineTo(cx + 2 * s, cy - s); tri.lineTo(cx + 2 * s, cy + s) }
                    p.y >= 0.999 -> { tri.moveTo(cx, cy); tri.lineTo(cx - s, cy + 2 * s); tri.lineTo(cx + s, cy + 2 * s) }
                    else -> { tri.moveTo(cx, cy); tri.lineTo(cx - s, cy - 2 * s); tri.lineTo(cx + s, cy - 2 * s) }
                }
                tri.close()
                drawPath(tri, StatusWarning)
            } else {
                drawCircle(Color.White, radius = 5.dp.toPx(), center = Offset(cx, cy))
                drawCircle(curveColor, radius = 3.dp.toPx(), center = Offset(cx, cy))
            }
        }
    }
}

/**
 * Legend chips built from the graph's own geometry, matching iOS
 * `FilmModeDetailsDisplayStates.legendChipLabels`. Each chip reuses the exact
 * color the canvas draws for that element so the key reads against the plot.
 * Ordering mirrors iOS `legendChipLabels`.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GraphLegend(graph: ReciprocityGraph) {
    val curveColor = MaterialTheme.colorScheme.primary
    val hasReference = graph.anchors.isNotEmpty() || graph.referenceMarkers.isNotEmpty()
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        LegendItem(curveColor, "Calculation curve")
        LegendItem(curveColor, "Current result")
        if (hasReference) LegendItem(StatusSuccess, "Source reference")
        if (graph.noCorrectionFraction != null) LegendItem(StatusSuccess.copy(alpha = 0.2f), "No-correction range")
        if (graph.notRecommendedBoundaryFraction != null) LegendItem(StatusDanger, "Not-recommended boundary")
        if (graph.sourceRangeFraction != null) LegendItem(StatusDanger.copy(alpha = 0.2f), "Beyond source range")
        if (graph.currentOutOfRange) LegendItem(StatusWarning, "Outside visible range")
    }
}

@Composable
private fun LegendItem(color: Color, label: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(color))
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
