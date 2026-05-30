# UI Spec

**Domain**: User-facing surfaces — calculator screen, bottom-sheet timer workspace, film picker sheet, reciprocity details sheet, lock-screen widget.

This document is a behavior contract for what the user sees and how they interact. It describes display contract (what is rendered) and interaction contract (what happens on user input). Visual styling parameters that are platform-default are not pinned; numbers are pinned only where intent requires a specific value.

---

## 1. Global presentation

### 1.1 Orientation

The app runs in **portrait only**. Orientation is enforced at the app entry point; views shall not opt out of this constraint.

### 1.2 Single primary screen

There shall be **one primary screen** that hosts both calculation and timer execution. The user adjusts exposure and starts a timer without screen transitions. Calculator and timer are not separated workflows. (Wiki 3866625)

### 1.3 Layout density tiers

The screen adapts to vertical room without changing structure. Three density tiers shall be supported:

- **Regular** — standard spacing, font sizes, and padding.
- **Compact** — reduced spacing on shorter viewports; structure unchanged.
- **Dense** — minimum padding so the calculator footprint stays stable on the smallest viewports the app supports.

Tier selection is a function of available height; the structure (sections, picker pair, result, dock) shall not collapse or rearrange across tiers.

---

## 2. Calculator section

### 2.1 Header / mode strip

Above the variable section sits a film row that conveys current workflow mode:

- **No film selected (digital workflow)** — the row presents an empty-state label and a "Choose Film" affordance.
- **Film selected (film workflow)** — the row presents the selected film's canonical name plus brand, a "Change" affordance, and a "Clear" affordance.

When a film is selected, the row shall also carry an **explicit profile-authority subtitle** matching the active reciprocity profile's authority: **"Official guidance"** for an official-authority profile, **"Unofficial practical"** for an unofficial-authority profile, **"Custom"** for a user-defined custom profile. The label shall be present for every supported authority — there is no implicit "missing label means official" interpretation.

The launch catalog ships only `authority = "official"` primary profiles ([DomainSchema Spec](DomainSchema.md) §13), so every shipped launch profile renders the **"Official guidance"** subtitle. Supplementary unofficial-practical profiles (DomainSchema §13.3) are bundled outside the launch catalog as secondary alternatives on a film identity; when one is the active profile, the subtitle reads **"Unofficial practical"**. Photographer-authored custom profiles (DomainSchema §13.4) carry `authority = "userDefined"` and render the **"Custom"** subtitle so a user-defined entry never reads as manufacturer-backed at a glance. `unknown` authorities have no presentation contract; the subtitle is omitted for that case only.

The "Clear" affordance shall remove the film selection without altering Base Shutter or ND. It shall not appear in the empty state.

### 2.1.1 Camera slot pager and rename

The calculator screen pages between four independent camera slots
(`Camera 1` through `Camera 4`). The active slot's name renders as
the screen's main title; the page indicator below the calculator
shows the active slot's position in the bounded set. Each slot owns
its own calculator inputs, film selection, scale, and reciprocity
result — switching slots never resets the slots not being switched.

The slot title doubles as the rename affordance. Tapping it on the
active page opens a sheet that lets the photographer:

- enter a custom name (e.g., `Hasselblad 500CM`, `Mamiya 7`); empty
  or whitespace-only input is treated as a reset request, falling
  back to the canonical `Camera N` label.
- reset a previously-renamed slot back to its canonical default
  through an explicit "Reset to Camera N" action.

The display name is a separate axis from the selected film/profile;
the rename surface shall not change calculator inputs, film
selection, scale, reciprocity result, or the slot's stable
identifier. Started timers keep the slot label captured at start
time; subsequent renames do not retroactively rewrite a running or
completed timer's identity. Custom names persist across launches
through the camera-slot session snapshot (see
[DomainSchema Spec](DomainSchema.md) §7.4).

### 2.2 Variable section

Two **wheel pickers** sit side-by-side in a single row:

- **Base Shutter picker** — the 1/3-stop densified ladder (55 entries from 1/8000 to 30 s, per [Calculator Spec](Calculator.md) §2.3) with conventional camera-facing labels. Sub-1 s rows render as reciprocal fractions (`1/N`, including the slow end `1/3, 1/2.5, 1/2, 1/1.6, 1/1.3`) and never carry an `s` suffix; rows at or above 1 s render as integer or `N.Ns` per camera convention.
- **ND picker** — **integer stops in the closed range `[0, 30]`**. One-third-stop applies to the Base Shutter ladder only ([Calculator Spec](Calculator.md) §1.4); the ND picker stays whole-stop because real-world fixed ND filters are sold in whole-stop strengths. Fractional rows such as `7 1/3` or `7 2/3` are **not** part of the shipping ND option list and shall not be filtered out at the view layer — they shall not exist in the option set at all.

