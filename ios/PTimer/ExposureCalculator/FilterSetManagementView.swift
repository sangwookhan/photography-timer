// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// Color swatch always paired with a text name somewhere in the same
/// element (color is never the only cue).
struct FilterSetColorSwatch: View {
    let color: FilterSetColor
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .fill(Color.filterSet(color))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

struct FilterSetDraft: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: FilterSetColor
}

/// Create sheet: name plus the required color. Opening it preselects
/// a random color that differs from the previous suggestion
/// (FILTER-SET-003); the user may keep or change it.
struct FilterSetEditorSheet: View {
    @State var draft: FilterSetDraft
    let onSave: (FilterSetDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Filter Set name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("filter-set-name-field")
                } header: {
                    Text("Name")
                }
                Section {
                    FilterSetColorGrid(selection: $draft.color)
                } header: {
                    Text("Color")
                } footer: {
                    Text("A color is required. Several Filter Sets may share one color.")
                }
            }
            .navigationTitle("New Filter Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("filter-set-save-button")
                }
            }
            .onAppear {
                DispatchQueue.main.async { isNameFocused = true }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        var saved = draft
        saved.name = trimmedName
        onSave(saved)
    }
}

/// Twelve-token color grid; every swatch carries its color name for
/// assistive technology and the selected one shows a check glyph.
struct FilterSetColorGrid: View {
    @Binding var selection: FilterSetColor

    // Eleven palette colors read in hue order over two rows.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(FilterSetColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.filterSet(color))
                            .frame(width: 34, height: 34)
                        if color == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.localizedName))
                .accessibilityAddTraits(color == selection ? [.isSelected] : [])
                .accessibilityIdentifier("filter-set-color-\(color.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Global Filter management (FILTER-FLOW-006), from the Settings menu:
/// the read-only Standard row first, then every Filter Set by name with
/// its contents, each opening its editor, then Add filter, Add Filter
/// Set, and Add Sample Filter Sets. It edits the shared inventory only — no camera selection,
/// mounting, or Shooting Filters here; the existing camera checks still
/// apply.
struct FilterManagementView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let onDismiss: () -> Void

    @State private var creationDraft: FilterSetDraft?
    @State private var editingItem: FilterItemEditorContext?
    /// This screen's New Filter session memory (FILTER-ITEM-007).
    @State private var editorSession = FilterItemEditorSessionMemory()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StandardNDListView()
                    } label: {
                        StandardFilterSourceLabel(showsSelectedCue: false)
                    }
                    .accessibilityIdentifier("filter-management-standard")
                    ForEach(FilterSetItemOrder.sortedByName(viewModel.filterInventory.filterSets)) { filterSet in
                        NavigationLink(value: filterSet.id) {
                            HStack(spacing: 10) {
                                FilterSetColorSwatch(color: filterSet.color, size: 11)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(filterSet.name)
                                    Text(FilterSetContentsHint.text(of: filterSet))
                                        .font(.caption)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                        }
                        .accessibilityIdentifier("filter-management-set-\(filterSet.id.rawValue)")
                    }
                }
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
                    .accessibilityIdentifier("filter-management-add-filter")
                    Button {
                        creationDraft = FilterSetDraft(name: "", color: viewModel.suggestFilterSetCreationColor())
                    } label: {
                        Label("Add Filter Set", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("filter-management-add-filter-set")
                    // Fresh, unselected copies of the Samples, at any time
                    // (FILTER-SET-008).
                    Button {
                        viewModel.addSampleFilterSets()
                    } label: {
                        Label("Add Sample Filter Sets", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("filter-management-add-sample-filter-sets")
                }
            }
            .navigationTitle("Filter management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .navigationDestination(for: FilterSetID.self) { filterSetID in
                FilterSetDetailView(viewModel: viewModel, filterSetID: filterSetID)
            }
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
        }
    }
}

/// Standard as a Set-like row (FILTER-SET-007): a built-in ND source that
/// is always available, never a user inventory Set. It has no edit or
/// removal action; a lock marks it read-only and, in Shooting Filters, a
/// check that cannot be removed marks it selected.
struct StandardFilterSourceLabel: View {
    let showsSelectedCue: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsSelectedCue {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 28, minHeight: 40)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Standard")
                    .foregroundStyle(.primary)
                Text("Built-in · Always available")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 8)
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(showsSelectedCue ? [.isSelected] : [])
    }
}

