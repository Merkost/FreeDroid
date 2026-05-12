# FreeDroid Plan #2 — UI Design System

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full `FreeDroidUI` design system: theme tokens (light + dark), motion presets, all reusable surfaces, controls, feedback components, and layouts described in the spec. Every component has Xcode Previews and snapshot tests in both themes.

**Architecture:** Single `FreeDroidUI` Swift Package. All components are pure SwiftUI views with no business-logic dependencies. Theme accessed exclusively via `@Environment(\.theme)`. Motion accessed exclusively via `Motion` preset enum. Snapshot tests cover light + dark for every component.

**Tech Stack:** SwiftUI, swift-snapshot-testing.

---

## File Structure

```
Packages/FreeDroidUI/
├── Package.swift                                              modify
└── Sources/FreeDroidUI/
    ├── Tokens/
    │   ├── Theme.swift                                        create
    │   ├── ColorTokens.swift                                  create
    │   ├── Spacing.swift                                      create
    │   ├── Radius.swift                                       create
    │   ├── Typography.swift                                   create
    │   └── Motion.swift                                       create
    ├── Surface/
    │   ├── MaterialPanel.swift                                create
    │   ├── GrainOverlay.swift                                 create
    │   ├── Card.swift                                         create
    │   └── Sheet.swift                                        create
    ├── Controls/
    │   ├── IconChip.swift                                     create
    │   ├── Hotkey.swift                                       create
    │   ├── CommandStrip.swift                                 create
    │   ├── ToggleRow.swift                                    create
    │   └── PillTabs.swift                                     create
    ├── Feedback/
    │   ├── FluidProgress.swift                                create
    │   ├── LivingRing.swift                                   create
    │   ├── Toast.swift                                        create
    │   └── Spinner.swift                                      create
    ├── Layout/
    │   ├── SidebarFlow.swift                                  create
    │   ├── MasonryLayout.swift                                create
    │   └── SectionHeader.swift                                create
    ├── Empty/
    │   └── EmptyState.swift                                   create
    └── Internal/
        └── BackgroundGradients.swift                          create
└── Tests/FreeDroidUITests/
    ├── SnapshotTesting+Helpers.swift                          create
    ├── TokensTests.swift                                      create
    ├── SurfaceSnapshotTests.swift                             create
    ├── ControlsSnapshotTests.swift                            create
    ├── FeedbackSnapshotTests.swift                            create
    └── LayoutSnapshotTests.swift                              create
```

The existing `Placeholder.swift` is removed in Task 2.

---

## Task 1: Add `swift-snapshot-testing` dependency

**Files:**
- Modify: `Packages/FreeDroidUI/Package.swift`

- [ ] **Step 1: Update the manifest**

Overwrite `Packages/FreeDroidUI/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FreeDroidUI", targets: ["FreeDroidUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "FreeDroidUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FreeDroidUITests",
            dependencies: [
                "FreeDroidUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 2: Resolve dependencies**

Run: `cd Packages/FreeDroidUI && swift package resolve`
Expected: `Package.resolved` created.

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add swift-snapshot-testing dependency"
```

---

## Task 2: Remove placeholder, add color tokens

**Files:**
- Delete: `Packages/FreeDroidUI/Sources/FreeDroidUI/Placeholder.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/ColorTokens.swift`

- [ ] **Step 1: Delete the placeholder**

```bash
rm Packages/FreeDroidUI/Sources/FreeDroidUI/Placeholder.swift
```

- [ ] **Step 2: Implement color tokens**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/ColorTokens.swift`:

```swift
import SwiftUI

public struct ColorTokens: Sendable, Equatable {
    public let background0: Color
    public let background1: Color
    public let background2: Color
    public let line: Color
    public let lineStrong: Color
    public let text0: Color
    public let text1: Color
    public let text2: Color
    public let text3: Color
    public let accent: Color
    public let accentSoft: Color
    public let adb: Color
    public let mtp: Color
    public let wifi: Color
    public let danger: Color
    public let warning: Color