A user-facing **exposure scale selector** is intentionally omitted in the current release; the calculator runs only on the one-third-stop shutter scale. A future Settings preference (Full / 1/2 / 1/3 stop, plus any future fractional-ND opt-in) is reserved (see [Calculator Spec](Calculator.md) §1.4); when it ships it will live in Settings, not in the calculator screen.

The picker pair is the only entry path for these variables; there is no free-text input. Tapping a wheel value shall update the calculator immediately; live preview during scroll is supported. Aperture and ISO controls are deferred and shall not appear in the current release.

### 2.3 Result section

The result section displays the computed exposure:

- **Digital workflow** — one primary line with the Output Shutter using the conventional notation rule from [Calculator Spec](Calculator.md) §2.4, plus a secondary line with the precise time (formatted by the time-display rules below) when meaningful.
- **Film workflow** — a fixed two-row hierarchy. The first row shows the **Adjusted Shutter** (ND-applied, pre-reciprocity). The second row shows the **Corrected Exposure**. The two-row layout shall remain stable across all reciprocity result categories.

The Corrected Exposure row shall always be visible in film workflow. Its content is determined by the reciprocity result category:

- **Quantified** (`No correction`, `Formula-derived`, or `Table-derived`, per [Calculator Spec](Calculator.md) §3.5) — show the corrected time using the same time-display rules as the Adjusted Shutter, plus a status badge.
- **Quantified with warning** (a numeric continuation outside the supported range — a formula prediction or a table-derived extrapolation; surfaces as `Beyond source range` for converted-formula and table-log-log profiles, or `Outside guidance` otherwise) — show the numeric value with a warning-toned badge so the user can tell the prediction is outside manufacturer guidance.
- **Non-quantified** (`No quantified prediction` for limited-guidance results, or `No corrected value` when the unsupported case has no numeric continuation) — show calm explanatory text in place of a number. The UI shall not fabricate a numeric value.

A **reciprocity state badge** sits with the row to convey the result category at a glance. The badge wording shall match the vocabulary above; legacy table-era wording (`Exact`, `Estimated`, `Interpolated`, `Extrapolated`, `Advisory`) shall not appear on launch preset reciprocity presentation.

### 2.4 Time-display rules

Time values follow a single hierarchy. Two display modes apply at the **day-scale** boundary:

| Range | Format |
|---|---|
| `< 1 s` | reciprocal notation when conventional (e.g. `1/30`); decimal otherwise |
| `1 s ≤ t < 60 s` | seconds with adaptive precision; integer for round values, decimals where useful |
| `60 s ≤ t < 1 h` | `MM:SS` |
| `1 h ≤ t < 1 d` | `HH:MM:SS` |
| `≥ 1 d` (precise mode) | days plus the smaller-unit remainder, e.g. `388d 08:40:32` |
| `≥ 1 d` (coarse mode) | plain day count with thousands separator, e.g. `388d`, `13,599d`, `83,602d` |

**Mode selection**: the result section's **primary corrected exposure** uses the **coarse mode** at and above 1 d so the user-facing top-level value is not dominated by sub-day noise. **Detail surfaces and timer views** use the **precise mode** at and above 1 d so secondary readers can verify exact remaining time. Sub-day ranges are unaffected.

Thousands grouping in coarse mode shall use a comma separator with grouping size 3, applied deterministically regardless of device locale.

The **calculated** value (precise) and the **notation** value (conventional) are kept distinct internally. The result section shows notation; downstream timer logic uses calculated. (See [Calculator Spec](Calculator.md) §2.4.)

### 2.5 Start Timer affordance

A **Start Timer** button is enabled iff the system has a quantified result with positive, finite duration. In film workflow, the affordance binds to the **Corrected Exposure**; when corrected is non-quantified, the affordance shall be disabled with a guidance hint, not hidden.

Tapping Start Timer creates a new timer using the current calculation snapshot and adds it to the dock. The screen shall not transition; the dock simply gains a new item.

### 2.6 Reciprocity details surface

