import SwiftUI

public struct Motion: Sendable, Equatable {
    public let response: Double
    public let damping: Double
    public let blendDuration: Double

    public static let crisp = Motion(response: 0.22, damping: 0.85, blendDuration: 0.0)
    public static let smooth = Motion(response: 0.42, damping: 0.78, blendDuration: 0.05)
    public static let lazy = Motion(response: 0.70, damping: 0.72, blendDuration: 0.10)

    public var animation: Animation {
        .spring(response: response, dampingFraction: damping, blendDuration: blendDuration)
    }
}

public extension View {
    func motion(_ preset: Motion, value: some Equatable) -> some View {
        animation(preset.animation, value: value)
    }
}
