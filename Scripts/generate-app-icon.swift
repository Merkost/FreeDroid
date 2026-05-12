#!/usr/bin/env swift

import AppKit
import CoreImage
import Foundation
import SwiftUI
import UniformTypeIdentifiers

let outputDir = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("FreeDroid/Resources/Assets.xcassets/AppIcon.appiconset")

struct IconEntry {
    let filename: String
    let size: Int
}

let iconEntries: [IconEntry] = [
    IconEntry(filename: "icon_16x16.png", size: 16),
    IconEntry(filename: "icon_16x16@2x.png", size: 32),
    IconEntry(filename: "icon_32x32.png", size: 32),
    IconEntry(filename: "icon_32x32@2x.png", size: 64),
    IconEntry(filename: "icon_128x128.png", size: 128),
    IconEntry(filename: "icon_128x128@2x.png", size: 256),
    IconEntry(filename: "icon_256x256.png", size: 256),
    IconEntry(filename: "icon_256x256@2x.png", size: 512),
    IconEntry(filename: "icon_512x512.png", size: 512),
    IconEntry(filename: "icon_512x512@2x.png", size: 1024),
]

struct AppIconView: View {
    let canvasSize: CGFloat

    private var headDiameter: CGFloat { canvasSize * 0.60 }
    private var headRadius: CGFloat { headDiameter / 2 }
    private var droidBodyHeight: CGFloat { headDiameter * 0.55 }
    private var droidCenterX: CGFloat { canvasSize / 2 }
    private var droidCenterY: CGFloat { canvasSize / 2 }
    private var headCenterY: CGFloat { droidCenterY - droidBodyHeight / 2 }
    private var bodyTopY: CGFloat { headCenterY }
    private var bodyBottomY: CGFloat { headCenterY + droidBodyHeight }

    private var antennaWidth: CGFloat { max(2, headDiameter * 0.06) }
    private var antennaLength: CGFloat { headDiameter * 0.25 }
    private var antennaSpacing: CGFloat { headDiameter * 0.30 }

    private var eyeRadius: CGFloat { max(1.5, headDiameter * 0.075) }
    private var eyeSpacing: CGFloat { headDiameter * 0.25 }
    private var eyeY: CGFloat { headCenterY - headRadius * 0.20 }

    private var shadowRadius: CGFloat { max(4, canvasSize * 0.030) }
    private var shadowYOffset: CGFloat { canvasSize * 0.016 }

    private var droidGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.239, green: 0.863, blue: 0.518), Color(red: 0.059, green: 0.702, blue: 0.416)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.10, green: 0.13, blue: 0.18), Color(red: 0.06, green: 0.08, blue: 0.11)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var shadowColor: Color {
        Color(red: 0.059, green: 0.702, blue: 0.416).opacity(0.35)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: canvasSize * 0.225, style: .continuous)
                .fill(backgroundGradient)

            RoundedRectangle(cornerRadius: canvasSize * 0.225, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 0.4)
                    )
                )

            RoundedRectangle(cornerRadius: canvasSize * 0.225, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: max(1, canvasSize * 0.003))

            DroidShape(
                headRadius: headRadius,
                droidCenterX: droidCenterX,
                headCenterY: headCenterY,
                bodyTopY: bodyTopY,
                bodyBottomY: bodyBottomY
            )
            .fill(shadowColor)
            .blur(radius: shadowRadius)
            .offset(y: shadowYOffset)

            DroidShape(
                headRadius: headRadius,
                droidCenterX: droidCenterX,
                headCenterY: headCenterY,
                bodyTopY: bodyTopY,
                bodyBottomY: bodyBottomY
            )
            .fill(droidGradient)

            AntennaShape(
                droidCenterX: droidCenterX,
                headCenterY: headCenterY,
                headRadius: headRadius,
                antennaSpacing: antennaSpacing,
                antennaLength: antennaLength,
                antennaWidth: antennaWidth
            )
            .fill(droidGradient)

            Circle()
                .fill(Color(red: 0.10, green: 0.13, blue: 0.18).opacity(0.92))
                .frame(width: eyeRadius * 2, height: eyeRadius * 2)
                .position(x: droidCenterX - eyeSpacing / 2, y: eyeY)

            Circle()
                .fill(Color(red: 0.10, green: 0.13, blue: 0.18).opacity(0.92))
                .frame(width: eyeRadius * 2, height: eyeRadius * 2)
                .position(x: droidCenterX + eyeSpacing / 2, y: eyeY)
        }
        .frame(width: canvasSize, height: canvasSize)
    }
}