A secondary affordance opens a **Reciprocity Details sheet** that shows reference data for the selected film: the active model (source + calculation), the formula expression or published table anchors, any manufacturer source-evidence rows, a graph visualization, and the source list. The details sheet:

- shall present the data using calm, secondary visual weight (not loud);
- shall render formulas in math-style typography;
- shall keep selector and current-result visuals quieter than the main calculator.

**Section order**: the sheet shall present sections in this order so every profile (preset official formula, official table log-log, unofficial practical, user-defined custom) reads the same shape:

1. **Header** — title plus a model subtitle naming the active model (e.g. "Official FOMA table" / "App-derived formula" / "Official guidance" / "Unofficial practical").
2. **Result card** — Adjusted Shutter, Corrected Exposure, and the reciprocity status / calculation basis for the active inputs.
3. **Reciprocity model** — a compact block: the secondary segmented model selector (shown only when the film exposes more than one model; the main screen is the primary selector) plus one-line **Source** and **Calculation** rows. It does not reintroduce a large per-film metadata table.
4. **Reciprocity Graph** — the calculation curve (guarded formula or log-log table) plus source-evidence markers when available.
5. **Source reference** — for preset profiles, any manufacturer source-evidence rows ("Source reference" / "Guidance boundary" sub-sections, source-only) and, **only for explicitly app-derived models**, a separate **App-derived comparison** block; the no-correction threshold + limited-guidance directive for limited-guidance profiles; for user-defined custom profiles, a dedicated **"Custom profile"** card carrying the photographer-supplied source kind, manufacturer / stock metadata, and reference URL when set. The custom-profile card shall not borrow manufacturer-published visual treatments.
6. **Sources** — provenance (publisher, citation, sourceVersion) when the active profile carries published source data. User-defined profiles do not synthesize a Sources section.

**Sheet height**: the sheet shall open at a stable initial height regardless of profile shape (official quantified formula, official table log-log, official limited guidance, unofficial practical formula). The initial detent shall not vary with content.

**Graph scale**: the reciprocity graph (formula or table model) shall use a stable scale tier so the reference curve does not auto-rescale tightly around the current input; the same profile and scale tier produce the same frame while only the current-result marker moves.

**Model selector labels**: the compact model selectors (the main-screen segmented control and the Details segmented control) shall show a short label per model. A profile's explicit `selectorLabel` ([DomainSchema Spec](DomainSchema.md) §3.2) is used when present; otherwise the label is derived from authority / calculation. Source-named unofficial / community / custom models should provide an explicit `selectorLabel` (e.g. "Ohzart") so the control reads the source name rather than a generic "Unofficial". The label is for compact selectors only — the full model `name` remains in the Details subtitle, the Source/Calculation summary, the Sources section, and accessibility; `selectorLabel` is never a source title or URL.

### 2.7 Target Shutter row

The Target Shutter row (see [Calculator Spec](Calculator.md) §3.6) is an optional, compact surface in the main shooting calculator. It does not replace the calculator's primary result hierarchy — Adjusted Shutter, Reciprocity status, and Corrected Exposure remain the photographer's primary read in film workflow, and the Output Shutter remains primary in digital workflow.

**Row states.** The row presents two states:

- **Inactive** — a compact status row indicating no committed target. Tapping the row opens the input sheet.
- **Active** — a compact row presenting the target duration, the stop difference against the active comparison value, and a timer-start affordance for the target. The comparison basis is not redisplayed on the row — it is determined by workflow per [Calculator Spec](Calculator.md) §3.6.

The main row shall not present a destructive `Clear` affordance or an enable/disable switch. Removal and disabling are owned by the input sheet so the main surface stays status/action oriented.

**Input sheet.** The input sheet is a draft editing surface. Mutations to the draft (enabling, disabling, picking a value) shall not affect the committed target until the user confirms.

- **Confirm** commits the draft (a positive enabled value sets the target; a disabled draft removes the target).
- **Cancel** discards the draft.
- **Sheet dismissal** (drag-to-dismiss, tap-outside, or any non-`Confirm` exit) shall behave as Cancel.

The sheet shall present a native switch that controls whether the draft target is enabled; disabling the switch shall not immediately remove the committed target. Duration entry shall offer two complementary surfaces — **Quick** (preset durations) and **Fine Tune** (h/m/s entry) — so the photographer can pick a common value quickly or dial in a custom one. The two surfaces share a single draft target; switching between them shall not destroy work done in the other.

