import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct GalleryView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: GalleryViewModel
    var onCopySelectionToMac: ([MediaItem]) -> Void

    public init(viewModel: GalleryViewModel, onCopySelectionToMac: @escaping ([MediaItem]) -> Void) {
        self.viewModel = viewModel
        self.onCopySelectionToMac = onCopySelectionToMac
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                GalleryHeader(viewModel: viewModel)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                        if viewModel.sections.isEmpty && !viewModel.isLoading {
                            emptyStateView
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(viewModel.sections) { sec in
                            sectionView(sec)
                        }
                        if viewModel.hasMore {
                            Button("Load more") {
                                Task { await viewModel.loadMore() }
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, Spacing.md)
                        }
                    }
                    .padding(Spacing.lg)
                }
                .task { await viewModel.load() }
            }

            if !viewModel.selection.isEmpty {
                CommandStrip(
                    selectionCount: viewModel.selection.count,
                    actions: [
                        CommandStripAction(
                            label: "Clear",
                            systemImage: "xmark.circle"
                        ) {
                            viewModel.clearSelection()
                        },
                        CommandStripAction(
                            label: "Copy to Mac",
                            systemImage: "square.and.arrow.down",
                            hotkey: "⌘D",
                            isPrimary: true
                        ) {
                            onCopySelectionToMac(viewModel.selectedItems)
                        }
                    ]
                )
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: Spacing.xl) {
            EmptyState(
                icon: "photo.on.rectangle.angled",
                title: "No media here",
                message: "No photos or videos found in\n\(viewModel.currentFolder.raw)"
            )

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Try another folder")
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(theme.colors.text2)
                    .padding(.horizontal, Spacing.lg)

                ForEach(suggestedFolders, id: \.path.raw) { preset in
                    Button {
                        Task { await viewModel.setFolder(preset.path) }
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(theme.colors.accent)
                            Text(preset.label)
                                .font(Typography.body)
                                .foregroundStyle(theme.colors.text0)
                            Spacer()
                            Text(preset.path.raw)
                                .font(Typography.monoCaption)
                                .foregroundStyle(theme.colors.text3)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, Spacing.xxl)
    }

    private var suggestedFolders: [GalleryPresetFolder] {
        galleryPresetFolders.filter { $0.path != viewModel.currentFolder }
    }

    @ViewBuilder
    private func sectionView(_ sec: MediaSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(sec.label, detail: "\(sec.items.count) items")
            MasonryLayout(columns: 4, spacing: Spacing.md - 2) {
                ForEach(sec.items) { item in
                    PhotoTile(
                        item: item,
                        isSelected: viewModel.selection.contains(item.id),
                        loader: viewModel.loadThumbnail
                    ) {
                        viewModel.toggleSelection(item)
                    }
                }
            }
        }
    }
}
