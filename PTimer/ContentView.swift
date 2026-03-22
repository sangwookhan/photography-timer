import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("PTimer")
                .font(.title2.weight(.semibold))

            Text("SwiftUI iPhone app bootstrap complete.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
