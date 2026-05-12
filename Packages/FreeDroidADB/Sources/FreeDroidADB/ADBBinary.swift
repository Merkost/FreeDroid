import Foundation

public enum ADBBinary {
    public static func path() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["FREEDROID_ADB_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ADBBinaryError.overrideNotExecutable(url)
            }
            return url
        }
        guard let bundled = Bundle.module.url(forResource: "adb", withExtension: nil) else {
            throw ADBBinaryError.notBundled
        }
        return bundled
    }
}

public enum ADBBinaryError: Error, Sendable, Equatable {
    case notBundled
    case overrideNotExecutable(URL)
}
