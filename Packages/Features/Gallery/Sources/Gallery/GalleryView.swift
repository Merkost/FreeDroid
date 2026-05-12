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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    if viewModel.sections.isEmpty && !viewModel.isLoading {
                        EmptyState(
                            icon: "photo.on.rectangle.angled",
                            title: "No photos",
                            message: "Photos and videos from this folder will appear here."
                        )
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
