// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// Shooting Filters (FILTER-FLOW-002..005, FILTER-SET-001,
/// FILTER-CAMERA-003, FILTER-AUX-003/006/007): auxiliary filters only;
/// ND stays on Main. One working session covers the Filter Sets selected
/// for the active camera and the auxiliary selection — mounting, CPL
/// choices, GND modes; Apply commits both atomically while Cancel
/// discards both. From the top: a fixed-height Selected filters panel
/// with the count, the exposure reduction, and every selected filter;
/// the read-only Standard row, always selected, then the Selected Sets,
/// each with its auxiliary filters in one strip below it; the Available
/// Sets, by name; then Add filter and Add Filter Set, and apart from them
/// the secondary Add Example Filter Sets. A Selected Set is removed at its leading control, edited
/// from its name, and gets a new filter from its trailing control — or,
/// while it holds no filter, from a full-width Add Filter row. An
/// Available Set is edited from its name and added at its trailing
/// control. There is no manual reorder.
struct ShootingFilterSelectionView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let onDismiss: () -> Void

    /// The working Filter Set selection and auxiliary selection,
    /// initialized from this camera's committed state (FILTER-AUX-003,
    /// FILTER-CAMERA-003). Nothing changes until Apply.
    @State private var session: ShootingFiltersSession
    @State private var applyRejection: FilterStackRejection?
    @State private var editingItem: FilterItemEditorContext?
    /// This popup's New Filter session memory (FILTER-ITEM-007).
    @State private var editorSession = FilterItemEditorSessionMemory()
    @State private var creationDraft: FilterSetDraft?
    @State private var editedFilterSetID: FilterSetID?
    /// Each strip's scroll position, kept while the list redraws.
    @State private var stripPositions: [FilterSetID: FilterItemID] = [:]
    /// The Selected filters list's height under a one-line count: three
    /// rows and part of a fourth, so a fourth selected filter shows that
    /// the list scrolls.
    @ScaledMetric(relativeTo: .footnote) private var selectedListHeight: CGFloat = 90
    /// The height of a one-line count and reduction above the list.
    @ScaledMetric(relativeTo: .headline) private var selectedHeaderHeight: CGFloat = 22
    /// The height the panel gives a refusal reason, taken from its list
    /// so the panel never grows.
    @ScaledMetric(relativeTo: .footnote) private var refusalRowHeight: CGFloat = 22
    /// Why the last mount or choice was refused; the working selection
    /// stayed as it was (FILTER-AUX-007). Cleared by the next accepted
    /// change.
    @State private var refusal: FilterStackRejection?

    init(viewModel: ExposureCalculatorViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _session = State(initialValue: ShootingFiltersSession(
            committedFilterSetIDs: viewModel.candidateFilterSetIDs,
            committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount)
        ))
    }

    /// The camera's committed Filter Set selection and mounts. Mount
    /// order never matters.
    private var committed: CommittedState {
        CommittedState(
            filterSetIDs: viewModel.candidateFilterSetIDs,
            mounts: Set(viewModel.mountedAuxiliaryFilters.map(\.mount))
        )
    }

    private struct CommittedState: Equatable {
        let filterSetIDs: [FilterSetID]
        let mounts: Set<MountedAuxiliaryFilter>
    }

    private var preview: Result<NDStep, FilterStackRejection> {
        viewModel.shootingFiltersPreview(selectedFilterSetIDs: session.selectedFilterSetIDs, mounts: session.mounts)
    }

    private var canApply: Bool {
        guard session.hasChanges, case .success = preview else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            List {
                selectedFiltersSection
                selectedSetSections
                availableSetSection
                Section {
                    // Filter-first registration, never attached to Standard
                    // (FILTER-FLOW-004, FILTER-ITEM-009).
                    Button {
                        editingItem = .general(
                            initialUnit: editorSession.initialUnit,
                            proposedFilterSetColor: viewModel.suggestFilterSetCreationColor()
                        )
                    } label: {
                        Label("Add filter", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("shooting-filters-add-filter-button")
                    Button {
                        creationDraft = FilterSetDraft(name: "", color: viewModel.suggestFilterSetCreationColor())
                    } label: {
                        Label("Add Filter Set", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("shooting-filters-add-filter-set-button")
                }
                Section {
                    // Fresh, unselected copies of the example Filter Sets
                    // (FILTER-SET-008): a secondary action in its own
                    // section, apart from the ordinary creation actions.
                    Button {
                        viewModel.addExampleFilterSets()
                    } label: {
                        Label("Add Example Filter Sets", systemImage: "square.stack.3d.up")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shooting-filters-add-example-filter-sets-button")
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 40)
            .navigationTitle("Shooting filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .accessibilityIdentifier("shooting-filters-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .disabled(!canApply)
                        .accessibilityIdentifier("shooting-filters-apply-button")
                }
            }
            .alert(
                Text("Cannot apply"),
                isPresented: Binding(
                    get: { applyRejection != nil },
                    set: { if !$0 { applyRejection = nil } }
                ),
                presenting: applyRejection
            ) { _ in
                Button("OK", role: .cancel) { applyRejection = nil }
            } message: { rejection in
                Text(FilterWheelPresenter.rejectionText(for: rejection))
            }
            .sheet(item: $editingItem) { context in
                FilterItemEditorView(
                    viewModel: viewModel,
                    context: context,
                    onSaved: { item in
                        editorSession.didSaveNewItem(item)
                    },
                    onDismiss: { editingItem = nil }
                )
            }
            // Add Filter Set adds the set to the inventory and returns
            // here; it selects and mounts nothing (FILTER-FLOW-005).
            .sheet(item: $creationDraft) { draft in
                FilterSetEditorSheet(
                    draft: draft,
                    onSave: { saved in
                        viewModel.createFilterSet(name: saved.name, color: saved.color)
                        creationDraft = nil
                    },
                    onCancel: { creationDraft = nil }
                )
            }
            .navigationDestination(item: $editedFilterSetID) { filterSetID in
                FilterSetDetailView(viewModel: viewModel, filterSetID: filterSetID)
            }
        }
        // The committed state can change underneath the popup through an
        // inventory edit made from here, which is immediate — an item's
        // kind corrected or moved, or a set deleted, in a Filter Set
        // editor (FILTER-FLOW-003, FILTER-ITEM-005/009). The working
        // mounts follow that edit item by item, so Apply can never undo
        // it with a stale selection and unrelated draft picks stay. The
        // same edits can touch only working picks, which the camera never
        // committed. The session decides both; the two handlers may run in
        // either order.
        .onChange(of: committed) { _, _ in followCommittedState() }
        .onChange(of: viewModel.filterInventory) { _, _ in followCommittedState() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Selected filters (FILTER-FLOW-003, FILTER-AUX-007)

    /// A fixed-height panel, so the Selected Sets never move as filters
    /// are picked: the count of selected auxiliary filters (a Record-only
    /// GND counts; ND wheels never do) and the exposure reduction on one
    /// line, then every selected filter in a list that scrolls inside the
    /// panel. The whole Total is not shown here: it includes ND wheels,
    /// which stay on Main. A refused mount or choice shows its reason in
    /// one row taken from the list, never in place of the count or the
    /// reduction (FILTER-AUX-007).
    private var selectedFiltersSection: some View {
        let rows = viewModel.selectedFilterRows(session.mounts)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    countText(rows.count)
                        .font(.headline)
                        .monospacedDigit()
                        .accessibilityIdentifier("shooting-filters-selected-count")
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Exposure reduction")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(FilterWheelPresenter.stopsText(viewModel.auxiliaryFiltersSubtotal(session.mounts)))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("shooting-filters-auxiliary-subtotal")
                }
                Divider()
                if let reason = shownRejection {
                    Label(FilterWheelPresenter.rejectionText(for: reason), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(height: refusalRowHeight)
                        .accessibilityIdentifier("shooting-filters-rejection")
                }
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            SelectedFilterRow(row: row)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicatorsFlash(trigger: rows.count)
                .accessibilityIdentifier("shooting-filters-selected-filters")
            }
            // A count or reduction that wraps takes its line from the
            // list, so the panel keeps one height in every language.
            .frame(height: selectedHeaderHeight + 9 + selectedListHeight, alignment: .top)
        }
    }

    /// The last refusal, or why the working state could not be applied —
    /// a removed set added back with picks that no longer fit.
    private var shownRejection: FilterStackRejection? {
        if let refusal {
            return refusal
        }
        if case .failure(let rejection) = preview {
            return rejection
        }
        return nil
    }

    /// `3 auxiliary filters`, or the explicit zero state, which is not
    /// an error (FILTER-FLOW-003).
    private func countText(_ count: Int) -> Text {
        switch count {
        case 0: return Text("No auxiliary filters selected")
        case 1: return Text("1 auxiliary filter")
        default: return Text("\(count) auxiliary filters")
        }
    }

    // MARK: Selected Sets (FILTER-SET-001, FILTER-CAMERA-003)

    /// The Selected Sets grouped by their contents — ND-only, ND and
    /// auxiliary, auxiliary-only, empty — each group in selection order,
    /// laid out continuously in one section: each set's one-line header, then its auxiliary filters in
    /// one indented horizontal strip, or one Add Filter row while the set
    /// holds no filter. Picking a filter never changes a set's height. A
    /// removed set's working picks are kept for the session.
    private var selectedSetSections: some View {
        let selected = viewModel.displayedSelectedFilterSets(session.selectedFilterSetIDs)
        return Section {
            // Standard first, always selected and read-only; with no user
            // Set selected it is the whole section, a normal state
            // (FILTER-SET-007, FILTER-FLOW-003).
            NavigationLink {
                StandardNDListView()
            } label: {
                StandardFilterSourceLabel(showsSelectedCue: true)
                    .font(.subheadline.weight(.semibold))
            }
            .listRowInsets(compactRowInsets)
            .accessibilityIdentifier("shooting-filters-standard")
            ForEach(selected) { filterSet in
                let placement = SelectedFilterSetAddFilterPlacement(for: filterSet)
                SelectedFilterSetRow(
                    filterSet: filterSet,
                    isInUse: viewModel.filterSetIDsReferencedByActiveCamera.contains(filterSet.id),
                    onRemove: {
                        session.setSelected(filterSet.id, false)
                        refusal = nil
                    },
                    onEdit: { editedFilterSetID = filterSet.id },
                    onAddFilter: placement == .headerControl ? { addFilter(to: filterSet.id) } : nil
                )
                if placement == .fullWidthRow {
                    Button {
                        addFilter(to: filterSet.id)
                    } label: {
                        Label("Add filter", systemImage: "plus.circle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    }
                    .listRowInsets(compactRowInsets)
                    .accessibilityIdentifier("shooting-filters-empty-set-add-filter-\(filterSet.id.rawValue)")
                }
                let items = FilterSetItemOrder.ordered(filterSet.auxiliaryItems)
                if !items.isEmpty {
                    filterItemStrip(items, of: filterSet)
                }
            }
        } header: {
            // A passive instruction directly below the title: ND values
            // are chosen on Main (FILTER-FLOW-003). It is not an action.
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected Filter Sets")
                // An explicit label color: a header already dims its
                // content, and a further hierarchical level is too faint.
                Text("Select ND filters on the main screen.")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shooting-filters-nd-on-main")
            }
        }
    }

    /// One set's filters in an indented strip that scrolls freely on its
    /// own, without snapping (FILTER-AUX-006, FILTER-FLOW-003); its
    /// position survives redraws. Every control has the same width:
    /// three tenths of the strip, so three whole controls and part of
    /// the next show at once. A strip with a GND reserves two lines in
    /// every bottom row, so its whole mode name fits and the set keeps
    /// one height whatever is mounted.
    private func filterItemStrip(_ items: [FilterItem], of filterSet: FilterSet) -> some View {
        let bottomLineCount = items.contains { $0.behavior.kind == .gnd } ? 2 : 1
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: stripSpacing) {
                ForEach(items) { item in
                    FilterItemStripControl(
                        item: item,
                        filterSetID: filterSet.id,
                        bottomLineCount: bottomLineCount,
                        mount: binding(for: item)
                    )
                    .containerRelativeFrame(.horizontal, count: 10, span: 3, spacing: stripSpacing)
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
            .padding(.trailing, 12)
        }
        .scrollPosition(id: Binding(
            get: { stripPositions[filterSet.id] },
            set: { stripPositions[filterSet.id] = $0 }
        ), anchor: .leading)
        .listRowInsets(stripRowInsets)
        .accessibilityIdentifier("shooting-filters-strip-\(filterSet.id.rawValue)")
    }

    private func addFilter(to filterSetID: FilterSetID) {
        editingItem = FilterItemEditorContext(
            filterSetID: filterSetID,
            item: nil,
            initialUnit: editorSession.initialUnit
        )
    }

    // MARK: Available Sets (FILTER-SET-001/004)

    @ViewBuilder
    private var availableSetSection: some View {
        let available = viewModel.availableFilterSets(excluding: session.selectedFilterSetIDs)
        if !available.isEmpty {
            Section {
                ForEach(available) { filterSet in
                    AvailableFilterSetRow(
                        filterSet: filterSet,
                        isInUse: viewModel.filterSetIDsReferencedByActiveCamera.contains(filterSet.id),
                        onEdit: { editedFilterSetID = filterSet.id },
                        onAdd: {
                            session.setSelected(filterSet.id, true)
                            refusal = nil
                        }
                    )
                }
            } header: {
                Text("Available Filter Sets")
            }
        }
    }

    /// The working mount of `item`, or `nil` when it is not selected. A
    /// mount or choice that would make the working state invalid is
    /// refused and leaves the session as it was (FILTER-AUX-007).
    private func binding(for item: FilterItem) -> Binding<MountedAuxiliaryFilter?> {
        Binding(
            get: { session.mount(of: item.id) },
            set: { mount in
                switch viewModel.shootingFiltersSession(session, settingMount: mount, for: item.id) {
                case .success(let next):
                    session = next
                    refusal = nil
                case .failure(let rejection):
                    refusal = rejection
                }
            }
        )
    }

    private func followCommittedState() {
        session.follow(
            committedFilterSetIDs: viewModel.candidateFilterSetIDs,
            committedMounts: viewModel.mountedAuxiliaryFilters.map(\.mount),
            inventory: viewModel.filterInventory
        )
    }

    /// Commits the set selection and the mounts together; a set left
    /// out takes its filters and ND wheels off this camera, with no
    /// further confirmation (FILTER-CAMERA-003).
    private func apply() {
        if let rejection = viewModel.applyShootingFilters(
            selectedFilterSetIDs: session.selectedFilterSetIDs,
            mounts: session.mounts
        ) {
            applyRejection = rejection
        } else {
            onDismiss()
        }
    }
}

/// The insets of every compact Shooting Filters row: each row stays at
/// least 44 points tall, so it is still a full touch target.
private let compactRowInsets = EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 12)

/// The insets of a set's filter strip: indented from the set header so
/// the set that owns it reads at once.
private let stripRowInsets = EdgeInsets(top: 4, leading: 44, bottom: 4, trailing: 0)

/// The gap between two controls of a strip.
private let stripSpacing: CGFloat = 6

/// A Filter Set's color and name on one line, with an inline In use
/// while this camera mounts a filter or ND wheel from it
/// (FILTER-SET-001) and, for a Selected Set with ND filters, a passive ND
/// cue (FILTER-FLOW-003); tapping it opens the set's editor.
private struct FilterSetEditLabel: View {
    let filterSet: FilterSet
    let isInUse: Bool
    var showsNDCue = false
    /// An Available Set's passive contents hint, read below its name.
    var contentsHint: String?
    let onEdit: () -> Void

    /// `Edit 72mm Kit, ND Filter, In use`.
    private var accessibilityText: String {
        var parts = [String(localized: "Edit \(filterSet.name)")]
        if showsNDCue {
            parts.append(String(localized: "ND Filter"))
        }
        if isInUse {
            parts.append(String(localized: "In use"))
        }
        if let contentsHint {
            parts.append(contentsHint)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 8) {
                FilterSetColorSwatch(color: filterSet.color, size: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text(filterSet.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let contentsHint {
                        Text(contentsHint)
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shooting-filters-available-set-contents-\(filterSet.id.rawValue)")
                    }
                }
                if showsNDCue {
                    Text("ND")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
                }
                if isInUse {
                    Text("In use")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityIdentifier("shooting-filters-set-edit-\(filterSet.id.rawValue)")
    }
}

/// A Selected Set's one-line header (FILTER-SET-001): the leading
/// control removes it from the working selection, the color and name open
/// its editor, and the trailing control — only while the set holds a
/// filter — adds a new filter to it.
private struct SelectedFilterSetRow: View {
    let filterSet: FilterSet
    let isInUse: Bool
    let onRemove: () -> Void
    let onEdit: () -> Void
    /// `nil` hides the trailing control; an empty set shows an Add Filter
    /// row instead.
    let onAddFilter: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .frame(minWidth: 28, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove \(filterSet.name)"))
            .accessibilityIdentifier("shooting-filters-selected-set-remove-\(filterSet.id.rawValue)")

            FilterSetEditLabel(filterSet: filterSet, isInUse: isInUse, showsNDCue: filterSet.showsNDCue, onEdit: onEdit)
                .font(.subheadline.weight(.semibold))

            if let onAddFilter {
                Button(action: onAddFilter) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Add filter to \(filterSet.name)"))
                .accessibilityIdentifier("shooting-filters-set-add-filter-\(filterSet.id.rawValue)")
            }
        }
        .listRowInsets(compactRowInsets)
    }
}

/// An Available Set's compact row (FILTER-SET-001): the color and name
/// open its editor, a passive hint below the name tells what the set
/// holds, and the trailing control adds it to the Selected Sets.
private struct AvailableFilterSetRow: View {
    let filterSet: FilterSet
    let isInUse: Bool
    let onEdit: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FilterSetEditLabel(
                filterSet: filterSet,
                isInUse: isInUse,
                contentsHint: FilterSetContentsHint.text(of: filterSet),
                onEdit: onEdit
            )
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .frame(minWidth: 40, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Add \(filterSet.name) to Selected Filter Sets"))
            .accessibilityIdentifier("shooting-filters-available-set-add-\(filterSet.id.rawValue)")
        }
        .listRowInsets(compactRowInsets)
    }
}

/// One selected filter in the Selected filters panel: the color swatch
/// of a Color filter, the whole name (truncated only when it does not
/// fit), the type, and the contribution or GND mode. Informational only.
private struct SelectedFilterRow: View {
    let row: SelectedFilterRowDisplayState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(row.opticalColor.map(Color.filterSet) ?? Color.clear)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(row.kindLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(row.valueText)
                .monospacedDigit()
                .fixedSize()
        }
        .font(.footnote)
        .frame(minHeight: 25)
        .accessibilityElement(children: .combine)
    }
}

/// A supplementary type cue beside a filter's type text
/// (FILTER-FLOW-007): a ring for CPL, a graduated filter for GND, and
/// sparkles for Effect. Decorative — the type text is what VoiceOver reads.
private struct FilterKindIcon: View {
    let kind: FilterItemKind

    private var systemName: String? {
        switch kind {
        case .cpl: return "circle.circle"
        case .gnd: return "square.tophalf.filled"
        case .effect: return "sparkles"
        case .fixed, .color: return nil
        }
    }

    var body: some View {
        if let systemName {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
        }
    }
}

/// One auxiliary item of a set's strip (FILTER-AUX-006,
/// FILTER-CPL-005, FILTER-GND-001/002/003): an equal-width control whose
/// upper part mounts or unmounts the item — a check while mounted and a
/// plus while not, so the state does not rest on color — and shows the
/// type apart from the name, which may wrap to two lines. The bottom
/// row of a mounted CPL or GND opens its exposure loss or calculation
/// mode directly without unmounting it; on every other control it
/// shows the registered value, so all controls keep one height.
private struct FilterItemStripControl: View {
    let item: FilterItem
    /// The set the item belongs to, which a fresh mount names.
    let filterSetID: FilterSetID
    /// The lines the bottom row reserves, the same for every control of
    /// a strip.
    let bottomLineCount: Int
    @Binding var mount: MountedAuxiliaryFilter?

    private var isMounted: Bool { mount != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: isMounted ? "checkmark.circle.fill" : "plus.circle")
                            .font(.footnote.weight(.semibold))
                        Text(FilterWheelPresenter.kindName(item.behavior.kind))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        FilterKindIcon(kind: item.behavior.kind)
                        if let color = item.behavior.opticalColor {
                            Circle()
                                .fill(Color.filterSet(color))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                    // The whole name in up to two lines; a long one shrinks a
                    // little before it is truncated.
                    Text(item.name)
                        .font(.footnote.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(item.name), \(registeredDetail(of: item))"))
            .accessibilityAddTraits(isMounted ? [.isSelected] : [])
            .accessibilityIdentifier("auxiliary-item-toggle-\(item.id.rawValue)")

            Rectangle()
                .fill(isMounted ? Color.white.opacity(0.4) : Color(.separator))
                .frame(height: 0.5)
                .accessibilityHidden(true)
            bottomRow
                .font(.caption)
                .lineLimit(bottomLineCount, reservesSpace: true)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .foregroundStyle(isMounted ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 10).fill(isMounted ? Color.accentColor : Color(.tertiarySystemFill)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isMounted ? Color.clear : Color(.separator), lineWidth: 0.5))
    }

    /// A mounted CPL's or GND's choice menu; otherwise the registered
    /// value as plain text.
    @ViewBuilder
    private var bottomRow: some View {
        switch (item.behavior, mount?.choice) {
        case (.cpl(let choices), .cplLoss(let loss)?):
            Menu {
                Picker("Exposure loss", selection: Binding(
                    get: { loss },
                    set: { mount = MountedAuxiliaryFilter(filterSetID: filterSetID, itemID: item.id, choice: .cplLoss($0)) }
                )) {
                    ForEach(choices.shootingChoices, id: \.self) { choice in
                        Text(FilterWheelPresenter.stopsText(choice)).tag(choice)
                    }
                }
            } label: {
                menuLabel(FilterWheelPresenter.stopsText(loss))
            }
            .accessibilityLabel(Text("Exposure loss, \(FilterWheelPresenter.stopsText(loss))"))
            .accessibilityIdentifier("auxiliary-item-cpl-choice-\(item.id.rawValue)")
        case (.gnd(let value), .gnd(let mode)?):
            // Either mode is an immediate, reversible working change; no
            // confirmation (FILTER-GND-003).
            Menu {
                Picker("Calculation mode", selection: Binding(
                    get: { mode },
                    set: { mount = MountedAuxiliaryFilter(filterSetID: filterSetID, itemID: item.id, choice: .gnd($0)) }
                )) {
                    ForEach(GNDCalculationMode.allCases, id: \.self) { choice in
                        let stops = choice == .applyFullValue ? value.canonicalStops ?? 0 : 0
                        Text(verbatim: "\(FilterWheelPresenter.gndModeName(choice)) · \(FilterWheelPresenter.stopsText(stops))")
                            .tag(choice)
                    }
                }
            } label: {
                menuLabel(FilterWheelPresenter.gndModeName(mode))
            }
            .accessibilityLabel(Text("Calculation mode, \(FilterWheelPresenter.gndModeName(mode))"))
            .accessibilityIdentifier("auxiliary-item-gnd-mode-\(item.id.rawValue)")
        default:
            Text(registeredValue)
                .monospacedDigit()
                .foregroundStyle(isMounted ? Color.white.opacity(0.85) : Color.secondary)
        }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .contentShape(Rectangle())
    }

    /// An unmounted CPL shows its configured losses, a GND its registered
    /// value, Color and Effect their loss.
    private var registeredValue: String {
        switch item.behavior {
        case .cpl(let choices):
            return choices.shootingChoices.map(FilterWheelPresenter.decimalStopsValue).joined(separator: " / ")
        case .gnd(let value), .fixed(let value):
            return FilterWheelPresenter.registeredValueText(value)
        case .color(let loss, _), .effect(let loss):
            return FilterWheelPresenter.stopsText(loss.stops)
        }
    }

    private func toggle() {
        if mount == nil {
            mount = MountedAuxiliaryFilter(
                filterSetID: filterSetID,
                itemID: item.id,
                choice: MountedAuxiliaryFilter.initialChoice(for: item) ?? .registeredLoss
            )
        } else {
            mount = nil
        }
    }
}

/// `CPL · 1 / 1.5 / 2 stops`, `GND · OD 0.9 · 3 stops`, `Color · Red ·
/// 2 stops`, `Effect · 0.5 stops` — the registered definition, spoken
/// with the control, so a GND's density is read as density, not as its
/// contribution.
private func registeredDetail(of item: FilterItem) -> String {
    let kind = FilterWheelPresenter.kindName(item.behavior.kind)
    switch item.behavior {
    case .cpl(let choices):
        let list = choices.shootingChoices.map(FilterWheelPresenter.decimalStopsValue).joined(separator: " / ")
        return "\(kind) · \(list) \(String(localized: "stops"))"
    case .gnd(let value), .fixed(let value):
        var text = "\(kind) · \(FilterWheelPresenter.registeredValueText(value))"
        if value.unit != .stops, let stops = value.canonicalStops {
            text += " · \(FilterWheelPresenter.stopsText(stops))"
        }
        return text
    case .color, .effect:
        return "\(kind) · \(FilterWheelPresenter.auxiliaryLossDetailText(for: item.behavior) ?? "")"
    }
}
