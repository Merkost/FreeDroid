import Foundation

public actor ADBSyncConnectionPool {
    private let serial: String
    private let host: String
    private let port: UInt16
    private let maxIdle: Int
    private var idle: [ADBWireConnection] = []
    private var openCount = 0

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
            let client = ADBSyncClient(connection: connection)
            let result = try await body(client)
            await giveBack(connection)
            return result
        } catch {
            await discard(connection)
            throw error
        }
    }

    public func drain() async {
        let pending = idle
        idle.removeAll()
        openCount = 0
        for connection in pending {
            connection.cancel()
        }
    }

    private func borrow() async throws -> ADBWireConnection {
        if let warm = idle.popLast() {
            return warm
        }
        let hostClient = ADBHostClient(host: host, port: port)
        let connection = try await hostClient.openTransport(serial: serial)
        try await connection.writeHostMessage("sync:")
        try await connection.readOKAY()
        openCount += 1
        return connection
    }

    private func giveBack(_ connection: ADBWireConnection) async {
        if idle.count >= maxIdle {
            connection.cancel()
            openCount = max(0, openCount - 1)
            return
        }
        idle.append(connection)
    }

    private func discard(_ connection: ADBWireConnection) async {
        connection.cancel()
        openCount = max(0, openCount - 1)
    }
}
