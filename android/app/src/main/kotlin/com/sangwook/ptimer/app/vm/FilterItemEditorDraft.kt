// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterDecimalInput
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterValueUnit

/**
 * What the physical-filter editor currently holds, as a pure value
 * (FILTER-ITEM-002/003/004, FILTER-CPL-001/002). The composable owns the
 * text fields; every validation question — is the value registerable, may
 * Save fire, which CPL field is wrong — is answered here so the rules
 * stay testable without a UI and read the same in both editor kinds.
 *
 * Errors are reported structurally; the display layer turns them into
 * localized messages (Android canonical-vocabulary rule).
 */
data class FilterItemEditorDraft(
    val name: String = "",
    /** Every new item starts Fixed, whatever the session remembered. */
    val kind: FilterItemKind = FilterItemKind.fixed,
    /** Fixed / GND registered value as typed; `,` and `.` both parse. */
    val valueText: String = "",
    val unit: FilterValueUnit = FilterValueUnit.stops,
    /** The three CPL exposure-loss fields as typed; blank omits a choice. */
    val cplTexts: List<String> = DEFAULT_CPL_TEXTS,
) {
    val trimmedName: String get() = name.trim()

    /** The registered value, or `null` when it cannot be registered. */
    val registeredValue: FilterRegisteredValue?
        get() = FilterDecimalInput.parseDecimal(valueText)
            ?.let { FilterRegisteredValue(it, unit) }
            ?.takeIf { it.isValid }

    /** Canonical stops of [registeredValue] for the live conversion line. */
    val canonicalStops: Double? get() = registeredValue?.canonicalStops

    /** True once the user typed something that cannot be registered —
     *  an untouched empty field is not yet an error. */
    val hasValueError: Boolean
        get() = kind != FilterItemKind.cpl &&
            valueText.isNotBlank() &&
            registeredValue == null

    private val cplParses: List<FilterDecimalInput.CplFieldParse>
        get() = cplTexts.map { FilterDecimalInput.parseCplField(it) }

    /** Per-field "this text is not a usable choice" flags. */
    val cplFieldErrors: List<Boolean>
        get() = cplParses.map { it is FilterDecimalInput.CplFieldParse.Invalid }

    /** True when every field is blank — at least one choice is required. */
    val cplIsEmpty: Boolean
        get() = cplParses.all { it is FilterDecimalInput.CplFieldParse.Empty }

    private val cplChoices: CplExposureLossChoices?
        get() {
            val fields = cplParses.map { parse ->
                when (parse) {
                    is FilterDecimalInput.CplFieldParse.Empty -> null
                    is FilterDecimalInput.CplFieldParse.Value -> parse.stops
                    is FilterDecimalInput.CplFieldParse.Invalid -> return null
                }
            }
            return CplExposureLossChoices(fields).takeIf { it.isValid }
        }

    /** The behavior this draft would save, or `null` while invalid. */
    fun behavior(): FilterItemBehavior? = when (kind) {
        FilterItemKind.fixed -> registeredValue?.let { FilterItemBehavior.Fixed(it) }
        FilterItemKind.gnd -> registeredValue?.let { FilterItemBehavior.Gnd(it) }
        FilterItemKind.cpl -> cplChoices?.let { FilterItemBehavior.Cpl(it) }
    }

    val canSave: Boolean get() = trimmedName.isNotEmpty() && behavior() != null

    companion object {
        /** New CPL items start at 1 / 1.5 / 2 stops (FILTER-CPL-001). */
        val DEFAULT_CPL_TEXTS: List<String> =
            CplExposureLossChoices.defaults.fields.map { field ->
                field?.let { FilterWheelPresenter.trimmedNumber(it) } ?: ""
            }

        /** Draft for an existing item; a non-CPL item keeps the CPL
         *  defaults so switching kind mid-edit starts from 1 / 1.5 / 2. */
        fun editing(name: String, behavior: FilterItemBehavior): FilterItemEditorDraft = when (behavior) {
            is FilterItemBehavior.Fixed -> FilterItemEditorDraft(
                name = name,
                kind = FilterItemKind.fixed,
                valueText = FilterWheelPresenter.trimmedNumber(behavior.value.value),
                unit = behavior.value.unit,
            )

            is FilterItemBehavior.Gnd -> FilterItemEditorDraft(
                name = name,
                kind = FilterItemKind.gnd,
                valueText = FilterWheelPresenter.trimmedNumber(behavior.value.value),
                unit = behavior.value.unit,
            )

            is FilterItemBehavior.Cpl -> FilterItemEditorDraft(
                name = name,
                kind = FilterItemKind.cpl,
                cplTexts = behavior.choices.fields.map { field ->
                    field?.let { FilterWheelPresenter.trimmedNumber(it) } ?: ""
                },
            )
        }
    }
}
