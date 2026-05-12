import Foundation
import Dependencies

private final class SendableFileManagerBox: @unchecked Sendable {
    let value: FileManager
    init(_ fileManager: FileManager) { self.value = fileManager }
}

private final class SendableBundleBox: @unchecked Sendable {
    let value: Bundle
    init(_ bundle: Bundle) { self.value = bundle }
}

private enum FileManagerKey: DependencyKey {
    static let liveValue = SendableFileManagerBox(.default)
    static let testValue = SendableFileManagerBox(.default)
}

private enum BundleKey: DependencyKey {
    static let liveValue = SendableBundleBox(.main)
    static let testValue = SendableBundleBox(.main)
}

public extension DependencyValues {
    var fileManager: FileManager {
        get { self[FileManagerKey.self].value }
        set { self[FileManagerKey.self] = SendableFileManagerBox(newValue) }
    }

    var bundle: Bundle {
        get { self[BundleKey.self].value }
        set { self[BundleKey.self] = SendableBundleBox(newValue) }
    }
}