---

## 3. Timer workspace (bottom sheet)

The dock and full timer list are projections of the same runtime source ([Timer Spec](Timer.md) §6). The workspace is a **bottom sheet** with two detents.

### 3.1 Detents

- **Compact** — a glanceable horizontal dock anchored at the bottom of the calculator screen. Calculator remains primary.
- **Large** — an expanded sheet that covers most of the screen, presenting the full timer list.

The **medium detent does not exist**; the model is strictly two-state.

### 3.2 Drag thresholds

User drag transitions between detents:

- Up-drag of approximately 92 pt from compact triggers expansion to large.
- Down-drag of approximately 64 pt from large triggers collapse to compact.

The thresholds are asymmetric: expansion is easier than collapse so an accidental upward swipe does not lose work view, and a deliberate down-swipe is required to collapse.

### 3.3 Compact dock contract

In the compact detent, the dock:

- displays each running, paused, and completed timer as a **96 × 96 pt** card in a horizontal scroll list;
- includes a **86 × 96 pt overflow card** at the end if more timers exist than fit on screen;
- uses a corner radius of approximately 22 pt and a horizontal spacing of approximately 10 pt;
- scrolls horizontally only — full-page scrolling shall not be allowed; the calculator section above shall remain pinned. (Wiki 8847362)

Each compact card shows: a primary remaining-time line (the dominant signal), a status icon, total duration, and a **multi-layered progress indicator** (see §3.5). It shall **not** show destructive actions (delete, clear). Tapping a card opens the detail / focuses it in the expanded workspace; long-press, swipe, and similar gestures are not specified.

Identity cues (e.g. a tint or badge) sit in the lower metadata area; the remaining time stays the primary visual signal.

### 3.4 Expanded (large) workspace contract

In the large detent, the workspace presents the full timer list grouped in two sections:

- **Active** — running and paused timers in LIFO-by-creation order. ([Timer Spec](Timer.md) §6)
- **Recently Completed** — completed timers in completion-time-descending order, presented behind the active group.

Each row shows: title (or fallback identity text), state, remaining and total time in a two-line hierarchy with trailing alignment, and inline action affordances (pause, resume, remove) as appropriate to state.

When the user taps a compact card or the overflow card, the workspace expands and that timer becomes focused — scrolled into view with restrained highlight. Focusing shall not mutate runtime state. The overflow tap shall focus the first hidden timer.

### 3.5 Compact progress indicator

Each compact card carries a **three-layer progress indicator** that conveys the timer's footprint at multiple time scales:

- **Bottom layer** — a 60-second cycle (sub-minute granularity).
- **Middle layer** — a 60-minute cycle (sub-hour granularity).
- **Top layer** — the original timer duration mapped within a 24-hour frame.

Visible layers are gated by total duration: short timers show only the bottom layer; longer timers progressively reveal middle and top. Bar-level animations are forbidden; only the status icon may pulse for active running.

### 3.6 Completed presentation

Completed timers shall present consistently in compact and expanded surfaces. The card label is **"Done"** in both. Original duration and completion timing remain visible as secondary metadata.

---

## 4. Film picker sheet

Film selection opens a **dedicated modal sheet** rather than an in-screen dropdown or inline list.

### 4.1 Display contract

Each row shows the film's canonical name in a flexible leading area and a compact ISO-speed capsule chip in a fixed trailing column. A checkmark slot is reserved at the trailing edge whether or not it is the currently selected film, so row positions never shift on selection change.

The sheet's affordances depend on selection state:

- Empty state ("Choose Film") — the sheet's header label uses "Choose Film" wording.
- Selected state — the header label uses "Change" wording.

A **Cancel** action exits the sheet without changing selection. A row tap **immediately applies the selection and dismisses the sheet** — no confirm step.

The sheet does not include in-list edit, sort, or filter affordances; those are deferred. The launch dataset is small enough that scroll suffices. (See [DomainSchema Spec](DomainSchema.md) §13 for launch dataset scope.)

### 4.1.1 Manufacturer grouping

The film selector supports the expanded launch preset catalog and presents preset films grouped visually by manufacturer. Each manufacturer renders as a **subtle grouped card** — a tinted rounded surface containing the manufacturer's films plus a header label — so the grouping reads as a real visual group rather than only a faint text divider between rows. The leading "No film" sentinel is rendered as a plain headerless row outside any card so it stays visually distinct from the preset groups and clears the current film selection on tap.

