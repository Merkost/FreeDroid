import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct BreadcrumbBar: View {
    @Environment(\.theme) private var theme
    private let components: [String]
    private let onSelect: (RemotePath) -> Void

    public init(components: [String], onSelect: @escaping (RemotePath) -> Void) {
        self.components = components
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { proxy in
            content(availableWidth: proxy.size.width)
        }
        .frame(height: 26)
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        let plan = BreadcrumbPlan.make(components: components, availableWidth: availableWidth)
        HStack(spacing: Spacing.xs) {
            crumb(label: "/", path: .root, isCurrent: components.isEmpty)
            ForEach(plan.items.indices, id: \.self) { index in
                separator
                renderItem(plan.items[index])
            }
            Spacer(minLength: 0)
        }
        .motion(.crisp, value: plan.items.count)
    }

    @ViewBuilder
    private func renderItem(_ item: BreadcrumbPlan.Item) -> some View {
        switch item {
        case .segment(let segment):
            crumb(label: segment.name, path: segment.path, isCurrent: segment.isCurrent)
        case .ellipsis(let hidden):
            ellipsisMenu(for: hidden)
        }
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.colors.text3)
    }

    @ViewBuilder
    private func crumb(label: String, path: RemotePath, isCurrent: Bool) -> some View {
        Button {
            onSelect(path)
        } label: {
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(isCurrent ? theme.colors.text0 : theme.colors.text1)
                .fontWeight(isCurrent ? .semibold : .regular)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isCurrent ? theme.colors.accentSoft : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(isCurrent ? theme.colors.accent.opacity(0.25) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func ellipsisMenu(for hidden: [BreadcrumbPlan.Segment]) -> some View {
        Menu {
            ForEach(hidden.indices, id: \.self) { index in
                let segment = hidden[index]
                Button(segment.name) { onSelect(segment.path) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.text2)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(theme.colors.line.opacity(0.5))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct BreadcrumbPlan {
    struct Segment: Equatable {
        let name: String
        let path: RemotePath
        let isCurrent: Bool
    }

    enum Item: Equatable {
        case segment(Segment)
        case ellipsis([Segment])
    }

    let items: [Item]

    static func make(components: [String], availableWidth: CGFloat) -> BreadcrumbPlan {
        let segments: [Segment] = components.indices.map { index in
            let name = components[index]
            let path = RemotePath(raw: "/" + components[0...index].joined(separator: "/"))
            return Segment(name: name, path: path, isCurrent: index == components.count - 1)
        }
        let maxVisible = visibleSegmentCount(width: availableWidth)
        if segments.count <= maxVisible {
            return BreadcrumbPlan(items: segments.map(Item.segment))
        }
        guard let first = segments.first, let last = segments.last else {
            return BreadcrumbPlan(items: segments.map(Item.segment))
        }
        let tailCount = max(1, maxVisible - 2)
        let tail = Array(segments.suffix(tailCount))
        let hidden = Array(segments.dropFirst().dropLast(tail.count))
        var items: [Item] = [.segment(first)]
        if !hidden.isEmpty {
            items.append(.ellipsis(hidden))
        }
        items.append(contentsOf: tail.map(Item.segment))
        if tail.contains(first) {
            items = tail.map(Item.segment)
        } else if !tail.contains(last) {
            items.append(.segment(last))
        }
        return BreadcrumbPlan(items: items)
    }

    private static func visibleSegmentCount(width: CGFloat) -> Int {
        switch width {
        case ..<320: return 2
        case ..<480: return 3
        case ..<680: return 4
        case ..<900: return 5
        default: return 8
        }
    }
}
