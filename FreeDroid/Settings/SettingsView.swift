import SwiftUI
import FreeDroidUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 280)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var preferences = container.preferences
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Transfers") {
                Picker("Parallel transfers per device", selection: $preferences.parallelTransfers) {
                    ForEach(ParallelTransfers.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Text("Run multiple file copies at once. Use 1 if your phone or USB cable is unstable.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use native ADB sync protocol", isOn: $preferences.useWireProtocol)
                Text("Talks to your phone over a persistent socket instead of spawning a process per file. Major speedup on 'Preparing to copy' and folder listings. Leave on unless you hit weird errors on an unusual device.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private enum AboutLinks {
    static let github = URL(string: "https://github.com/Merkost/FreeDroid")!
    static let releases = URL(string: "https://github.com/Merkost/FreeDroid/releases")!
    static let issues = URL(string: "https://github.com/Merkost/FreeDroid/issues/new")!
    static let license = URL(string: "https://opensource.org/license/mit/")!
}

struct AboutSettingsView: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        VStack(spacing: Spacing.md) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            Text("FreeDroid")
                .font(Typography.title)
            Text("Version \(version)")
                .font(Typography.callout)
                .foregroundStyle(.secondary)
            Text("The free, modern, open-source way to mount Android devices on macOS.")
                .font(Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xl)
            HStack(spacing: Spacing.md) {
                Link("Source", destination: AboutLinks.github)
                Link("Releases", destination: AboutLinks.releases)
                Link("Report issue", destination: AboutLinks.issues)
                Link("License", destination: AboutLinks.license)
            }
            .padding(.top, Spacing.sm)
            Text("Built by independent contributors. Star the repo if it saved you $40/year.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}
