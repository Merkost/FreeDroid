import SwiftUI

public enum LivingRingState: Sendable, Equatable {
    case idle
    case transferring
    case disconnected
}

public struct LivingRing: View {
    @Environment(\.theme) private var theme
    private let color: Color
    private let state: LivingRingState
    private let glyph: String

    public init(color: Color, state: LivingRingState, glyph: String) {
        self.color = color
        self.state = state
        self.glyph = glyph
    }

    public var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .strokeBorder(theme.colors.line, lineWidth: 2)
                ringForeground(time: time)
                Text(glyph)
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(state == .disconnected ? theme.colors.text2 : theme.colors.text0)
            }
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private func ringForeground(time: Double) -> some View {
        switch state {
        case .idle:
            let phase = sin(time / 3.2 * .pi * 2) * 0.5 + 0.5
            Circle()
                .trim(from: 0, to: 0.78 + phase * 0.22)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(0.85 + phase * 0.15)
        case .transferring:
            let angle = time.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
            Circle()
                .trim(from: 0.18, to: 0.42)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(angle - 90))
        case .disconnected:
            Circle()
                .strokeBorder(theme.colors.text3, style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
        }
    }
}
