// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

extension View {
    /// Presents a selection, management, editing or details task as a
    /// bounded form on a wide window instead of stretching its controls
    /// across it (SHELL-060). Compact windows keep the full sheet. Before
    /// iOS 18 the system's default sheet sizing applies.
    @ViewBuilder
    func boundedTaskPresentation() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.form)
        } else {
            self
        }
    }
}
