// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The single Filter Set management surface (FILTER-SET-001): create,
/// rename, recolor, reorder, and delete Filter Sets, and manage each
/// set's physical items. Reached from the persistent ND header entry
/// and by long-pressing the Plus wheel.
struct FilterSetManagementView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let onDone: () -> Void

    @State private var creationDraft: FilterSetDraft?
    @State private var pendingDeletion: FilterSet?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.filterInventory.filterSets.isEmpty {
                    Section {
                        Text("No Filter Sets yet. Create one to register the physical filters you carry.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(viewModel.filterInventory.filterSets) { filterSet in
                    NavigationLink {
                        FilterSetDetailView(viewModel: viewModel, filterSetID: filterSet.id)
                    } label: {
                        FilterSetRow(filterSet: filterSet)
                    }
                    .accessibilityIdentifier("filter-set-row-\(filterSet.id.rawValue)")
                }
                .onMove { source, destination in
                    viewModel.moveFilterSets(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    guard let index = offsets.first,
                          viewModel.filterInventory.filterSets.indices.contains(index) else { return }
                    pendingDeletion = viewModel.filterInventory.filterSets[index]
                }
            }
            .navigationTitle("Filter Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("filter-sets-done-button")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creationDraft = FilterSetDraft(
                            name: "",
                            color: viewModel.suggestFilterSetCreationColor()
                        )
                    } label: {
                        Label("New Filter Set", systemImage: "plus")
                    }
                    .accessibilityIdentifier("filter-sets-create-button")
                }
                ToolbarItem(placement: .secondaryAction) {
                    EditButton()
                }
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
            .confirmationDialog(
                Text("Delete Filter Set?"),
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { filterSet in
                Button(role: .destructive) {
                    viewModel.deleteFilterSet(id: filterSet.id)
                    pendingDeletion = nil
                } label: {
                    Text("Delete \(filterSet.name)")
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { filterSet in
                Text(deletionMessage(for: filterSet))
            }
        }
    }

    private func deletionMessage(for filterSet: FilterSet) -> String {
        let cameras = viewModel.cameraNames(affectedByDeletingFilterSet: filterSet.id)
        if cameras.isEmpty {
            return String(localized: "Its filters are removed from the inventory. Timers already started keep their captured summary.")
        }
        return String(localized: "Filter wheels from this set are removed on \(cameras.joined(separator: ", ")). Timers already started keep their captured summary.")
    }
}

private struct FilterSetRow: View {
    let filterSet: FilterSet

    var body: some View {
        HStack(spacing: 12) {
            FilterSetColorSwatch(color: filterSet.color, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(filterSet.name)
                Text(filterCountText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(filterSet.name), \(filterSet.color.localizedName), \(filterCountText)"))
    }

    private var filterCountText: String {
        filterSet.items.count == 1
            ? String(localized: "1 filter")
            : String(localized: "\(filterSet.items.count) filters")
    }
}

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

/// One Filter Set: rename, recolor, and manage its physical items.
struct FilterSetDetailView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let filterSetID: FilterSetID

    @State private var nameDraft: String = ""
    @State private var editingItem: FilterItemEditorContext?
    @State private var pendingItemDeletion: FilterItem?

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
                    if filterSet.items.isEmpty {
                        Text("No filters registered yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filterSet.items) { item in
                        Button {
                            editingItem = FilterItemEditorContext(filterSetID: filterSetID, item: item)
                        } label: {
                            FilterItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("filter-item-row-\(item.id.rawValue)")
                    }
                    .onMove { source, destination in
                        viewModel.moveFilterItems(in: filterSetID, fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        guard let index = offsets.first, filterSet.items.indices.contains(index) else { return }
                        pendingItemDeletion = filterSet.items[index]
                    }
                    Button {
                        editingItem = FilterItemEditorContext(filterSetID: filterSetID, item: nil)
                    } label: {
                        Label("Add filter", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("filter-item-add-button")
                } header: {
                    Text("Filters")
                } footer: {
                    Text("Register each physical filter separately, even two filters of the same strength, so both can be mounted together.")
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
            .onDisappear(perform: commitRename)
            .sheet(item: $editingItem) { context in
                FilterItemEditorView(viewModel: viewModel, context: context) {
                    editingItem = nil
                }
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
        } else {
            Text("This Filter Set no longer exists.")
                .foregroundStyle(.secondary)
        }
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = filterSet?.name ?? ""
            return
        }
        viewModel.renameFilterSet(id: filterSetID, name: trimmed)
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
                Text(item.name)
                    .foregroundStyle(.primary)
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
