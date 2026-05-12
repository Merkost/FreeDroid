import Foundation
import FreeDroidDomain
import FreeDroidIPC

actor BridgeHandler {
    private let sessions: BridgeSessions

    init() throws {
        self.sessions = try BridgeSessions()
    }

    func handle(payload: Data) async -> Data {
        do {
            let request = try IPCCoder.decoder.decode(IPCRequest.self, from: payload)
            let response = try await execute(request)
            return try IPCCoder.encoder.encode(response)
        } catch let error as TransportError {
            let response = IPCResponse.failure(.transport(error))
            return (try? IPCCoder.encoder.encode(response)) ?? Data()
        } catch {
            let response = IPCResponse.failure(.decodingFailed(String(describing: error)))
            return (try? IPCCoder.encoder.encode(response)) ?? Data()
        }
    }

    private func execute(_ request: IPCRequest) async throws -> IPCResponse {
        switch request {
        case let .list(deviceID, path):
            return .entries(try await sessions.session(for: deviceID.raw).list(path))
        case let .stat(deviceID, path):
            return .entry(try await sessions.session(for: deviceID.raw).stat(path))
        case let .read(deviceID, path, offset, length):
            return .data(try await sessions.session(for: deviceID.raw).read(path, offset: offset, length: length))
        case let .write(deviceID, path, data, offset):
            try await sessions.session(for: deviceID.raw).write(path, data: data, offset: offset)
            return .empty
        case let .mkdir(deviceID, path):
            try await sessions.session(for: deviceID.raw).mkdir(path)
            return .empty
        case let .remove(deviceID, path):
            try await sessions.session(for: deviceID.raw).remove(path)
            return .empty
        case let .rename(deviceID, from, to):
            try await sessions.session(for: deviceID.raw).rename(from, to: to)
            return .empty
        }
    }
}
