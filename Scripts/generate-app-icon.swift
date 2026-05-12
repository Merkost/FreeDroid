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
    private var s: CGFloat { canvasSize / 1024.0 }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.102, green: 0.129, blue: 0.169), Color(red: 0.059, green: 0.078, blue: 0.106)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var droidGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.239, green: 0.863, blue: 0.518), Color(red: 0.059, green: 0.702, blue: 0.416)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230 * s, style: .continuous)
                .fill(backgroundGradient)

            RoundedRectangle(cornerRadius: 230 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: max(0.5, 2 * s))

            AntennaeShape()
                .stroke(droidGradient, style: StrokeStyle(lineWidth: 32 * s, lineCap: .round))

            HeadAndBodyShape()
                .fill(droidGradient)

            EyesShape()
                .fill(Color(red: 0.059, green: 0.078, blue: 0.106))
        }
        .frame(width: canvasSize, height: canvasSize)
    }

    private struct AntennaeShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024.0
            let cx = rect.midX
            let cy = rect.midY
            var p = Path()
            p.move(to: CGPoint(x: cx - 160 * s, y: cy - 310 * s))
            p.addLine(to: CGPoint(x: cx - 110 * s, y: cy - 220 * s))
            p.move(to: CGPoint(x: cx + 160 * s, y: cy - 310 * s))
            p.addLine(to: CGPoint(x: cx + 110 * s, y: cy - 220 * s))
            return p
        }
    }

    private struct HeadAndBodyShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024.0
            let cx = rect.midX
            let cy = rect.midY
            var p = Path()
            p.move(to: CGPoint(x: cx - 260 * s, y: cy))
            p.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: 260 * s,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            p.addLine(to: CGPoint(x: cx + 260 * s, y: cy + 170 * s))
            p.addArc(
                center: CGPoint(x: cx + 250 * s, y: cy + 170 * s),
                radius: 10 * s,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            p.addLine(to: CGPoint(x: cx - 250 * s, y: cy + 180 * s))
            p.addArc(
                center: CGPoint(x: cx - 250 * s, y: cy + 170 * s),
                radius: 10 * s,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            p.closeSubpath()
            return p
        }
    }

    private struct EyesShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 1024.0
            let cx = rect.midX
            let cy = rect.midY
            var p = Path()
            p.addEllipse(in: CGRect(x: cx - 110 * s - 28 * s, y: cy - 60 * s - 28 * s, width: 56 * s, height: 56 * s))
            p.addEllipse(in: CGRect(x: cx + 110 * s - 28 * s, y: cy - 60 * s - 28 * s, width: 56 * s, height: 56 * s))
            return p
        }
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
        let destination = outputDir.appendingPathComponent(entry.filename)
        savePNG(cgImage: cgImage, to: destination)
        print("Wrote \(entry.filename) (\(entry.size)x\(entry.size))")
    }
}

DispatchQueue.main.async {
    run()
    exit(0)
}
RunLoop.main.run()
