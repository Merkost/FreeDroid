import Foundation

public actor ADBHostClient {
    private let host: String
    private let port: UInt16

    public init(host: String = "127.0.0.1", port: UInt16 = 5037) {
        self.host = host
        self.port = port
    }

    public func version() async throws -> Int {
        let conn = try await ADBWireConnection.connect(host: host, port: port)
        defer { conn.cancel() }
        try await conn.writeHostMessage("host:version")
        try await conn.readOKAY()
        let lenHex = try await conn.readBytes(4)
        let len = Int(String(decoding: lenHex, as: UTF8.self), radix: 16) ?? 0
        let payload = try await conn.readString(len)
        return Int(payload, radix: 16) ?? 0
    }

    public func devices() async throws -> [ADBDeviceListEntry] {
        let conn = try await ADBWireConnection.connect(host: host, port: port)
        defer { conn.cancel() }
        try await conn.writeHostMessage("host:devices-l")
        try await conn.readOKAY()
        let lenHex = try await conn.readBytes(4)
        let len = Int(String(decoding: lenHex, as: UTF8.self), radix: 16) ?? 0
        let payload = try await conn.readString(len)
        return ADBOutputParser.parseDeviceList(payload)
    }

    public func features(serial: String) async throws -> [String] {
        let conn = try await ADBWireConnection.connect(host: host, port: port)
        defer { conn.cancel() }
        try await conn.writeHostMessage("host-serial:\(serial):features")
        try await conn.readOKAY()
        let lenHex = try await conn.readBytes(4)
        let len = Int(String(decoding: lenHex, as: UTF8.self), radix: 16) ?? 0
        let payload = try await conn.readString(len)
        return payload.split(separator: ",").map(String.init)
    }

    public func kill() async throws {
        let conn = try await ADBWireConnection.connect(host: host, port: port)
        defer { conn.cancel() }
        try await conn.writeHostMessage("host:kill")
        try await conn.readOKAY()
    }

    func openTransport(serial: String) async throws -> ADBWireConnection {
        let conn = try await ADBWireConnection.connect(host: host, port: port)
        try await conn.writeHostMessage("host:transport:\(serial)")
        try await conn.readOKAY()
        return conn
    }
}
