import Foundation

public enum ADBOutputParser {
    public struct LsEntry: Hashable, Sendable {
        public let name: String
        public let size: Int64
        public let modifiedAt: String
        public let isDirectory: Bool
    }

    public static func parseDeviceList(_ output: String) -> [ADBDeviceListEntry] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line -> ADBDeviceListEntry? in
            let lineString = String(line)
            if lineString.hasPrefix("List of devices") { return nil }
            return parseDeviceLine(lineString)
        }
    }

    static func parseDeviceLine(_ line: String) -> ADBDeviceListEntry? {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        let serial = parts[0]
        let stateString = parts[1]
        let state = ADBDeviceState(rawValue: stateString) ?? .unknown

        var product: String?
        var model: String?
        var device: String?
        var transportId: String?
        for token in parts.dropFirst(2) {
            let kv = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "product": product = kv[1]
            case "model": model = kv[1]
            case "device": device = kv[1]
            case "transport_id": transportId = kv[1]
            default: break
            }
        }

        return ADBDeviceListEntry(
            serial: serial,
            state: state,
            product: product,
            model: model,
            device: device,
            transportId: transportId
        )
    }

    public static func parseLsLine(_ line: String) -> LsEntry? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 8 else { return nil }
        let permString = parts[0]
        let isDir = permString.first == "d"
        guard let size = Int64(parts[4]) else { return nil }
        let date = parts[5]
        let time = parts[6]
        let name = parts[7...].joined(separator: " ")
        return LsEntry(
            name: name,
            size: size,
            modifiedAt: "\(date) \(time)",
            isDirectory: isDir
        )
    }
}
