import SwiftUI
import FreeDroidUI

public struct DeviceEmptyState: View {
    public init() {}

    public var body: some View {
        EmptyState(
            icon: "cable.connector",
            title: "No devices found",
            message: "Plug in your Android phone with a USB cable. We'll detect it automatically."
        )
    }
}
