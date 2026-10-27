// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerCore

public struct TargetNDSettingsView: View {
    @ObservedObject private var model: TargetNDSettingsModel
    @Environment(\.dismiss) private var dismiss

    public init(model: TargetNDSettingsModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Suggest ND selection", isOn: $model.settings.isEnabled)
                        .accessibilityIdentifier("target-nd-suggestions-enabled")
                } header: {
                    Text("Target Shutter")
                } footer: {
                    Text("Adjust Base to see required ND and an Apply action. Filters change only when you apply a suggestion.")
                }
                Section {
                    Picker("Negative", selection: $model.settings.negative) { allowanceChoices(for: .negative) }
                    Picker("Positive", selection: $model.settings.positive) { allowanceChoices(for: .positive) }
                    Picker("Digital", selection: $model.settings.digital) { allowanceChoices(for: .digital) }
                } header: {
                    Text("Allowed exposure error")
                } footer: {
                    Text("These are app selection allowances, not guaranteed film or sensor limits. Digital Extended assumes RAW processing.")
                }
            }
            .navigationTitle("Target Shutter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func allowanceChoices(for medium: TargetNDMedium) -> some View {
        ForEach(TargetNDAllowance.allCases, id: \.self) { mode in
            Text(label(mode, medium: medium)).tag(mode)
        }
    }

    private func label(_ mode: TargetNDAllowance, medium: TargetNDMedium) -> String {
        let name = mode == .standard ? String(localized: "Default") : String(localized: "Extended")
        let range: String
        switch (medium, mode) {
        case (.negative, .standard): range = "−0.5…+1"
        case (.negative, .extended): range = "−0.5…+2"
        case (.positive, .standard): range = "−⅓…+⅓"
        case (.positive, .extended): range = "−0.5…+0.5"
        case (.digital, .standard): range = "−1…0"
        case (.digital, .extended): range = "−2…0"
        }
        return "\(name) (\(range) \(String(localized: "stops")))"
    }
}
