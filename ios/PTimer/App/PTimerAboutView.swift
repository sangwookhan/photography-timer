// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PTimerAboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let version: String
    private let build: String

    init(bundle: Bundle = .main) {
        version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unavailable"
        build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unavailable"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photography Timer")
                            .font(.title.bold())
                        Text("Exposure calculator and countdown timer for film and digital photography.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Version") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Build", value: build)
                }

                Section("Legal") {
                    Text("Copyright © 2026 Sangwook Han")
                    Text("Licensed under the Apache License, Version 2.0. The full license text is available in this repository's LICENSE file.")
                }

                Section("Film Data") {
                    Text("Film data is centered on official data sheets and manufacturer publications, with publicly available references used as supplemental sources where applicable.")
                    Text("Photography Timer stores normalized factual values and source references; it does not redistribute third-party datasheet PDFs or copied source documents.")
                }

                Section {
                    Link("Photography Timer Website", destination: URL(string: "https://sangwookhan.github.io/photography-timer/")!)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
