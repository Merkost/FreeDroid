import Foundation
import AsyncAlgorithms

public enum ADBAuthorizationStatus: Hashable, Sendable {
    case authorized
    case unauthorized
    case missing
}

public actor ADBAuthorizationObserver {
    private let server: ADBServer
    private let serial: String
    private let pollInterval: Duration

    public init(server: ADBServer, serial: String, pollInterval: Duration = .milliseconds(750)) {
        self.server = server
        self.serial = serial
        self.pollInterval = pollInterval
    }

    public func status() async throws -> ADBAuthorizationStatus {
        let devices = try await server.listDevices()
        guard let device = devices.first(where: { $0.serial == serial }) else {
            return .missing
        }
        switch device.state {
        case .device: return .authorized
        case .unauthorized: return .unauthorized
        default: return .missing
        }
    }

    public func observe() -> AsyncThrowingStream<ADBAuthorizationStatus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var last: ADBAuthorizationStatus?
                while !Task.isCancelled {
                    do {
                        let current = try await self.status()
                        if current != last {
                            continuation.yield(current)
                            last = current
                        }
                        if current == .authorized { continuation.finish(); return }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    try? await Task.sleep(for: pollInterval)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
