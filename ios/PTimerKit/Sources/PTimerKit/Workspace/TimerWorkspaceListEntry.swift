// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One identity space lets SwiftUI move an existing timer between sections
/// instead of destroying its Active row and inserting a different History row.
public enum TimerWorkspaceListEntry: Identifiable, Equatable {
    case header(title: String, isHistory: Bool)
    case timer(BottomSheetLargeItem)

    public var id: String {
        switch self {
        case .header(let title, _): return "section:\(title)"
        case .timer(let item): return "timer:\(item.id.uuidString)"
        }
    }

    public static func make(from sections: [TimerWorkspaceSection]) -> [Self] {
        sections.flatMap { section in
            [.header(title: section.title, isHistory: section.isCompletedSection)]
                + section.items.map(Self.timer)
        }
    }
}