struct DroidShape: Shape {
    let headRadius: CGFloat
    let droidCenterX: CGFloat
    let headCenterY: CGFloat
    let bodyTopY: CGFloat
    let bodyBottomY: CGFloat

    func path(in _: CGRect) -> Path {
        var p = Path()
        let bodyLeft = droidCenterX - headRadius
        let bodyRight = droidCenterX + headRadius
        let bodyCorner = max(2, headRadius * 0.12)

        p.move(to: CGPoint(x: bodyLeft, y: bodyTopY))
        p.addLine(to: CGPoint(x: bodyLeft, y: bodyBottomY - bodyCorner))
        p.addQuadCurve(
            to: CGPoint(x: bodyLeft + bodyCorner, y: bodyBottomY),
            control: CGPoint(x: bodyLeft, y: bodyBottomY)
        )
        p.addLine(to: CGPoint(x: bodyRight - bodyCorner, y: bodyBottomY))
        p.addQuadCurve(
            to: CGPoint(x: bodyRight, y: bodyBottomY - bodyCorner),
            control: CGPoint(x: bodyRight, y: bodyBottomY)
        )
        p.addLine(to: CGPoint(x: bodyRight, y: bodyTopY))

        p.addArc(
            center: CGPoint(x: droidCenterX, y: headCenterY),
            radius: headRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

struct AntennaShape: Shape {
    let droidCenterX: CGFloat
    let headCenterY: CGFloat
    let headRadius: CGFloat
    let antennaSpacing: CGFloat
    let antennaLength: CGFloat
    let antennaWidth: CGFloat

    func path(in _: CGRect) -> Path {
        var p = Path()

        let leftBaseX = droidCenterX - antennaSpacing / 2
        let rightBaseX = droidCenterX + antennaSpacing / 2
        let baseY = headCenterY - headRadius

        let leftAngleRad = -15.0 * Double.pi / 180.0
        let rightAngleRad = 15.0 * Double.pi / 180.0
        let leftDX = CGFloat(antennaLength * sin(leftAngleRad))
        let leftDY = CGFloat(antennaLength * cos(leftAngleRad))
        let rightDX = CGFloat(antennaLength * sin(rightAngleRad))
        let rightDY = CGFloat(antennaLength * cos(rightAngleRad))

        let halfW = antennaWidth / 2

        p.move(to: CGPoint(x: leftBaseX - halfW, y: baseY))
        p.addLine(to: CGPoint(x: leftBaseX - halfW + leftDX, y: baseY - leftDY))
        p.addLine(to: CGPoint(x: leftBaseX + halfW + leftDX, y: baseY - leftDY))
        p.addLine(to: CGPoint(x: leftBaseX + halfW, y: baseY))
        p.closeSubpath()

        p.move(to: CGPoint(x: rightBaseX - halfW, y: baseY))
        p.addLine(to: CGPoint(x: rightBaseX - halfW + rightDX, y: baseY - rightDY))
        p.addLine(to: CGPoint(x: rightBaseX + halfW + rightDX, y: baseY - rightDY))
        p.addLine(to: CGPoint(x: rightBaseX + halfW, y: baseY))
        p.closeSubpath()

        return p
    }
}

@MainActor
func renderIcon(size: Int) -> CGImage {
    let view = AppIconView(canvasSize: CGFloat(size))
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    renderer.proposedSize = ProposedViewSize(width: CGFloat(size), height: CGFloat(size))
    guard let cgImage = renderer.cgImage else {
        fputs("Error: ImageRenderer.cgImage returned nil for size \(size)x\(size)\n", stderr)
        exit(1)
    }
    return cgImage
}

func savePNG(cgImage: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fputs("Error: Could not create CGImageDestination for \(url.path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("Error: Could not finalize PNG at \(url.path)\n", stderr)
        exit(1)
    }
}

@MainActor
func run() {
    do {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
        fputs("Error: Could not create output directory: \(error)\n", stderr)
        exit(1)
    }

    for entry in iconEntries {
        let cgImage = renderIcon(size: entry.size)
        let url = outputDir.appendingPathComponent(entry.filename)
        savePNG(cgImage: cgImage, to: url)
        print("Generated \(entry.filename) (\(entry.size)x\(entry.size))")
    }

    print("Done. Icons written to \(outputDir.path)")
}

Task { @MainActor in
    run()
    exit(0)
}
RunLoop.main.run()
