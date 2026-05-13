import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct FileRowView: View {
    @Environment(\.theme) private var theme
    public let entry: RemoteEntry
    public let isSelected: Bool
    public let isFocused: Bool

    @State private var isHovering = false

    private let iconColumnWidth: CGFloat = 24
    private let sizeColumnWidth: CGFloat = 96
    private let dateColumnWidth: CGFloat = 116
    private let chevronColumnWidth: CGFloat = 18

    public init(entry: RemoteEntry, isSelected: Bool, isFocused: Bool = false) {
        self.entry = entry
        self.isSelected = isSelected
        self.isFocused = isFocused
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            iconView
            nameView
            Spacer(minLength: Spacing.sm)
            sizeView
            dateView
            chevronView
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 32)
        .background(rowBackground)
        .overlay(focusOverlay)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .motion(.crisp, value: isHovering)
        .motion(.crisp, value: isSelected)
        .motion(.crisp, value: isFocused)
    }

    private var iconView: some View {
        Image(systemName: FileIconResolver.symbol(for: entry))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(iconColor)
            .frame(width: iconColumnWidth, alignment: .center)
            .symbolRenderingMode(.hierarchical)
    }

    private var nameView: some View {
        HStack(spacing: Spacing.sm) {
            Text(entry.name)
                .font(Typography.body)
                .foregroundStyle(entry.isHidden ? theme.colors.text2 : theme.colors.text0)
                .lineLimit(1)
                .truncationMode(.middle)
            if entry.isHidden {
                Text("HIDDEN")
                    .font(Typography.label)
                    .tracking(0.6)
                    .foregroundStyle(theme.colors.text2)
                    .padding(.horizontal, Spacing.xs + 1)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(theme.colors.line)
                    )
            }
        }
    }

    @ViewBuilder
    private var sizeView: some View {
        if let text = FileEntryFormatter.sizeString(for: entry) {
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(theme.colors.text2)
                .frame(width: sizeColumnWidth, alignment: .trailing)
                .monospacedDigit()
        } else {
            Text("—")
                .font(Typography.caption)
                .foregroundStyle(theme.colors.text3)
                .frame(width: sizeColumnWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var dateView: some View {
        if let text = FileEntryFormatter.modifiedString(for: entry) {
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(theme.colors.text2)
                .frame(width: dateColumnWidth, alignment: .trailing)
                .monospacedDigit()
        } else {
            Text("—")
                .font(Typography.caption)
                .foregroundStyle(theme.colors.text3)
                .frame(width: dateColumnWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var chevronView: some View {
        if entry.kind == .directory {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.colors.text3)
                .frame(width: chevronColumnWidth, alignment: .trailing)
        } else {
            Color.clear.frame(width: chevronColumnWidth, height: 1)
        }
    }

    private var iconColor: Color {
        if entry.kind == .directory { return theme.colors.accent }
        return isSelected ? theme.colors.text0 : theme.colors.text1
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: Color {
        if isSelected { return theme.colors.accentSoft }
        if isHovering { return theme.colors.line.opacity(0.6) }
        return .clear
    }

    private var focusOverlay: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(borderColor, lineWidth: borderWidth)
    }

    private var borderColor: Color {
        if isSelected { return theme.colors.accent.opacity(0.45) }
        if isFocused { return theme.colors.accent.opacity(0.35) }
        return .clear
    }

    private var borderWidth: CGFloat {
        if isSelected { return 1 }
        if isFocused { return 1 }
        return 0
    }
}

public struct FileRowSkeleton: View {
    @Environment(\.theme) private var theme
    public let nameWidth: CGFloat
    @State private var shimmerPhase: CGFloat = -0.5

    public init(nameWidth: CGFloat = 180) {
        self.nameWidth = nameWidth
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            placeholder(width: 16, height: 16)
                .frame(width: 24, alignment: .center)
            placeholder(width: nameWidth, height: 10)
            Spacer()
            placeholder(width: 60, height: 10)
            placeholder(width: 80, height: 10)
            Color.clear.frame(width: 18, height: 1)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 32)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.5
            }
        }
    }

    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .fill(theme.colors.line)
            .frame(width: width, height: height)
            .overlay(
                LinearGradient(
                    colors: [.clear, theme.colors.background0.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.7)
                .offset(x: width * shimmerPhase)
                .mask(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            )
            .clipped()
    }
}
