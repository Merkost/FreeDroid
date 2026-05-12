import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct AsyncThumbnail: View {
    @Environment(\.theme) private var theme
    private let item: MediaItem
    private let loader: LoadThumbnailUseCase
    private let size: ThumbnailSize

    @State private var image: NSImage?
    @State private var hasFailed = false

    public init(item: MediaItem, loader: LoadThumbnailUseCase, size: ThumbnailSize = .medium) {
        self.item = item
        self.loader = loader
        self.size = size
    }

    public var body: some View {
        ZStack {
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else if hasFailed {
                ZStack {
                    Rectangle().fill(theme.colors.background2)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(theme.colors.text2)
                }
            } else {
                ZStack {
                    Rectangle().fill(theme.colors.background2)
                    Spinner(size: 14)
                }
            }
        }
        .clipped()
        .motion(.smooth, value: image == nil)
        .task(id: item.id) {
            await loadImage()
        }
    }

    private func loadImage() async {
        do {
            let data = try await loader(for: item, size: size)
            if let loaded = NSImage(data: data) {
                image = loaded
            } else {
                hasFailed = true
            }
        } catch {
            hasFailed = true
        }
    }
}
