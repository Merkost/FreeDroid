import SwiftUI

public struct MasonryLayout: Layout {
    public var columns: Int
    public var spacing: CGFloat

    public init(columns: Int = 4, spacing: CGFloat = Spacing.md - 2) {
        self.columns = max(1, columns)
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard !subviews.isEmpty else { return .zero }
        let columnWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        var heights = Array(repeating: CGFloat(0), count: columns)
        for subview in subviews {
            let col = shortestColumn(of: heights)
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            heights[col] += size.height + spacing
        }
        return CGSize(width: width, height: (heights.max() ?? 0) - spacing)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        var heights = Array(repeating: bounds.minY, count: columns)
        for subview in subviews {
            let col = shortestColumn(of: heights)
            let xPos = bounds.minX + CGFloat(col) * (columnWidth + spacing)
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            subview.place(at: CGPoint(x: xPos, y: heights[col]), proposal: ProposedViewSize(width: columnWidth, height: size.height))
            heights[col] += size.height + spacing
        }
    }

    private func shortestColumn(of heights: [CGFloat]) -> Int {
        var bestIdx = 0
        var bestVal = CGFloat.infinity
        for (idx, height) in heights.enumerated() where height < bestVal {
            bestVal = height
            bestIdx = idx
        }
        return bestIdx
    }
}
