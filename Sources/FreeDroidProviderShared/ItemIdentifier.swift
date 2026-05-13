import Foundation
@_exported import FreeDroidDomain

public enum ItemIdentifier {
    public static let appleRoot = "NSFileProviderRootContainerItemIdentifier"
    public static let pathPrefix = "p:"

    public static func encode(_ path: RemotePath) -> String {
        if path.isRoot { return appleRoot }
        let data = Data(path.raw.utf8)
        return pathPrefix + data.base64EncodedString()
    }

    public static func decode(_ identifier: String) -> RemotePath? {
        if identifier == appleRoot { return .root }
        guard identifier.hasPrefix(pathPrefix) else { return nil }
        let payload = String(identifier.dropFirst(pathPrefix.count))
        guard let data = Data(base64Encoded: payload),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return RemotePath(raw: raw)
    }
}
