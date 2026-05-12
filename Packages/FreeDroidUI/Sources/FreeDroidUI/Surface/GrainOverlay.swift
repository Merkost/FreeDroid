import SwiftUI

public struct GrainOverlay: View {
    private let intensity: Double

    public init(intensity: Double = 0.06) {
        self.intensity = intensity
    }

    public var body: some View {
        Canvas { context, size in
            let pixelSize: CGFloat = 1.2
            let count = Int(size.width * size.height / 64)
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<count {
                let posX = Double.random(in: 0..<Double(size.width), using: &rng)
                let posY = Double.random(in: 0..<Double(size.height), using: &rng)
                let alpha = Double.random(in: 0..<intensity, using: &rng)
                let rect = CGRect(x: posX, y: posY, width: pixelSize, height: pixelSize)
                context.fill(Path(rect), with: .color(.white.opacity(alpha)))
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}