    public static let dark = ColorTokens(
        background0: Color(red: 0.047, green: 0.051, blue: 0.063),
        background1: Color(red: 0.071, green: 0.075, blue: 0.090),
        background2: Color(red: 0.086, green: 0.094, blue: 0.114),
        line: Color.white.opacity(0.07),
        lineStrong: Color.white.opacity(0.12),
        text0: Color(red: 0.961, green: 0.961, blue: 0.969),
        text1: Color(red: 0.722, green: 0.725, blue: 0.753),
        text2: Color(red: 0.482, green: 0.490, blue: 0.525),
        text3: Color(red: 0.302, green: 0.310, blue: 0.341),
        accent: Color(red: 0.0, green: 0.878, blue: 0.541),
        accentSoft: Color(red: 0.0, green: 0.878, blue: 0.541).opacity(0.16),
        adb: Color(red: 0.0, green: 0.878, blue: 0.541),
        mtp: Color(red: 0.353, green: 0.663, blue: 1.0),
        wifi: Color(red: 0.690, green: 0.486, blue: 1.0),
        danger: Color(red: 1.0, green: 0.365, blue: 0.416),
        warning: Color(red: 1.0, green: 0.741, blue: 0.180)
    )

    public static let light = ColorTokens(
        background0: Color(red: 0.973, green: 0.973, blue: 0.976),
        background1: Color(red: 1.0, green: 1.0, blue: 1.0),
        background2: Color(red: 0.949, green: 0.949, blue: 0.957),
        line: Color.black.opacity(0.08),
        lineStrong: Color.black.opacity(0.14),
        text0: Color(red: 0.059, green: 0.059, blue: 0.078),
        text1: Color(red: 0.298, green: 0.310, blue: 0.341),
        text2: Color(red: 0.467, green: 0.482, blue: 0.518),
        text3: Color(red: 0.659, green: 0.671, blue: 0.706),
        accent: Color(red: 0.0, green: 0.682, blue: 0.420),
        accentSoft: Color(red: 0.0, green: 0.682, blue: 0.420).opacity(0.12),
        adb: Color(red: 0.0, green: 0.682, blue: 0.420),
        mtp: Color(red: 0.149, green: 0.471, blue: 0.851),
        wifi: Color(red: 0.490, green: 0.255, blue: 0.890),
        danger: Color(red: 0.875, green: 0.227, blue: 0.286),
        warning: Color(red: 0.812, green: 0.553, blue: 0.094)
    )
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git rm Packages/FreeDroidUI/Sources/FreeDroidUI/Placeholder.swift
git add Packages/FreeDroidUI
git commit -m "feat(ui): add color tokens for light and dark themes"
```

---

## Task 3: Spacing, Radius, Typography tokens

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Spacing.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Radius.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Typography.swift`

- [ ] **Step 1: Implement `Spacing`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Spacing.swift`:

```swift
import CoreFoundation

public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}
```

- [ ] **Step 2: Implement `Radius`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Radius.swift`:

```swift
import CoreFoundation

public enum Radius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 9
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let pill: CGFloat = 999
}
```

- [ ] **Step 3: Implement `Typography`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Typography.swift`:

```swift
import SwiftUI

public enum Typography {
    public static let display = Font.system(size: 26, weight: .semibold, design: .default)
    public static let title = Font.system(size: 18, weight: .semibold, design: .default)
    public static let bodyEmphasized = Font.system(size: 13, weight: .semibold)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let callout = Font.system(size: 12, weight: .regular)
    public static let caption = Font.system(size: 11, weight: .regular)
    public static let captionEmphasized = Font.system(size: 11, weight: .semibold)
    public static let label = Font.system(size: 10, weight: .semibold).smallCaps()
    public static let numeral = Font.system(size: 13, weight: .medium, design: .rounded).monospacedDigit()
    public static let monoCaption = Font.system(size: 10, weight: .medium, design: .monospaced)
}
```

- [ ] **Step 4: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add spacing, radius, typography tokens"
```

---

## Task 4: `Theme` and `Environment` value with tests

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Theme.swift`
- Create: `Packages/FreeDroidUI/Tests/FreeDroidUITests/TokensTests.swift`

- [ ] **Step 1: Write the failing test**

Write `Packages/FreeDroidUI/Tests/FreeDroidUITests/TokensTests.swift`:

```swift
import Testing
import SwiftUI
@testable import FreeDroidUI

@Suite("Tokens")
struct TokensTests {
    @Test func darkAndLightThemesProvideAllRequiredColors() {
        let dark = Theme.dark
        let light = Theme.light
        #expect(dark.colors != light.colors)
        #expect(dark.colorScheme == .dark)
        #expect(light.colorScheme == .light)
    }

    @Test func environmentDefaultIsDark() {
        let env = EnvironmentValues()
        #expect(env.theme.colorScheme == .dark)
    }

