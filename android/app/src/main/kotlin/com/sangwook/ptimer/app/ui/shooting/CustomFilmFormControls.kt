// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
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
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType
/**
 * Material full-screen dialog for a multi-field input form: a top app bar with
 * a leading close (X) and a trailing confirm action over a scrolling body.
 * [onConfirm] runs validation and returns an error message (rendered at the top
 * of the form; the body scrolls up to it on failure) or null on success.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FullScreenFormDialog(
    title: String,
    confirmLabel: String,
    onConfirm: () -> String?,
    onDismiss: () -> Unit,
    clearErrorOn: Any? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    // Drop a stale validation message when the caller's reset key changes
    // (e.g. the Formula/Table toggle) so a formula error never lingers on the
    // table form, and vice versa.
    LaunchedEffect(clearErrorOn) { error = null }
    Dialog(
        onDismissRequest = onDismiss,
        // Draw edge-to-edge so the Scaffold's system-bar insets and imePadding
        // apply: without this the dialog window keeps the platform insets and
        // the on-screen keyboard covers the focused field (and the content's
        // bottom slides under the navigation bar).
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Surface(modifier = Modifier.fillMaxSize()) {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(title) },
                        navigationIcon = {
                            IconButton(onClick = onDismiss) {
                                Icon(Icons.Filled.Close, contentDescription = "Close")
                            }
                        },
                        actions = {
                            TextButton(onClick = {
                                error = onConfirm()
                                if (error != null) scope.launch { scroll.animateScrollTo(0) }
                            }) { Text(confirmLabel) }
                        },
                    )
                },
            ) { padding ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        // Consume the Scaffold's insets, then reserve the nav bar
                        // (so the bottom content — the preview graph + legend —
                        // clears the home indicator) and the keyboard on top of it
                        // (the canonical navigationBarsPadding().imePadding() stack,
                        // which avoids double-counting the overlap).
                        .consumeWindowInsets(padding)
                        .navigationBarsPadding()
                        .imePadding()
                        .padding(horizontal = 16.dp)
                        .verticalScroll(scroll),
                ) {
                    error?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            it,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Spacer(Modifier.height(4.dp))
                    }
                    content()
                }
            }
        }
    }
}


/**
 * Compact numeric Tm/Tc cell in the table editor (iOS: decimal-pad anchor
 * field). A slim bordered box — not the 56dp Material outlined field — so two
 * cells plus the delete control sit on one tidy line.
 */
@Composable
internal fun AnchorField(
    placeholder: String,
    value: String,
    onValue: (String) -> Unit,
    onFocusLost: () -> Unit = {},
) {
    val shape = RoundedCornerShape(8.dp)
    val textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace)
    var wasFocused by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f), shape)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (value.isEmpty()) {
            Text(placeholder, style = textStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        BasicTextField(
            value = value,
            onValueChange = onValue,
            singleLine = true,
            textStyle = textStyle.copy(color = MaterialTheme.colorScheme.onSurface),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier
                .fillMaxWidth()
                // Sorting fires when a cell loses focus (iOS commit point), so a
                // completed row settles into metered order without jumping mid-type.
                .onFocusChanged {
                    if (wasFocused && !it.isFocused) onFocusLost()
                    wasFocused = it.isFocused
                },
        )
    }
}

/** Which custom-film value row is expanded for inline editing. */
internal enum class EditField { Manufacturer, Label, Iso, Tc0, Tm0, P, B, NoCorrection, SourceData }

// Preset ladders mirror the iOS field sheets (CustomFilmEditorFieldSheets).
// The formula value chips store bare seconds (the equation appends "s" and the
// steppers parse doubles); the duration-parsed Source-data field keeps unit
// suffixes since the parser accepts s/m/h and "Unlimited".
internal val MANUFACTURER_PRESETS = listOf("ADOX", "Kodak", "Ilford", "Fujifilm", "Foma", "Rollei")
internal val ISO_PRESETS = listOf(
    "6", "12", "20", "25", "50", "64", "80", "100", "125", "160", "200", "250",
    "320", "400", "500", "640", "800", "1000", "1250", "1600", "3200",
)
internal val TC_PRESETS = listOf("0.1", "0.5", "1", "2", "5", "10", "30", "60")
internal val TM_PRESETS = listOf("0.5", "1", "2", "5", "10")
internal val P_PRESETS = listOf("1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "1.8", "1.9")
internal val B_PRESETS = listOf("-1", "-0.5", "0", "0.5", "1", "2")
internal val NO_CORRECTION_PRESETS = listOf("0.5", "1", "2", "5", "10", "30")
internal val SOURCE_PRESETS = listOf("Unlimited", "30s", "1m", "2m", "5m", "10m", "30m", "1h")

/**
 * Compact list row (label + current value + chevron) that toggles an inline
 * editor below it. The chevron points down while expanded. Keeps editing inside
 * the scrolling form — no nested popup window (which renders unreliably inside
 * the editor's Dialog).
 */
@Composable
internal fun EditorRow(label: String, value: String, expanded: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                value.ifBlank { "—" },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(
                if (expanded) Icons.Filled.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** "Source" provenance row in Details: current label + a dropdown of the
 *  CustomProfileSourceType options (iOS: the Source picker). */
@Composable
internal fun SourceTypeRow(value: CustomProfileSourceType, onSelect: (CustomProfileSourceType) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Source", style = MaterialTheme.typography.bodyLarge)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(value.displayLabel, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            CustomProfileSourceType.values().forEach { type ->
                DropdownMenuItem(text = { Text(type.displayLabel) }, onClick = { onSelect(type); open = false })
            }
        }
    }
}

