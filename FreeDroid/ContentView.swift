import SwiftUI
import FreeDroidUI
import FreeDroidDomain
import DeviceManagement
import FileBrowser
import Gallery
import Transfer

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openSettings) private var openSettings
    @State private var tab: DetailTab = .files

    enum DetailTab: Hashable { case files, gallery }

    private var theme: Theme {
        container.preferences.theme(for: systemColorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AmbientGradientBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        DeviceListView(
                            viewModel: container.deviceListViewModel,
                            deviceFractions: container.transfersViewModel.deviceFractions,
                            onRevealInFinder: { device in
                                FinderRevealer.revealTransferDestination(for: device.displayName)
                            }
                        )
                        appearanceMenu
                            .padding(Spacing.md)
                    }
                    Divider().overlay(theme.colors.line)
                    detail
                }
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .freeDroidTheme(theme)
        .task { await container.start() }
        .overlay(alignment: .bottomTrailing) {
            if !container.transfersViewModel.states.isEmpty {
                TransfersPanel(
                    viewModel: container.transfersViewModel,
                    deviceNameByID: { deviceID in
                        container.deviceListViewModel.devices.first { $0.id == deviceID }?.displayName
                    }
                )
                .frame(width: 360)
                .padding(Spacing.lg)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: Spacing.sm) {
                ForEach(container.transferToastPresenter.toasts) { toast in
                    toast
                }
            }
            .padding(Spacing.lg)
        }
        .task {
            for await states in container.transferRepository.observe() {
                await MainActor.run {
                    container.transferToastPresenter.consume(states)
                }
            }
        }
    }

    private var appearanceMenu: some View {
        @Bindable var preferences = container.preferences
        return Menu {
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Divider()
            Button("Settings\u{2026}") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.text2)
                .padding(8)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedID = container.deviceListViewModel.selectedID {
            VStack(spacing: 0) {
                PillTabs(
                    selection: $tab,
                    tabs: [("Files", DetailTab.files), ("Gallery", DetailTab.gallery)]
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                Divider().overlay(theme.colors.line)
                SidebarFlow(selection: tab) { selectedTab in
                    switch selectedTab {
                    case .files:
                        FileBrowserView(viewModel: container.fileBrowserViewModel(for: selectedID))
                    case .gallery:
                        GalleryView(
                            viewModel: container.galleryViewModel(for: selectedID),
                            onCopySelectionToMac: { items in
                                Task {
                                    guard let device = await container.registry.device(selectedID) else { return }
                                    let stream = container.startTransferUseCase()(
                                        deviceID: selectedID,
                                        deviceName: device.displayName,
                                        items: items.map { $0.path }
                                    )
                                    do {
                                        for try await progress in stream {
                                            await MainActor.run {
                                                container.transfersViewModel.register(jobID: progress.jobID, on: selectedID)
                                            }
                                        }
                                    } catch {}
                                }
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