    @Test func motionPresetsAreDistinct() {
        #expect(Motion.crisp.response != Motion.smooth.response)
        #expect(Motion.smooth.response != Motion.lazy.response)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `cd Packages/FreeDroidUI && swift test`
Expected: build errors — `cannot find 'Theme'`, `'Motion'`, `'theme'`.

- [ ] **Step 3: Implement `Theme` with environment integration**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Theme.swift`:

```swift
import SwiftUI

public struct Theme: Sendable, Equatable {
    public let colorScheme: ColorScheme
    public let colors: ColorTokens

    public static let dark = Theme(colorScheme: .dark, colors: .dark)
    public static let light = Theme(colorScheme: .light, colors: .light)

    public static func from(_ scheme: ColorScheme) -> Theme {
        scheme == .light ? .light : .dark
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    func freeDroidTheme(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
    }
}
```

- [ ] **Step 4: Implement `Motion`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Motion.swift`:

```swift
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
    func motion(_ motion: Motion, value: some Equatable) -> some View {
        animation(motion.animation, value: value)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd Packages/FreeDroidUI && swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add Theme environment value and Motion presets"
```

---

## Task 5: Snapshot test helpers

**Files:**
- Create: `Packages/FreeDroidUI/Tests/FreeDroidUITests/SnapshotTesting+Helpers.swift`

- [ ] **Step 1: Write the helper**

Write `Packages/FreeDroidUI/Tests/FreeDroidUITests/SnapshotTesting+Helpers.swift`:

```swift
import SwiftUI
import SnapshotTesting
@testable import FreeDroidUI

@MainActor
func assertSnapshot<V: View>(
    of view: V,
    size: CGSize = CGSize(width: 360, height: 200),
    name: String,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
) {
    for theme in [Theme.dark, Theme.light] {
        let suffix = theme.colorScheme == .dark ? "dark" : "light"
        let hosting = view
            .frame(width: size.width, height: size.height)
            .freeDroidTheme(theme)
        assertSnapshot(
            of: hosting,
            as: .image(layout: .fixed(width: size.width, height: size.height)),
            named: "\(name)-\(suffix)",
            file: file,
            testName: testName,
            line: line
        )
    }
}
```

- [ ] **Step 2: Build the test target to verify it compiles**

Run: `cd Packages/FreeDroidUI && swift test --skip 'TokensTests'`
Expected: no test failures (only token tests would run, but they pass and we're verifying compile).

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "test(ui): add snapshot testing helpers for light and dark themes"
```

---

## Task 6: `BackgroundGradients` and `GrainOverlay`

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Internal/BackgroundGradients.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/GrainOverlay.swift`

- [ ] **Step 1: Implement `BackgroundGradients`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Internal/BackgroundGradients.swift`:

```swift
import SwiftUI

struct AmbientGradientBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let radius = max(size.width, size.height) * 0.6
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.2 - radius/2, y: size.height * 0.3 - radius/2, width: radius, height: radius)),
                with: .color(theme.colors.accent.opacity(0.10))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.85 - radius/2, y: size.height * 0.75 - radius/2, width: radius, height: radius)),
                with: .color(theme.colors.mtp.opacity(0.08))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.5 - radius/2, y: size.height * 1.0 - radius/2, width: radius, height: radius)),
                with: .color(theme.colors.wifi.opacity(0.06))
            )
        }
        .blur(radius: 80)
        .background(theme.colors.background0)
    }
}
```

- [ ] **Step 2: Implement `GrainOverlay`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/GrainOverlay.swift`:

```swift
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
                let x = Double.random(in: 0..<Double(size.width), using: &rng)
                let y = Double.random(in: 0..<Double(size.height), using: &rng)
                let alpha = Double.random(in: 0..<intensity, using: &rng)
                let rect = CGRect(x: x, y: y, width: pixelSize, height: pixelSize)
                context.fill(Path(rect), with: .color(.white.opacity(alpha)))
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add ambient gradient background and grain overlay"
```

---

## Task 7: `MaterialPanel`, `Card`, `Sheet` surfaces

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/MaterialPanel.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/Card.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/Sheet.swift`
- Create: `Packages/FreeDroidUI/Tests/FreeDroidUITests/SurfaceSnapshotTests.swift`

- [ ] **Step 1: Implement `MaterialPanel`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/MaterialPanel.swift`:

```swift
import SwiftUI

public struct MaterialPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = Radius.lg, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(theme.colors.line, lineWidth: 1)
                    )
            }
    }
}
```

