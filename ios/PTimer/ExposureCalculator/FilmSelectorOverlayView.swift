import SwiftUI

/// Material-backed film selection overlay surfaced by
/// `ExposureCalculatorScreen` when the photographer taps the Film
/// row. Renders sections grouped by manufacturer plus a sentinel
/// "No film" row at the top.

struct FilmSelectorOverlay: View {
    let sections: [FilmSelectorSection]
    let selectedFilmID: String?
    let onSelectEntry: (FilmSelectorEntry) -> Void
    /// Tapping the "Create custom film" sentinel row at the top of
    /// the picker invokes this callback. Optional so the picker can
    /// still render in surfaces that have no editor entry point
    /// (preview / future read-only contexts).
    let onCreateCustomFilm: (() -> Void)?
    /// contexts. Only `kind == .custom` rows surface the action, so
    /// a preset row can never be deleted by mistake.
    let onDeleteCustomFilm: ((String) -> Void)?
    /// Opens the editor on the existing custom film via the row
    /// overflow menu (Edit). Same gating rule as
    /// `onDeleteCustomFilm` — only `kind == .custom` rows surface
    /// the action.
    let onEditCustomFilm: ((String) -> Void)?
    let style: ExposureWorkspaceMainLayoutStyle

    /// Captured entry awaiting the "Delete custom film?"
    /// confirmation. Keyed on the full `FilmSelectorEntry` so the
    /// dialog can render the film's stock name in the destructive
    /// button label without re-resolving the entry through the
    /// section data.
    @State private var pendingDelete: FilmSelectorEntry?