/**
 * Inline value editor shown under an expanded [EditorRow]: an optional +/- step
 * stepper around a typable field, plus a row of quick "Common" presets — so a
 * value can be set without the keyboard (mirrors the iOS per-value sheet).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ValueEditPanel(
    value: String,
    onValue: (String) -> Unit,
    step: Double?,
    presets: List<String>,
    onClose: () -> Unit = {},
    hint: String? = null,
) {
    // Scroll the freshly-expanded panel fully into view so a row near the bottom
    // (e.g. No correction) isn't left hidden below the fold / keyboard.
    val bringIntoView = remember { BringIntoViewRequester() }
    LaunchedEffect(Unit) {
        delay(50)
        bringIntoView.bringIntoView()
    }
    Column(Modifier.fillMaxWidth().bringIntoViewRequester(bringIntoView).padding(bottom = 8.dp)) {
        hint?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
        }
        if (step != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { onValue(adjustValue(value, -step)) }) { Text("-${trimNum(step)}") }
                OutlinedTextField(
                    value = value,
                    onValueChange = onValue,
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    textStyle = MaterialTheme.typography.titleMedium.copy(textAlign = TextAlign.Center),
                )
                OutlinedButton(onClick = { onValue(adjustValue(value, step)) }) { Text("+${trimNum(step)}") }
            }
        } else {
            OutlinedTextField(
                value = value,
                onValueChange = onValue,
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (presets.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                presets.forEach { p ->
                    // Picking a preset is a complete choice — apply it and collapse.
                    FilterChip(selected = value == p, onClick = { onValue(p); onClose() }, label = { Text(p) })
                }
            }
        }
    }
}

/**
 * Read-only symbolic structure line shown above the filled equation (iOS:
 * CustomFilmFormulaSymbolicLine). Maps token-for-token onto the value row so
 * the photographer always knows which chip is p, which is b, etc.
 */
@Composable
internal fun FormulaTemplate() {
    Text(
        buildAnnotatedString {
            append("Tc = Tc₀ × (Tm / Tm₀)")
            withStyle(SpanStyle(baselineShift = BaselineShift.Superscript, fontSize = 9.sp)) { append("p") }
            append(" + b")
        },
        style = MaterialTheme.typography.bodyMedium,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

/** Tall, light parenthesis bracketing the Tm/Tm₀ fraction (iOS: 30pt light). */
@Composable
internal fun Paren(text: String) {
    Text(
        text,
        fontSize = 32.sp,
        fontWeight = FontWeight.Light,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

/** Concept definitions toggled by the (i) button (iOS help-panel wording). */
@Composable
internal fun FormulaHelpPanel() {
    val lines = listOf(
        "Tc₀ — corrected exposure at the metered anchor.",
        "Tm₀ — metered exposure used as the anchor.",
        "p — curve strength; higher gives stronger correction at long exposures.",
        "b — fixed time added after the curve.",
        "No correction — Tm at or below this value stays unchanged.",
        "Source data — results past this value read as beyond source range.",
    )
    Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        lines.forEach {
            Text(
                "•  $it",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Static monospace token in the inline equation. */
@Composable
internal fun EquationText(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurface,
    )
}

/**
 * Tappable value pill embedded in the equation; accent-tinted, with a thin
 * border that strengthens while the pill is being edited (iOS pill style).
 */
@Composable
internal fun FormulaChip(value: String, selected: Boolean, compact: Boolean = false, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = if (selected) 0.28f else 0.12f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(
            if (selected) 1.dp else 0.5.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = if (selected) 0.9f else 0.3f),
        ),
    ) {
        Text(
            value,
            // The exponent renders compact so it reads as a raised superscript
            // rather than a full-size term.
            style = if (compact) MaterialTheme.typography.labelMedium else MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(
                horizontal = if (compact) 5.dp else 7.dp,
                vertical = if (compact) 2.dp else 3.dp,
            ),
        )
    }
}

/** Label + inline editor shown under the equation for the tapped chip. */
@Composable
internal fun FormulaValuePanel(label: String, content: @Composable () -> Unit) {
    Spacer(Modifier.height(12.dp))
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(4.dp))
    content()
}

/** Adds [delta] to a numeric string, formatted without trailing zeros. */
internal fun adjustValue(value: String, delta: Double): String =
    trimNum((value.trim().toDoubleOrNull() ?: 0.0) + delta)

internal fun trimNum(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString()
    else (Math.round(value * 100.0) / 100.0).toString()

/**
 * Normalizes a duration row's displayed value: a bare number gains an "s"
 * (0.5 → 0.5s), "unlimited" any-case reads "Unlimited", and unit-bearing text
 * (5m, 1h) is shown as typed — so No correction / Source data read consistently.
 */
internal fun durationRowLabel(raw: String): String {
    val t = raw.trim()
    if (t.equals("unlimited", ignoreCase = true)) return "Unlimited"
    return t.toDoubleOrNull()?.let { "${trimNum(it)}s" } ?: t
}

/** Live editor title derived from the in-progress maker/label/ISO (iOS header). */
@Composable
internal fun CustomFilmTitle(manufacturer: String, label: String, iso: String) {
    val name = listOf(manufacturer.trim(), label.trim()).filter { it.isNotEmpty() }.joinToString(" ")
    val isoText = iso.trim().toIntOrNull()?.let { " · ISO $it" } ?: ""
    Text(
        if (name.isEmpty()) "New custom film" else "$name$isoText",
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.Bold,
    )
    Spacer(Modifier.height(12.dp))
}

/** Section label above a grouped editor card (iOS groups fields under headers). */
@Composable
internal fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(bottom = 6.dp),
    )
}

/** Card grouping a set of editor fields, matching iOS's grouped-list look. */
@Composable
internal fun FormCard(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp), content = content)
    }
}