- [ ] **Step 2: Implement `Card`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/Card.swift`:

```swift
import SwiftUI

public struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    private let isActive: Bool
    private let content: Content

    public init(isActive: Bool = false, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(isActive ? theme.colors.accentSoft : theme.colors.background1.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(isActive ? theme.colors.accent.opacity(0.25) : theme.colors.line, lineWidth: 1)
                    )
            }
            .shadow(color: isActive ? theme.colors.accent.opacity(0.25) : .clear, radius: 30, x: 0, y: 10)
            .motion(.smooth, value: isActive)
    }
}
```

- [ ] **Step 3: Implement `Sheet`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Surface/Sheet.swift`:

```swift
import SwiftUI

public struct Sheet<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            content
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 480)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(theme.colors.lineStrong, lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.4), radius: 50, x: 0, y: 25)
    }
}
```

- [ ] **Step 4: Write snapshot tests**

Write `Packages/FreeDroidUI/Tests/FreeDroidUITests/SurfaceSnapshotTests.swift`:

```swift
import Testing
import SwiftUI
import SnapshotTesting
@testable import FreeDroidUI

@MainActor
@Suite("Surface snapshots")
struct SurfaceSnapshotTests {
    @Test func materialPanelSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            MaterialPanel {
                Text("Material Panel").font(Typography.title).padding()
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 160), name: "MaterialPanel")
    }

    @Test func cardSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            VStack(spacing: Spacing.md) {
                Card { Text("Idle card").padding(.horizontal) }
                Card(isActive: true) { Text("Active card").padding(.horizontal) }
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 220), name: "Card")
    }

    @Test func sheetSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            Sheet {
                Text("Connect your device").font(Typography.title)
                Text("Tap Allow on your phone to authorize this Mac.").font(Typography.body)
            }
        }
        assertSnapshot(of: view, size: CGSize(width: 520, height: 260), name: "Sheet")
    }
}
```

- [ ] **Step 5: Run tests in record mode first**

Run: `cd Packages/FreeDroidUI && SNAPSHOT_TESTING_RECORD=true swift test --filter SurfaceSnapshotTests`
Expected: tests "fail" with record-mode messages, generating reference images under `Tests/FreeDroidUITests/__Snapshots__/`.

- [ ] **Step 6: Run tests in normal mode**

Run: `cd Packages/FreeDroidUI && swift test --filter SurfaceSnapshotTests`
Expected: all tests pass against the recorded snapshots.

- [ ] **Step 7: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add MaterialPanel, Card, Sheet surfaces with snapshot tests"
```

---

## Task 8: `Hotkey` and `IconChip` controls

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/Hotkey.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/IconChip.swift`

- [ ] **Step 1: Implement `Hotkey`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/Hotkey.swift`:

```swift
import SwiftUI

public struct Hotkey: View {
    @Environment(\.theme) private var theme
    private let symbols: String

    public init(_ symbols: String) {
        self.symbols = symbols
    }

    public var body: some View {
        Text(symbols)
            .font(Typography.monoCaption)
            .foregroundStyle(theme.colors.text2)
            .padding(.horizontal, Spacing.xs + 1)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(theme.colors.line)
            )
    }
}
```

- [ ] **Step 2: Implement `IconChip`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/IconChip.swift`:

```swift
import SwiftUI

public enum IconChipKind: Sendable {
    case adb, mtp, wifi, off, custom(Color)
}

public struct IconChip: View {
    @Environment(\.theme) private var theme
    private let label: String
    private let kind: IconChipKind

    public init(_ label: String, kind: IconChipKind) {
        self.label = label
        self.kind = kind
    }

    public var body: some View {
        Text(label.uppercased())
            .font(Typography.captionEmphasized)
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.xs + 1)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }

    private var color: Color {
        switch kind {
        case .adb: theme.colors.adb
        case .mtp: theme.colors.mtp
        case .wifi: theme.colors.wifi
        case .off: theme.colors.text2
        case .custom(let c): c
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add Hotkey and IconChip controls"
```

---

## Task 9: `PillTabs` and `ToggleRow` controls

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/PillTabs.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/ToggleRow.swift`

- [ ] **Step 1: Implement `PillTabs`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/PillTabs.swift`:

