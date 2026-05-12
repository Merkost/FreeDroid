import SwiftUI

public enum LivingRingState: Sendable, Equatable {
    case idle
    case transferring
    case disconnected
    case pendingAuthorization
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
        ZStack {
            Circle()
                .strokeBorder(theme.colors.line, lineWidth: 2)
            staticOrAnimatedRing
            Text(glyph)
                .font(Typography.bodyEmphasized)
                .foregroundStyle(
                    state == .disconnected || state == .pendingAuthorization
                        ? theme.colors.text2
                        : theme.colors.text0
                )
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var staticOrAnimatedRing: some View {
        switch state {
        case .idle:
            Circle()
                .trim(from: 0, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .opacity(0.95)

        case .transferring:
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let angle = time.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
                Circle()
                    .trim(from: 0.18, to: 0.42)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(angle - 90))
            }

        case .disconnected:
            Circle()
                .strokeBorder(theme.colors.text3, style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

        case .pendingAuthorization:
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = sin(time / 5.0 * .pi * 2) * 0.5 + 0.5
                Circle()
                    .strokeBorder(color.opacity(0.5 + phase * 0.45), lineWidth: 2)
            }
        }
    }
}
