// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The X close control shared by sheets: an `xmark` icon whose
/// accessible name is `Close`. The visible glyph carries no text, so
/// the name is set explicitly.
struct SheetCloseButton: View {
    static let systemImageName = "xmark"
    static var accessibilityLabelText: String { String(localized: "Close") }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: Self.systemImageName)
        }
        .accessibilityLabel(Text(Self.accessibilityLabelText))
        .accessibilityIdentifier("sheet-close-button")
    }
}