```swift
import SwiftUI

public struct PillTabs<Tab: Hashable & Sendable>: View {
    @Environment(\.theme) private var theme
    @Binding private var selection: Tab
    private let tabs: [(label: String, value: Tab)]

    public init(selection: Binding<Tab>, tabs: [(String, Tab)]) {
        self._selection = selection
        self.tabs = tabs
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.value) { tab in
                let isActive = tab.value == selection
                Button {
                    selection = tab.value
                } label: {
                    Text(tab.label)
                        .font(Typography.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(isActive ? theme.colors.text0 : theme.colors.text2)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs + 1)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(isActive ? theme.colors.line : .clear)
                        )
                }
                .buttonStyle(.plain)
                .motion(.crisp, value: isActive)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.colors.background1.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
        )
    }
}
```

- [ ] **Step 2: Implement `ToggleRow`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/ToggleRow.swift`:

```swift
import SwiftUI

public struct ToggleRow: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.bodyEmphasized).foregroundStyle(theme.colors.text0)
                if let subtitle {
                    Text(subtitle).font(Typography.callout).foregroundStyle(theme.colors.text2)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(theme.colors.accent)
        }
        .padding(Spacing.md)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add PillTabs and ToggleRow controls"
```

---

## Task 10: `CommandStrip` control

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/CommandStrip.swift`
- Create: `Packages/FreeDroidUI/Tests/FreeDroidUITests/ControlsSnapshotTests.swift`

- [ ] **Step 1: Implement `CommandStrip`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Controls/CommandStrip.swift`:

```swift
import SwiftUI

public struct CommandStripAction: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let systemImage: String?
    public let hotkey: String?
    public let isPrimary: Bool
    public let action: @MainActor () -> Void

    public init(
        label: String,
        systemImage: String? = nil,
        hotkey: String? = nil,
        isPrimary: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.hotkey = hotkey
        self.isPrimary = isPrimary
        self.action = action
    }
}

public struct CommandStrip: View {
    @Environment(\.theme) private var theme
    private let selectionCount: Int
    private let actions: [CommandStripAction]

