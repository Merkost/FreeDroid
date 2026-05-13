import Foundation

public actor ADBSyncConnectionPool {
    private let serial: String
    private let host: String
    private let port: UInt16
    private let maxIdle: Int
    private var idle: [ADBWireConnection] = []

    public init(serial: String, host: String = "127.0.0.1", port: UInt16 = 5037, maxIdle: Int = 4) {
        self.serial = serial
        self.host = host
        self.port = port
        self.maxIdle = max(1, maxIdle)
    }

    public func withConnection<T>(
        _ body: (ADBSyncClient) async throws -> T
    ) async throws -> T {
        let connection = try await borrow()
        do {
            let result = try await body(ADBSyncClient(connection: connection))
            giveBack(connection)
            return result
        } catch {
            connection.cancel()
            throw error
        }
    }

    public func drain() {
        let pending = idle
        idle.removeAll()
        for connection in pending {
            connection.cancel()
        }
    }

    public var idleCount: Int { idle.count }

    private func borrow() async throws -> ADBWireConnection {
        if let warm = idle.popLast() { return warm }
        let hostClient = ADBHostClient(host: host, port: port)
        let connection = try await hostClient.openTransport(serial: serial)
        try await connection.writeHostMessage("sync:")
        try await connection.readOKAY()
        return connection
    }

    private func giveBack(_ connection: ADBWireConnection) {
        if idle.count >= maxIdle {
            connection.cancel()
            return
        }
        idle.append(connection)
    }
}
