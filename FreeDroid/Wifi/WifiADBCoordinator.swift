import Foundation
import FreeDroidADB

enum WifiADBError: Error, LocalizedError {
    case pairFailed(String)
    case connectFailed(String)
    case invalidAddress

    var errorDescription: String? {
        switch self {
        case .pairFailed(let msg): return "Pairing failed: \(msg)"
        case .connectFailed(let msg): return "Connect failed: \(msg)"
        case .invalidAddress: return "Enter a valid host:port (e.g. 192.168.1.5:37561)"
        }
    }
}

actor WifiADBCoordinator {
    private let adbServer: ADBServer
    private let store: WifiEndpointStore

    init(adbServer: ADBServer, store: WifiEndpointStore) {
        self.adbServer = adbServer
        self.store = store
    }

    func start() async {
        let saved = await store.all()
        for endpoint in saved {
            _ = try? await connect(endpoint)
        }
    }

    func pair(host: String, port: Int, code: String) async throws {
        let runner = await adbServer.runner(for: "\(host):\(port)")
        let output = try await runner.runWithStdin(.pair(host: host, port: port), stdin: code, timeout: .seconds(30))
        let combined = output.stdout + output.stderr
        if combined.lowercased().contains("failed") || combined.lowercased().contains("error") {
            throw WifiADBError.pairFailed(combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let endpoint = WifiEndpoint(host: host, port: port, displayName: nil, lastConnected: nil)
        try? await store.add(endpoint)
        _ = try await connect(endpoint)
    }

    @discardableResult
    func connect(_ endpoint: WifiEndpoint) async throws -> ADBProcessOutput {
        let runner = await adbServer.runner(for: "\(endpoint.host):\(endpoint.port)")
        let output = try await runner.run(.connect(host: endpoint.host, port: endpoint.port), timeout: .seconds(8))
        let combined = output.stdout + output.stderr
        if combined.lowercased().contains("failed") || combined.lowercased().contains("unable") {
            throw WifiADBError.connectFailed(combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try? await store.update(lastConnected: Date(), for: endpoint)
        return output
    }

    func disconnect(_ endpoint: WifiEndpoint) async throws {
        let runner = await adbServer.runner(for: "\(endpoint.host):\(endpoint.port)")
        _ = try? await runner.run(.disconnect(host: endpoint.host, port: endpoint.port), timeout: .seconds(5))
        try? await store.remove(endpoint)
    }

    func savedEndpoints() async -> [WifiEndpoint] {
        await store.all()
    }
}
