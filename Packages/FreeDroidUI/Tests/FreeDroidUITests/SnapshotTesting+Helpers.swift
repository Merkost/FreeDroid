import AppKit
import SwiftUI
import SnapshotTesting
@testable import FreeDroidUI

@MainActor
func assertSnapshot<V: View>(
    of view: V,
    size: CGSize = CGSize(width: 360, height: 200),
    name: String,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    for theme in [Theme.dark, Theme.light] {
        let suffix = theme.colorScheme == .dark ? "dark" : "light"
        let hosting = NSHostingController(
            rootView: view
                .frame(width: size.width, height: size.height)
                .freeDroidTheme(theme)
        )
        hosting.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(
            of: hosting.view,
            as: .image(size: size),
            named: "\(name)-\(suffix)",
            file: file,
            testName: testName,
            line: line
        )
    }
}