Photographer-authored custom profiles ([DomainSchema Spec](DomainSchema.md) §13.4) are presented in their **own group, separate from the shipped manufacturer cards**, so a user-defined entry can never visually pose as a manufacturer-published row. Each custom row carries a visible **"Custom" text badge** alongside the canonical name — the user-defined treatment must not collapse into icon or color alone — and selection of a custom row applies it on the same terms as a preset selection. The same group surfaces a **discoverable create-custom-profile affordance** so authoring a new profile is reachable from the selector without a settings detour.

The manufacturer label sits inside the card as a **subtle header pill** — a small tinted rounded label with a slightly stronger fill than the card surface itself, paired with near-primary text contrast so the label reads immediately. The pill is bold + uppercase + tracked so it remains visually subordinate to film rows by size, not by faded color. Group cards stay light overall: no per-manufacturer colors, no heavy decoration.

Within a manufacturer group, films are ordered alphabetically by canonical stock name. Manufacturer order itself is alphabetical for now unless a later explicit product sort order is introduced.

Future fold/unfold gestures may toggle the rows region of any group card without changing the underlying section data shape.

### 4.1.2 One-line row format

Film rows are one-line rows. Each row carries a left-side label and a right-side ISO speed:

- **Official primary profile:** `<Film name>` … `ISO <value>`
- **Unofficial practical profile:** `<Film name> · Unofficial` … `ISO <value>`

The qualifier `" · Unofficial"` lives on the **left** because it describes the profile, not the speed. The ISO right column is identical for an official row and its unofficial sibling, since both profiles describe the same film stock.

Unofficial profile variants stay visible. They appear as sibling rows in the same manufacturer group, adjacent to their matching official film when possible — never moved to a separate section.

The collapsed film row on the calculator screen carries an authority subtitle (`"Official guidance"` / `"Unofficial practical"`) so the user can tell which variant is active without opening the picker.

### 4.1.3 Reopen at current selection

Reopening the selector reveals the current selection. When the picker is presented with a film already selected, it scrolls to the exact selected row on appear so the user does not have to manually search the launch catalog. Manual scrolling within the picker is preserved — the auto-scroll fires once on presentation and does not interfere with subsequent gestures.

Selector row identities are stable and distinguish official from unofficial variants for the same film. An active unofficial selection lands on the unofficial row, not on the official row above it. The implementation requires that every selector row participates in the layout pass before the scroll is requested, so the view materializes its rows eagerly rather than lazily.

### 4.2 Custom profile editor

The custom profile editor is a **formula-first** sheet for authoring, editing, and reviewing a user-defined reciprocity profile. The editor renders the active formula as a single symbolic line

$$T_c = T_{c_0} \times (T_m / T_{m_0})^p + b$$

and exposes each formula term as a **tappable token** in that line. Tapping a token opens a focused per-field input surface; the preview area underneath the formula renders the resulting curve, a representative Tm→Tc table, and the calculation basis so the photographer can see the effect of an edit without leaving the editor.

The formula tokens map to the shared guarded formula fields ([DomainSchema Spec](DomainSchema.md) §5.2.1) as:

- **Tc₀** — corrected exposure at the anchor (`coefficientSeconds`).
- **Tm₀** — metered exposure at the anchor (`referenceMeteredTimeSeconds`).
- **p** — curve exponent (`exponent`).
- **b** — fixed offset added after the power term (`offsetSeconds`).

A compact range/policy block sits beneath the formula tokens and exposes the two boundaries that bound the formula's behavior:

- **No correction** — the inclusive upper bound of the no-correction band (`noCorrectionThroughSeconds`). Tm at or below this value returns the identity.
- **Source data** — the inclusive upper bound of the source / fitting confidence range (`sourceRangeThroughSeconds`). Results past this value present as **Beyond source range**; calculation continues past the boundary.

`No correction` and `Source data` are **range/policy controls**, not formula terms — they bound the formula's domain rather than appearing inside the equation.

The editor exposes two recovery affordances in the formula card:

- **Reset** — replaces the formula fields and range/policy controls with neutral starter values. Available in both the New and Edit flows.
- **Revert Changes** — restores the formula and range/policy values to the snapshot the editor was opened with. Available only in the Edit flow, where an opening snapshot exists to revert to.

