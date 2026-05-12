import SwiftUI

public struct Spinner: View {
    @Environment(\.theme) private var theme
    private let size: CGFloat

    public init(size: CGFloat = 18) {
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
            Circle()
                .trim(from: 0.18, to: 0.82)
                .stroke(theme.colors.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(angle))
                .frame(width: size, height: size)
        }
    }
}
