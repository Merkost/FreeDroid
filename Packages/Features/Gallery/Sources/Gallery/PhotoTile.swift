import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct PhotoTile: View {
    @Environment(\.theme) private var theme
    private let item: MediaItem
    private let isSelected: Bool
    private let loader: LoadThumbnailUseCase
    private let onTap: () -> Void

    @State private var isHovered = false
    @State private var hoverOffset: CGSize = .zero

    public init(
        item: MediaItem,
        isSelected: Bool,
        loader: LoadThumbnailUseCase,
        onTap: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.loader = loader
        self.onTap = onTap
    }

    public var body: some View {
        let tileHeight = CGFloat(120 + (abs(item.id.hashValue) % 80))
        ZStack(alignment: .topLeading) {
            AsyncThumbnail(item: item, loader: loader)
                .frame(height: tileHeight)
                .background(theme.colors.background2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(isSelected ? theme.colors.accent : .clear, lineWidth: 2)
                )

            if isHovered || isSelected {
                Circle()
                    .fill(isSelected ? theme.colors.accent : Color.black.opacity(0.45))
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.4)
                    )
                    .frame(width: 18, height: 18)
                    .padding(Spacing.sm)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .offset(hoverOffset)
        .shadow(color: isHovered ? .black.opacity(0.45) : .clear, radius: 18, x: 0, y: 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovered = hovering
            hoverOffset = hovering ? CGSize(width: 0, height: -2) : .zero
        }
        .motion(.smooth, value: isHovered)
        .motion(.smooth, value: isSelected)
    }
}
