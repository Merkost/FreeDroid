import SwiftUI
import FreeDroidUI
import FreeDroidDomain
import DeviceManagement
import FileBrowser

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var theme: Theme = .dark

    var body: some View {
        ZStack {
            AmbientGradientBackground().ignoresSafeArea()
            HStack(spacing: 0) {
                DeviceListView(viewModel: container.deviceListViewModel)
                Divider().overlay(theme.colors.line)
                detail
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .freeDroidTheme(theme)
        .task { await container.start() }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedID = container.deviceListViewModel.selectedID {
            FileBrowserView(viewModel: container.fileBrowserViewModel(for: selectedID))
                .id(selectedID)
        } else {
            placeholderDetail
        }
    }

    private var placeholderDetail: some View {
        ZStack {
            Color.clear
            VStack(spacing: Spacing.md) {
                Text("Select a device").font(Typography.title)
                Text("Plug in a phone or pick one from the sidebar to start browsing.")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
