import Foundation
import FreeDroidDomain
import FreeDroidData
import FreeDroidIPC

actor XPCFileServerHandler {
    private let registry: DeviceRegistry

    init(registry: DeviceRegistry) {
        self.registry = registry
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

    private func transport(for identifier: DeviceID) async throws -> any Transport {
        guard let transport = await registry.transport(for: identifier) else {
            throw TransportError.notConnected
        }
        return transport
    }

    private func execute(_ request: IPCRequest) async throws -> IPCResponse {
        switch request {
        case let .list(deviceID, path):
            return .entries(try await transport(for: deviceID).list(path))
        case let .stat(deviceID, path):
            return .entry(try await transport(for: deviceID).stat(path))
        case let .read(deviceID, path, offset, length):
            return .data(try await transport(for: deviceID).read(path, offset: offset, length: length))
        case let .write(deviceID, path, data, offset):
            try await transport(for: deviceID).write(path, data: data, offset: offset)
            return .empty
        case let .mkdir(deviceID, path):
            try await transport(for: deviceID).mkdir(path)
            return .empty
        case let .remove(deviceID, path):
            try await transport(for: deviceID).remove(path)
            return .empty
        case let .rename(deviceID, from, to):
            try await transport(for: deviceID).rename(from, to: to)
            return .empty
        }
    }
}
