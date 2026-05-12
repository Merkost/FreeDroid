import SwiftUI
import FreeDroidUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 16) {
            Text("FreeDroid")
                .font(.largeTitle.weight(.semibold))
            Text("v\(container.bundleVersion) — pre-alpha")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("UI module: \(FreeDroidUIInfo.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 360, height: 200)
    }
}
