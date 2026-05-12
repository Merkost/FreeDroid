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
