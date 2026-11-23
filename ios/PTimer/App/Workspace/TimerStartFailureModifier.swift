// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import PTimerKit
import SwiftUI

struct TimerStartFailureModifier: ViewModifier {
    var workspace: TimerWorkspaceModel?
    @State private var message: String?

    private var errors: AnyPublisher<String?, Never> {
        workspace?.$startError.eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()
    }

    func body(content: Content) -> some View {
        content
            .onReceive(errors) { message = $0 }
            .alert("Timer could not start", isPresented: Binding(
                get: { message != nil },
                set: {
                    if !$0 {
                        message = nil
                        workspace?.dismissStartError()
                    }
                }
            )) {
                Button("OK") {
                    message = nil
                    workspace?.dismissStartError()
                }
            } message: {
                Text(message ?? "")
            }
    }
}