    public init(selectionCount: Int, actions: [CommandStripAction]) {
        self.selectionCount = selectionCount
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: 2) {
            if selectionCount > 0 {
                HStack(spacing: 6) {
                    Text("\(selectionCount)").font(Typography.numeral).foregroundStyle(theme.colors.text0)
                    Text("selected").font(Typography.caption).foregroundStyle(theme.colors.text2)
                }
                .padding(.horizontal, Spacing.sm)
                separator
            }
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                button(for: action)
                if idx < actions.count - 1 && actions[idx + 1].isPrimary {
                    separator
                }
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg + 2, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg + 2, style: .continuous)
                        .strokeBorder(theme.colors.lineStrong, lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.55), radius: 25, x: 0, y: 14)
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.colors.line)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func button(for action: CommandStripAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: 7) {
                if let icon = action.systemImage {
                    Image(systemName: icon).font(.system(size: 13, weight: action.isPrimary ? .semibold : .medium))
                }
                Text(action.label).font(Typography.callout).fontWeight(action.isPrimary ? .semibold : .medium)
                if let hk = action.hotkey {
                    Hotkey(hk)
                }
            }
            .foregroundStyle(action.isPrimary ? Color(red: 0, green: 0.2, blue: 0.1) : theme.colors.text1)
            .padding(.horizontal, Spacing.md - 1)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md - 1, style: .continuous)
                    .fill(action.isPrimary ? theme.colors.accent : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Write a snapshot test**

Write `Packages/FreeDroidUI/Tests/FreeDroidUITests/ControlsSnapshotTests.swift`:

```swift
import Testing
import SwiftUI
@testable import FreeDroidUI

@MainActor
@Suite("Controls snapshots")
struct ControlsSnapshotTests {
    @Test func iconChipsSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            HStack(spacing: Spacing.sm) {
                IconChip("ADB", kind: .adb)
                IconChip("MTP", kind: .mtp)
                IconChip("Wi-Fi", kind: .wifi)
                IconChip("Off", kind: .off)
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 360, height: 80), name: "IconChips")
    }

    @Test func pillTabsSnapshot() {
        @Previewable @State var sel = "gallery"
        let view = ZStack {
            AmbientGradientBackground()
            PillTabs(selection: $sel, tabs: [
                ("Gallery", "gallery"),
                ("Files", "files"),
                ("Apps", "apps")
            ])
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 80), name: "PillTabs")
    }

    @Test func commandStripSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            CommandStrip(selectionCount: 3, actions: [
                CommandStripAction(label: "Copy to Mac", systemImage: "arrow.down.circle", hotkey: "⌘D") { },
                CommandStripAction(label: "Delete", systemImage: "trash") { },
                CommandStripAction(label: "Reveal in Finder", systemImage: "folder", hotkey: "⏎", isPrimary: true) { }
            ])
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 720, height: 100), name: "CommandStrip")
    }
}
```

- [ ] **Step 3: Record and verify**

Run: `cd Packages/FreeDroidUI && SNAPSHOT_TESTING_RECORD=true swift test --filter ControlsSnapshotTests`
Then: `cd Packages/FreeDroidUI && swift test --filter ControlsSnapshotTests`
Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add CommandStrip with snapshot tests"
```

---

## Task 11: `Spinner` and `Toast` feedback components

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/Spinner.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/Toast.swift`

- [ ] **Step 1: Implement `Spinner`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/Spinner.swift`:

```swift
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
```

- [ ] **Step 2: Implement `Toast`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/Toast.swift`:

```swift
import SwiftUI

public enum ToastKind: Sendable {
    case info, success, warning, danger
}

public struct Toast: View, Identifiable {
    public let id = UUID()
    @Environment(\.theme) private var theme
    private let kind: ToastKind
    private let title: String
    private let detail: String?

    public init(kind: ToastKind = .info, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: Spacing.sm + 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 6)
            HStack(spacing: 6) {
                Text(title).font(Typography.callout).foregroundStyle(theme.colors.text0)
                if let detail {
                    Text(detail).font(Typography.captionEmphasized).foregroundStyle(theme.colors.text0)
                }
            }
        }
        .padding(.horizontal, Spacing.md + 2)
        .padding(.vertical, Spacing.sm + 1)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(theme.colors.lineStrong, lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
    }

    private var color: Color {
        switch kind {
        case .info: theme.colors.accent
        case .success: theme.colors.accent
        case .warning: theme.colors.warning
        case .danger: theme.colors.danger
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add Spinner and Toast components"
```

---

## Task 12: `LivingRing` and `FluidProgress` signature components

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/LivingRing.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/FluidProgress.swift`
- Create: `Packages/FreeDroidUI/Tests/FreeDroidUITests/FeedbackSnapshotTests.swift`

- [ ] **Step 1: Implement `LivingRing`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/LivingRing.swift`:

```swift
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
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .strokeBorder(theme.colors.line, lineWidth: 2)
                ringForeground(time: t)
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
```

- [ ] **Step 2: Implement `FluidProgress`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Feedback/FluidProgress.swift`:

```swift
import SwiftUI

public struct FluidProgress: View {
    @Environment(\.theme) private var theme
    private let fraction: Double
    private let cornerRadius: CGFloat

    public init(fraction: Double, cornerRadius: CGFloat = Radius.lg) {
        self.fraction = max(0, min(1, fraction))
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        GeometryReader { geo in
            let h = geo.size.height * fraction
            ZStack(alignment: .bottom) {
                Color.clear
                LinearGradient(
                    colors: [theme.colors.accent.opacity(0.10), theme.colors.accent.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.colors.accent.opacity(0.5))
                        .frame(height: 1)
                        .blur(radius: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .motion(.smooth, value: fraction)
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: Write snapshot tests**

Write `Packages/FreeDroidUI/Tests/FreeDroidUITests/FeedbackSnapshotTests.swift`:

```swift
import Testing
import SwiftUI
@testable import FreeDroidUI

@MainActor
@Suite("Feedback snapshots")
struct FeedbackSnapshotTests {
    @Test func livingRingsSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            HStack(spacing: Spacing.lg) {
                LivingRing(color: .green, state: .idle, glyph: "P")
                LivingRing(color: .blue, state: .transferring, glyph: "O")
                LivingRing(color: .gray, state: .disconnected, glyph: "M")
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 240, height: 80), name: "LivingRings")
    }

    @Test func fluidProgressSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            Card {
                ZStack {
                    HStack(spacing: Spacing.md) {
                        LivingRing(color: .green, state: .transferring, glyph: "O")
                        VStack(alignment: .leading) {
                            Text("OnePlus 12").font(Typography.bodyEmphasized)
                            Text("Copying · 1.4 / 2.2 GB").font(Typography.caption)
                        }
                        Spacer()
                    }
                    FluidProgress(fraction: 0.64)
                }
                .frame(width: 240)
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 120), name: "FluidProgressCard")
    }

    @Test func toastSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            VStack(spacing: Spacing.sm) {
                Toast(kind: .success, title: "Pixel 8 Pro mounted")
                Toast(kind: .warning, title: "OnePlus 12 copying…", detail: "64%")
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 160), name: "Toasts")
    }
}
```

- [ ] **Step 4: Record then verify**

Run: `cd Packages/FreeDroidUI && SNAPSHOT_TESTING_RECORD=true swift test --filter FeedbackSnapshotTests`
Then: `cd Packages/FreeDroidUI && swift test --filter FeedbackSnapshotTests`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add LivingRing and FluidProgress with snapshot tests"
```

---

## Task 13: `MasonryLayout` and `SectionHeader`

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Layout/MasonryLayout.swift`
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Layout/SectionHeader.swift`

- [ ] **Step 1: Implement `MasonryLayout`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Layout/MasonryLayout.swift`:

```swift
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
            let s = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            heights[col] += s.height + spacing
        }
        return CGSize(width: width, height: (heights.max() ?? 0) - spacing)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        var heights = Array(repeating: bounds.minY, count: columns)
        for subview in subviews {
            let col = shortestColumn(of: heights)
            let x = bounds.minX + CGFloat(col) * (columnWidth + spacing)
            let s = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            subview.place(at: CGPoint(x: x, y: heights[col]), proposal: ProposedViewSize(width: columnWidth, height: s.height))
            heights[col] += s.height + spacing
        }
    }

    private func shortestColumn(of heights: [CGFloat]) -> Int {
        var bestIdx = 0
        var bestVal = CGFloat.infinity
        for (i, h) in heights.enumerated() where h < bestVal {
            bestVal = h
            bestIdx = i
        }
        return bestIdx
    }
}
```

- [ ] **Step 2: Implement `SectionHeader`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Layout/SectionHeader.swift`:

```swift
import SwiftUI

public struct SectionHeader: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.sm + 2) {
            Text(title).font(Typography.title).foregroundStyle(theme.colors.text0)
            if let detail {
                Text(detail).font(Typography.monoCaption).foregroundStyle(theme.colors.text2)
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add MasonryLayout and SectionHeader"
```

---

## Task 14: `SidebarFlow` transition container

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Layout/SidebarFlow.swift`
- Create: `Packages/FreeDroidUI/Tests/FreeDroidUITests/LayoutSnapshotTests.swift`

- [ ] **Step 1: Implement `SidebarFlow`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Layout/SidebarFlow.swift`:

```swift
import SwiftUI

public struct SidebarFlow<Selection: Hashable, Content: View>: View {
    private let selection: Selection
    private let content: (Selection) -> Content

    public init(selection: Selection, @ViewBuilder content: @escaping (Selection) -> Content) {
        self.selection = selection
        self.content = content
    }

    public var body: some View {
        ZStack {
            content(selection)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.985).combined(with: .opacity),
                    removal: .scale(scale: 1.015).combined(with: .opacity)
                ))
                .id(selection)
        }
        .motion(.smooth, value: selection)
    }
}
```

- [ ] **Step 2: Write masonry snapshot test**

Write `Packages/FreeDroidUI/Tests/FreeDroidUITests/LayoutSnapshotTests.swift`:

```swift
import Testing
import SwiftUI
@testable import FreeDroidUI

@MainActor
@Suite("Layout snapshots")
struct LayoutSnapshotTests {
    @Test func masonrySnapshot() {
        let palettes: [(Color, CGFloat)] = [
            (.blue, 140), (.purple, 110), (.green, 180), (.orange, 125),
            (.red, 150), (.cyan, 95), (.yellow, 160), (.pink, 130)
        ]
        let view = ZStack {
            AmbientGradientBackground()
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("Today", detail: "42 photos")
                MasonryLayout(columns: 4, spacing: Spacing.md - 2) {
                    ForEach(0..<palettes.count, id: \.self) { idx in
                        let (color, h) = palettes[idx]
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(color.opacity(0.4))
                            .frame(height: h)
                    }
                }
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 600, height: 400), name: "Masonry")
    }
}
```

- [ ] **Step 3: Record then verify**

Run: `cd Packages/FreeDroidUI && SNAPSHOT_TESTING_RECORD=true swift test --filter LayoutSnapshotTests`
Then: `cd Packages/FreeDroidUI && swift test --filter LayoutSnapshotTests`
Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add SidebarFlow and Masonry snapshot tests"
```

---

## Task 15: `EmptyState` component

**Files:**
- Create: `Packages/FreeDroidUI/Sources/FreeDroidUI/Empty/EmptyState.swift`

- [ ] **Step 1: Implement `EmptyState`**

Write `Packages/FreeDroidUI/Sources/FreeDroidUI/Empty/EmptyState.swift`:

```swift
import SwiftUI

public struct EmptyState: View {
    @Environment(\.theme) private var theme
    private let icon: String
    private let title: String
    private let message: String
    private let actionLabel: String?
    private let action: (@MainActor () -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionLabel: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.colors.text2)
            VStack(spacing: 4) {
                Text(title).font(Typography.title).foregroundStyle(theme.colors.text0)
                Text(message).font(Typography.body).foregroundStyle(theme.colors.text2).multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.colors.accent)
            }
        }
        .frame(maxWidth: 320)
        .padding(Spacing.xl)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd Packages/FreeDroidUI && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/FreeDroidUI
git commit -m "feat(ui): add EmptyState component"
```

---

## Task 16: Wire previews into app for visual smoke test

**Files:**
- Modify: `FreeDroid/ContentView.swift`

- [ ] **Step 1: Replace `ContentView.swift`**

Overwrite `FreeDroid/ContentView.swift`:

```swift
import SwiftUI
import FreeDroidUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var theme: Theme = .dark
    @State private var selectedTab: String = "components"

    var body: some View {
        ZStack {
            AmbientGradientBackground().ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                header
                componentGallery
            }
            .padding(Spacing.xl)
        }
        .frame(width: 720, height: 560)
        .freeDroidTheme(theme)
    }

    private var header: some View {
        HStack {
            Text("FreeDroid Design System").font(Typography.display)
            Spacer()
            PillTabs(selection: $theme, tabs: [("Dark", Theme.dark), ("Light", Theme.light)])
        }
    }

    private var componentGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SectionHeader("Surfaces")
                HStack(spacing: Spacing.md) {
                    Card { Text("Idle card") }
                    Card(isActive: true) { Text("Active card") }
                }
                SectionHeader("Feedback")
                HStack(spacing: Spacing.lg) {
                    LivingRing(color: .green, state: .idle, glyph: "P")
                    LivingRing(color: .blue, state: .transferring, glyph: "G")
                    Spinner()
                }
                SectionHeader("Toasts")
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toast(kind: .success, title: "Pixel 8 Pro mounted")
                    Toast(kind: .warning, title: "OnePlus 12 copying…", detail: "64%")
                }
            }
        }
    }
}
```

Note: `PillTabs` requires `Theme: Hashable`. Add this to `Theme.swift`:

In `Packages/FreeDroidUI/Sources/FreeDroidUI/Tokens/Theme.swift`, change the `Theme` declaration to also conform to `Hashable`:

```swift
public struct Theme: Sendable, Equatable, Hashable {
```

- [ ] **Step 2: Build and run the app**

In Xcode: `⌘R`.
Expected: a window showing the design system gallery in dark theme. Toggle to light using the pill tabs — entire app re-themes instantly.

- [ ] **Step 3: Commit**

```bash
git add FreeDroid Packages/FreeDroidUI
git commit -m "feat: design system gallery in app with theme toggle"
```

---

## Task 17: Update CI to run UI tests

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Replace the `test-ui` job**

In `.github/workflows/ci.yml`, replace the `test-ui` job with:

```yaml
  test-ui:
    name: Test FreeDroidUI
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - name: Build & test
        run: |
          cd Packages/FreeDroidUI
          swift test --parallel
```

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: run FreeDroidUI test suite"
```

---

## Done When

- `swift test` in `FreeDroidUI` passes, including all snapshot tests for both themes.
- The app launches and shows a complete design-system gallery.
- Toggling between dark and light themes re-themes every component in place.
- SwiftLint passes.
- CI workflow updated to include UI test suite.
- Every signature interaction moment from the spec (Living device ring, Liquid transfer fill, Spatial photo grid / masonry, Sidebar flow transitions, Floating command strip, Toast pearls) has a working component in the package.

## Self-Review

- All signature components from spec §8.3 → implemented in Tasks 10, 12, 13, 14.
- Theme system from §8.2 → Tasks 4, 16 (`@Environment(\.theme)`, no hex outside tokens).
- Motion presets from §8.4 → Task 4 (three named springs).
- Snapshot tests for both themes → Task 5 (shared helper), used in Tasks 7, 10, 12, 14.
- No comments in any of the above code, matching spec §8.5.