/// Standard's ND values, read-only (FILTER-SET-007, ND-001): whole stops
/// 1–30 with their OD and ND factor. Zero is no ND filter and is not
/// listed.
struct StandardNDListView: View {
    var body: some View {
        List {
            ForEach(1...ExposureScale.maximumWholeNDStops, id: \.self) { stops in
                HStack {
                    Text("\(stops) stops")
                    Spacer()
                    Text(verbatim: [
                        NDNotationFormatter.display(forStops: Double(stops), mode: .opticalDensity).inline,
                        NDNotationFormatter.display(forStops: Double(stops), mode: .filterFactor).inline,
                    ].joined(separator: " · "))
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Standard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One Filter Set: rename, recolor, and manage its physical items in
/// one list, ND first, then Color, Effect, CPL, GND, each kind by name,
/// with one Add Filter action and no manual reorder (FILTER-SET-001,
/// FILTER-ITEM-001). Every set can be deleted here, after a
/// confirmation that names it and its global effect (FILTER-SET-006).
struct FilterSetDetailView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let filterSetID: FilterSetID

    @Environment(\.dismiss) private var dismiss
    @State private var isDeletionPending = false

    @State private var nameDraft: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @State private var editingItem: FilterItemEditorContext?
    @State private var pendingItemDeletion: FilterItem?
    /// This open editing session's memory (FILTER-ITEM-007): the
    /// notation of the last saved new Fixed or GND item, offered to
    /// the next new item. It lives and dies with this detail view, so
    /// leaving the Filter Set or relaunching starts again in Stops.
    @State private var editorSession = FilterItemEditorSessionMemory()

    private var filterSet: FilterSet? {
        viewModel.filterSet(withID: filterSetID)
    }

    var body: some View {
        if let filterSet {
            Form {
                Section {
                    TextField("Filter Set name", text: $nameDraft)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFieldFocused)
                        .onSubmit(commitRename)
                        .accessibilityIdentifier("filter-set-detail-name-field")
                    FilterSetColorGrid(
                        selection: Binding(
                            get: { filterSet.color },
                            set: { viewModel.recolorFilterSet(id: filterSetID, color: $0) }
                        )
                    )
                } header: {
                    Text("Filter Set")
                } footer: {
                    Text("Renaming or recoloring never changes the set's identity or any camera's stack.")
                }

                Section {
                    let orderedItems = FilterSetItemOrder.ordered(filterSet.items)
                    if orderedItems.isEmpty {
                        Text("No filters registered yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(orderedItems) { item in
                        Button {
                            editingItem = FilterItemEditorContext(filterSetID: filterSetID, item: item)
                        } label: {
                            FilterItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("filter-item-row-\(item.id.rawValue)")
                    }
                    .onDelete { offsets in
                        // One row per delete gesture; see the set list.
                        guard offsets.count == 1, let index = offsets.first,
                              orderedItems.indices.contains(index) else { return }
                        pendingItemDeletion = orderedItems[index]
                    }
                    // One Add Filter action; the new filter starts as ND
                    // in this set, and its type and set are chosen in the
                    // editor (FILTER-ITEM-003/009).
                    Button {
                        editingItem = FilterItemEditorContext(
                            filterSetID: filterSetID,
                            item: nil,
                            initialUnit: editorSession.initialUnit
                        )
                    } label: {
                        Label("Add filter", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("filter-item-add-button")
                } header: {
                    Text("Filters")
                } footer: {
                    Text("Register each physical filter separately, even two filters of the same strength, so both can be mounted together.")
                }

                Section {
                    Button(role: .destructive) {
                        isDeletionPending = true
                    } label: {
                        Label("Delete Filter Set", systemImage: "trash")
                    }
                    .accessibilityIdentifier("filter-set-delete-button")
                }
            }
            .navigationTitle(filterSet.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            .onAppear { nameDraft = filterSet.name }
            .onChange(of: filterSet.name) { _, newValue in
                if nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != newValue {
                    nameDraft = newValue
                }
            }
            // The draft commits on Done (`onSubmit`), when the field
            // loses focus, and when the screen is left with the field
            // still focused (Back without Done). All three run the same
            // decision, and a set that no longer exists is a no-op, so
            // deleting the set never turns into a rename call.
            .onChange(of: isNameFieldFocused) { _, isFocused in
                if !isFocused {
                    commitRename()
                }
            }
            .onDisappear {
                if isNameFieldFocused {
                    commitRename()
                }
            }
            .sheet(item: $editingItem) { context in
                FilterItemEditorView(
                    viewModel: viewModel,
                    context: context,
                    onSaved: { item in
                        // Only a saved NEW item teaches the session;
                        // editing an existing item leaves the memory
                        // untouched.
                        if context.item == nil {
                            editorSession.didSaveNewItem(item)
                        }
                    },
                    onDismiss: { editingItem = nil }
                )
            }
            .confirmationDialog(
                Text("Delete filter?"),
                isPresented: Binding(
                    get: { pendingItemDeletion != nil },
                    set: { if !$0 { pendingItemDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingItemDeletion
            ) { item in
                Button(role: .destructive) {
                    viewModel.deleteFilterItem(id: item.id)
                    pendingItemDeletion = nil
                } label: {
                    Text("Delete \(item.name)")
                }
                Button("Cancel", role: .cancel) { pendingItemDeletion = nil }
            } message: { item in
                Text(itemDeletionMessage(for: item))
            }
            // Cancel, dragging the sheet down, or tapping outside it keeps
            // the set and every camera as they are.
            .sheet(isPresented: $isDeletionPending) {
                DestructiveConfirmationSheet(
                    title: String(localized: "Delete \(filterSet.name)?"),
                    message: deletionMessage(for: filterSet),
                    actionTitle: String(localized: "Delete"),
                    onConfirm: {
                        isDeletionPending = false
                        viewModel.deleteFilterSet(id: filterSetID)
                        dismiss()
                    },
                    onCancel: { isDeletionPending = false }
                )
            }
        } else {
            Text("This Filter Set no longer exists.")
                .foregroundStyle(.secondary)
        }
    }

    private func commitRename() {
        switch FilterSetRenameCommit.decide(draft: nameDraft, currentName: filterSet?.name) {
        case .rename(let name):
            viewModel.renameFilterSet(id: filterSetID, name: name)
        case .restore(let name):
            nameDraft = name
        case .none:
            break
        }
    }

    /// The global effect of deleting the set (FILTER-SET-006,
    /// FILTER-ITEM-006): the set and its filters leave the inventory,
    /// and the cameras that mount from it lose those filters and wheels.
    private func deletionMessage(for filterSet: FilterSet) -> String {
        let cameras = viewModel.cameraNames(affectedByDeletingFilterSet: filterSet.id)
        if cameras.isEmpty {
            return String(localized: "This removes \(filterSet.name) and its filters from your inventory. No camera currently mounts from it. Timers already started keep their captured summary.")
        }
        return String(localized: "This removes \(filterSet.name) and its filters from your inventory, and removes its filters and ND wheels on \(cameras.joined(separator: ", ")). Timers already started keep their captured summary.")
    }

    private func itemDeletionMessage(for item: FilterItem) -> String {
        let cameras = viewModel.cameraNames(affectedByDeletingItem: item.id)
        if cameras.isEmpty {
            return String(localized: "No camera currently mounts this filter. Timers already started keep their captured summary.")
        }
        return String(localized: "Wheels mounting this filter become Empty on \(cameras.joined(separator: ", ")). Timers already started keep their captured summary.")
    }
}

private struct FilterItemRow: View {
    let item: FilterItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // A Color filter shows its actual color beside its
                    // name (FILTER-COLOR-001); the name is spoken.
                    if let color = item.behavior.opticalColor {
                        Circle()
                            .fill(Color.filterSet(color))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                    }
                    Text(item.name)
                        .foregroundStyle(.primary)
                }
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(detailText)"))
    }

    private var detailText: String {
        switch item.behavior {
        case .fixed(let value):
            return "\(FilterWheelPresenter.kindName(.fixed)) · \(registeredText(value))"
        case .cpl(let choices):
            let list = choices.shootingChoices
                .map(FilterWheelPresenter.decimalStopsValue)
                .joined(separator: " / ")
            return "\(FilterWheelPresenter.kindName(.cpl)) · \(list) \(String(localized: "stops"))"
        case .gnd(let value):
            return "\(FilterWheelPresenter.kindName(.gnd)) · \(registeredText(value))"
        case .color, .effect:
            let detail = FilterWheelPresenter.auxiliaryLossDetailText(for: item.behavior) ?? ""
            return "\(FilterWheelPresenter.kindName(item.behavior.kind)) · \(detail)"
        }
    }

    /// Original representation plus the canonical stops when the unit
    /// differs from stops (`OD 0.9 · 3 stops`); plain stops read once.
    private func registeredText(_ value: FilterRegisteredValue) -> String {
        let original = FilterWheelPresenter.registeredValueText(value)
        guard value.unit != .stops, let stops = value.canonicalStops else {
            return original
        }
        return "\(original) · \(FilterWheelPresenter.stopsText(stops))"
    }
}

/// A destructive confirmation that names exactly what it changes, with
/// Cancel and the destructive action both visible. Dragging it down or
/// tapping outside it dismisses it like Cancel.
struct DestructiveConfirmationSheet: View {
    let title: String
    let message: String
    let actionTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("destructive-confirmation-cancel")
                Button(role: .destructive, action: onConfirm) {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("destructive-confirmation-confirm")
            }
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}