**Invalid formula presentation.** When a formula state violates a parameter contract (for example, a non-positive Tc₀, a missing exponent, or a `No correction` value above `Source data`), the editor shall surface an inline explanation of the violated constraint on the offending field and shall suppress misleading preview output for that state. The editor shall not render a numeric curve, table, or status preview that suggests the invalid state would produce a usable correction.

### 4.3 Clear

The "Clear" affordance lives in the header / mode strip on the calculator screen, not in the picker sheet. Clearing is a separate operation.

---

## 5. Lock-screen widget

The lock-screen widget shows the **expected completion time** of one representative running timer. ([Timer Spec](Timer.md) §5)

- The widget refresh cadence is approximately 1 s; the displayed time updates on each refresh.
- When no timer is running, the widget shows a "no active timer" presentation rather than stale data.
- The widget surface is a Live Activity instance; the runtime drives its lifecycle (creation, update, end). The widget is read-only; user input on the widget is out of scope.

---

## 6. Forbidden patterns

The UI shall **not**:

1. Allow full-page scrolling. The calculator section is pinned; only the dock and the expanded workspace scroll.
2. Show destructive actions (delete, clear, stop) on a compact card. Destructive actions live in the expanded card or detail surface.
3. Maintain timer state inside any view component. Views are projections; the runtime is the source. ([Timer Spec](Timer.md) §7)
4. Fabricate a numeric Corrected Exposure when the reciprocity result is non-quantified. Show explanatory text in place. (See [Calculator Spec](Calculator.md) §6.)
5. Re-derive remaining time independently of the runtime.
6. Run timer mutation logic (start, pause, resume, complete) inside view-builder code paths.
7. Animate progress bars at bar level. Only status icons may animate.
8. Reorder timers inside the view layer. Ordering is decided by the runtime ([Timer Spec](Timer.md) §6).
9. Open a film selection dropdown in-screen. Selection always opens the dedicated sheet.
10. Place a Clear or enable/disable switch on the main Target Shutter row (§2.7). Those affordances live only inside the input sheet.
11. Treat Target Shutter sheet dismissal (drag-to-dismiss, tap-outside) as commit. Only `Confirm` mutates the committed Target Shutter (§2.7).

---

## 7. Drift and open questions

- **Wheel picker snap behavior.** The wheel picker model implies snap-to-grid with live preview, but the precise interaction (swipe-momentum stop point, tap-to-set vs tap-to-cycle) is not pinned in spec.
- **Film picker sort / search.** The current launch dataset is small (see [DomainSchema Spec](DomainSchema.md) §13) so a flat scrollable list is sufficient. As the dataset grows, sort and search will be needed; ordering policy is undecided.
- **Animation feel.** Detent transitions and card animations use platform-default spring parameters; no human-readable feel statement is recorded. If the feel matters, it should be specified verbally ("soft, ~300 ms, no overshoot") rather than pinned to numeric stiffness/damping.
- **Reciprocity details surface depth.** The graph component, axis ranges, and labeling rules are partially specified; a human-readable spec for axes, units, and edge cases is incomplete.
- **Empty-state copy.** Calm guidance text strings for limited-guidance / unsupported corrected exposure are not pinned in this spec; revisit when localization arrives.
- **Selection model.** No multi-select, no batch action surface. Wiki 9601025 deliberately defers this; UI accordingly exposes nothing for it.
- **Accessibility labels.** Row-specific accessibility labels exist for film-mode timer actions; a complete accessibility spec across the app is not present.
- **Lock-screen widget detail.** Beyond the contract in §5, the widget's typography, color, and layout are platform-conventional; details are not pinned.

---

## 8. Sources of intent (reference)

These are *reference material*, not normative.

**Wiki (Confluence pages cited by page id)**
- 3866625 — 화면 흐름 초안 (single screen for calculation + execution)
- 3899394 — 계산 화면 와이어프레임 초안 (screen structure)
- 3932162 — UI 인터랙션 및 컴포넌트 구조 초안 (component hierarchy, fixed/derived toggle, calculator-vs-timer separation)
- 8847362 — Floating Timer Dock UI Design (dock states, scroll independence, destructive actions)
- 8880129 — Floating Timer Dock Architecture (one-source-of-truth projection)
- 9568257 — Bottom Sheet UI 기획 초안 (compact / expanded UX)
- 9601025 — Bottom Sheet UI Architecture 설계 초안 (layer split)
- 16482307 — Film Selection and Reciprocity Calculator UI (workflow direction, terms)

