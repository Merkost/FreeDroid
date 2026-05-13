import Foundation

public actor ADBSyncConnectionPool {
    private struct IdleEntry {
        let connection: ADBWireConnection
        let idleSince: ContinuousClock.Instant
    }

    private let serial: String
    private let host: String
    private let port: UInt16
    private let maxIdle: Int
    private let idleTimeout: Duration
    private let clock = ContinuousClock()
    private var idle: [IdleEntry] = []
    private var sweepTask: Task<Void, Never>?

    public init(
        serial: String,
        host: String = "127.0.0.1",
        port: UInt16 = 5037,
        maxIdle: Int = 4,
        idleTimeout: Duration = .seconds(60)
    ) {
        self.serial = serial
        self.host = host
        self.port = port
        self.maxIdle = max(1, maxIdle)
        self.idleTimeout = idleTimeout
    }

    public func withConnection<T>(
        _ body: (ADBSyncClient) async throws -> T
    ) async throws -> T {
        let connection = try await borrow()
        do {
            let result = try await body(ADBSyncClient(connection: connection))
            giveBack(connection)
            startSweepIfNeeded()
            return result
        } catch {
            connection.cancel()
            throw error
        }
    }

    public func drain() {
        sweepTask?.cancel()
        sweepTask = nil
        let pending = idle
        idle.removeAll()
        for entry in pending {
            entry.connection.cancel()
        }
    }

    public var idleCount: Int { idle.count }

    private func borrow() async throws -> ADBWireConnection {
        if let warm = idle.popLast()?.connection { return warm }
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
        idle.append(IdleEntry(connection: connection, idleSince: clock.now))
    }

    private func startSweepIfNeeded() {
        if sweepTask != nil { return }
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                guard let self else { return }
                await self.sweepStale()
            }
        }
    }

    private func sweepStale() {
        let now = clock.now
        var kept: [IdleEntry] = []
        for entry in idle {
            if (now - entry.idleSince) > idleTimeout {
                entry.connection.cancel()
            } else {
                kept.append(entry)
            }
        }
        idle = kept
        if idle.isEmpty {
            sweepTask?.cancel()
            sweepTask = nil
        }
    }
}