    init(
        sections: [FilmSelectorSection],
        selectedFilmID: String?,
        onSelectEntry: @escaping (FilmSelectorEntry) -> Void,
        onCreateCustomFilm: (() -> Void)? = nil,
        onDeleteCustomFilm: ((String) -> Void)? = nil,
        onEditCustomFilm: ((String) -> Void)? = nil,
        style: ExposureWorkspaceMainLayoutStyle
    ) {
        self.sections = sections
        self.selectedFilmID = selectedFilmID
        self.onSelectEntry = onSelectEntry
        self.onCreateCustomFilm = onCreateCustomFilm
        self.onDeleteCustomFilm = onDeleteCustomFilm
        self.onEditCustomFilm = onEditCustomFilm
        self.style = style
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                FilmSelectorHeader(
                    style: style,
                    onCreateCustomFilm: onCreateCustomFilm
                )
                ScrollView(.vertical, showsIndicators: true) {
                    // Eager VStack (not LazyVStack) so every section card and
                    // every row is registered with the ScrollViewProxy before
                    // the .onAppear scroll target is requested. With 34 films
                    // across 6 manufacturer groups the eagerness cost is
                    // negligible, but the reliability gain is the difference
                    // between scrollTo finding a row and silently no-oping
                    // when the target row sits below the initial viewport.
                    VStack(spacing: groupSpacing) {
                        ForEach(sections) { section in
                            FilmSelectorSectionCard(
                                section: section,
                                selectedFilmID: selectedFilmID,
                                onSelectEntry: onSelectEntry,
                                onRequestDeleteCustomFilm: onDeleteCustomFilm == nil
                                    ? nil
                                    : { entry in pendingDelete = entry },
                                onEditCustomFilm: onEditCustomFilm,
                                rowHeight: rowHeight
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: overlayWidth, maxHeight: maxOverlayHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("film-selector-overlay")
            // Confirmation dialog for the destructive Delete
            // action. Held at the overlay level so the long-press
            // contextMenu and the inline `…` Menu both route
            // through the same reliable confirmation step before
            // the library mutation runs.
            .confirmationDialog(
                "Delete custom film?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { presented in if !presented { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { entry in
                // Always confirm against the canonical custom-film
                // id so a Quick Access alias row (id prefix
                // `quick:`) does not route through the alias when
                // removing the entry from the library.
                Button("Delete \(entry.primaryText)", role: .destructive) {
                    if let canonical = entry.canonicalCustomFilmID {
                        onDeleteCustomFilm?(canonical)
                    }
                    pendingDelete = nil
                }
                .accessibilityIdentifier(
                    "film-selector-confirm-delete-\(entry.canonicalCustomFilmID ?? entry.id)"
                )
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { entry in
                Text("This removes \(entry.primaryText) from your custom films. Running and completed timers keep their original profile.")
            }
            .onAppear {
                scrollToSelection(proxy: proxy)
            }
        }
    }

    /// Scrolls the overlay to the currently selected row.
    ///
    /// Two main-queue hops are required for reliability:
    ///  - `.onAppear` fires before SwiftUI completes the overlay's first
    ///    layout pass.
    ///  - The first `DispatchQueue.main.async` lands after view-tree
    ///    insertion but before the ScrollViewProxy has finished
    ///    registering every `.id(...)` from the freshly-materialized
    ///    section cards.
    ///  - The second `DispatchQueue.main.async` lands after the proxy
    ///    registry has settled, so `scrollTo(id:anchor:)` can find any
    ///    row regardless of whether it sits inside the initial viewport.
    ///
    /// The entry id distinguishes official from unofficial variants
    /// because the unofficial selector entry uses the unofficial profile
    /// id, not the film id (see `ExposureCalculatorViewModel
    /// .selectedSelectorEntryID`).
    private func scrollToSelection(proxy: ScrollViewProxy) {
        guard let selectedFilmID, !selectedFilmID.isEmpty else { return }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                proxy.scrollTo(selectedFilmID, anchor: .center)
            }
        }
    }

    private var overlayWidth: CGFloat {
        switch style {
        case .regular:
            return 440
        case .compact:
            return 404
        case .dense:
            return 372
        }
    }

    private var rowHeight: CGFloat {
        switch style {
        case .regular:
            return 52
        case .compact:
            return 48
        case .dense:
            return 44
        }
    }

    private var maxOverlayHeight: CGFloat {
        switch style {
        case .regular:
            return 520
        case .compact:
            return 460
        case .dense:
            return 420
        }
    }

    private var groupSpacing: CGFloat { 12 }
}

/// One manufacturer group rendered as a subtle grouped card. The
/// "No film" sentinel section has `manufacturer == nil` and renders
/// as a plain card-less row at the top so it stays distinct from the
/// preset groups. The view layout is intentionally header-on-top /
/// rows-below (rather than interleaved headers + rows) so a future
/// fold/unfold gesture can be added by toggling the rows region
/// without touching the header.
private struct FilmSelectorSectionCard: View {
    let section: FilmSelectorSection
    let selectedFilmID: String?
    let onSelectEntry: (FilmSelectorEntry) -> Void
    /// The section card raises a request to delete (full
    /// `FilmSelectorEntry`) so the parent overlay can route it
    /// through a single confirmation dialog. The actual library
    /// mutation happens only after the user taps the destructive
    /// button in the dialog.
    let onRequestDeleteCustomFilm: ((FilmSelectorEntry) -> Void)?
    let onEditCustomFilm: ((String) -> Void)?
    let rowHeight: CGFloat

    private let cardCornerRadius: CGFloat = 14
    private let cardInnerPadding: CGFloat = 12
    private let rowSpacing: CGFloat = 4

    var body: some View {
        if let manufacturer = section.manufacturer {
            VStack(alignment: .leading, spacing: rowSpacing) {
                // Header pill — a small rounded label that sits inside
                // the card with a slightly stronger tint than the card
                // surface itself, plus near-primary text contrast. The
                // pill keeps the manufacturer name immediately readable
                // while staying visually subordinate to film rows by
                // size and uppercase styling.
                Text(manufacturer)
                    .font(.subheadline.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.bottom, 2)
                    .accessibilityIdentifier("film-selector-section-\(manufacturer)")

                ForEach(section.entries) { entry in
                    rowButton(for: entry)
                }
            }
            .padding(cardInnerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            )
        } else {
            // "No film" sentinel: rendered card-less so it visually
            // separates from the manufacturer groups.
            VStack(spacing: rowSpacing) {
                ForEach(section.entries) { entry in
                    rowButton(for: entry)
                }
            }
            .padding(.horizontal, cardInnerPadding)
        }
    }

    @ViewBuilder
    private func rowButton(for entry: FilmSelectorEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                onSelectEntry(entry)
            } label: {
                HStack(spacing: 10) {
                    // Keep the Unofficial badge next to the film name so it reads as profile identity.
                    HStack(spacing: 6) {
                        Text(entry.primaryText)
                            .font(.body.weight(isSelected(entry) ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        unofficialBadge(for: entry.supportState)
                    }
                    .layoutPriority(0)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Official support icon sits next to ISO; shape carries the support state.
                    officialSupportIcon(for: entry.supportState)

                    if let secondaryText = entry.secondaryText {
                        Text(secondaryText)
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.68))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .background(rowBackground(for: entry))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: entry))
            .accessibilityAddTraits(isSelected(entry) ? .isSelected : [])
            .accessibilityIdentifier("film-selector-entry-\(entry.id)")

            // Edit/Delete overflow menu for custom-film rows only.
            // Preset rows render the same trailing space empty so
            // the row heights stay aligned across the picker.
            customRowOverflowMenu(for: entry)
        }
        .id(entry.id)
        .contextMenu {
            // Long-press fallback for custom-film rows. Same gating
            // rule as the inline overflow menu so a shipped film
            // cannot be deleted by accident.
            if entry.film?.kind == .custom {
                if let onEditCustomFilm, let canonical = entry.canonicalCustomFilmID {
                    Button {
                        onEditCustomFilm(canonical)
                    } label: {
                        Label("Edit custom film", systemImage: "pencil")
                    }
                }
                if let onRequestDeleteCustomFilm {
                    Button(role: .destructive) {
                        onRequestDeleteCustomFilm(entry)
                    } label: {
                        Label("Delete custom film", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func customRowOverflowMenu(for entry: FilmSelectorEntry) -> some View {
        let isCustom = entry.film?.kind == .custom
        let hasAction = onEditCustomFilm != nil || onRequestDeleteCustomFilm != nil
        if isCustom, hasAction {
            Menu {
                if let onEditCustomFilm, let canonical = entry.canonicalCustomFilmID {
                    Button {
                        onEditCustomFilm(canonical)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                if let onRequestDeleteCustomFilm {
                    Button(role: .destructive) {
                        onRequestDeleteCustomFilm(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(width: 28, height: rowHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Custom film options")
            .accessibilityIdentifier("film-selector-entry-overflow-\(entry.id)")
        } else {
            Color.clear.frame(width: 0, height: rowHeight)
        }
    }

    /// Compact SF Symbol for the three official support states.
    /// Primary-opacity tint keeps the glyph legible on the
    /// `.ultraThinMaterial` popover; shape, not color, carries the
    /// meaning. The row's combined `accessibilityLabel` already
    /// announces the full support meaning, so the glyph stays hidden
    /// from VoiceOver. Returns `EmptyView` for `unofficialPractical`
    /// (whose indicator is the badge next to the film name) and
    /// `.none`.
    @ViewBuilder
    private func officialSupportIcon(for state: FilmSelectorSupportDisplayState) -> some View {
        if let icon = state.iconSystemName {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .imageScale(.medium)
                .foregroundStyle(Color.primary.opacity(0.78))
                .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }

    /// Visible "UNOFFICIAL" pill rendered next to the film name so it
    /// reads as part of the film/profile identity. The uppercase word
    /// is the primary discriminator; the capsule fill + thin border
    /// is supplementary. Hidden from VoiceOver because the row's
    /// `accessibilityLabel` carries "Unofficial practical estimate".
    /// Returns `EmptyView` for every other state.
    @ViewBuilder
    private func unofficialBadge(for state: FilmSelectorSupportDisplayState) -> some View {
        if let badge = state.unofficialBadgeText {
            Text(badge)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Color.primary.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(0.28), lineWidth: 0.5)
                )
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }

    /// Compose one row-level accessibility label because the visual
    /// row uses split indicators (badge next to the name, icon next
    /// to the ISO). Reads "name, ISO, support meaning".
    private func accessibilityLabel(for entry: FilmSelectorEntry) -> String {
        var parts: [String] = [entry.primaryText]
        if let secondary = entry.secondaryText {
            parts.append(secondary)
        }
        if let supportLabel = entry.supportState.accessibilityLabel {
            parts.append(supportLabel)
        }
        return parts.joined(separator: ", ")
    }

    private func isSelected(_ entry: FilmSelectorEntry) -> Bool {
        guard let selectedFilmID else { return false }
        if entry.id == selectedFilmID { return true }
        // A Quick Access alias row is the same selection identity
        // as its canonical row; mark both selected so the
        // photographer sees a single coherent highlight regardless
        // of which row they tapped.
        return entry.aliasOfOriginalID == selectedFilmID
    }

    @ViewBuilder
    private func rowBackground(for entry: FilmSelectorEntry) -> some View {
        if isSelected(entry) {
            Color.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }
}

/// Lightweight overlay chrome that carries the picker title and
/// the trailing "+" button. The "+" is the primary entry point
/// for the custom-film editor. Kept outside the ScrollView so it
/// stays pinned even after a long scroll.
private struct FilmSelectorHeader: View {
    let style: ExposureWorkspaceMainLayoutStyle
    let onCreateCustomFilm: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text("Films")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            if let onCreateCustomFilm {
                Button(action: onCreateCustomFilm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.78))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create custom film")
                .accessibilityIdentifier("film-selector-create-custom-film")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            // Match the parent material so the header reads as
            // part of the popover surface rather than a separate
            // toolbar.
            Color.clear
        )
    }
}
