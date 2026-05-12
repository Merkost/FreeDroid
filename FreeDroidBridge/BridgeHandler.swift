import Foundation
import FreeDroidDomain
import FreeDroidIPC
import os.log

private let handlerLogger = Logger(subsystem: "com.merkost.freedroid", category: "bridge")

actor BridgeHandler {
    private let sessions: BridgeSessions
    private var listCache: [ListingCacheKey: ListingCacheValue] = [:]
    private let listingTTL: TimeInterval = 5

    init() throws {
        self.sessions = try BridgeSessions()
    }

    private struct ListingCacheKey: Hashable {
        let device: String
        let path: String
    }

    private struct ListingCacheValue {
        let entries: [RemoteEntry]
        let expiresAt: Date
    }

    private func cachedListing(deviceID: DeviceID, path: RemotePath) -> [RemoteEntry]? {
        let key = ListingCacheKey(device: deviceID.raw, path: path.raw)
        guard let value = listCache[key], value.expiresAt > Date() else { return nil }
        return value.entries
    }

    private func storeListing(deviceID: DeviceID, path: RemotePath, entries: [RemoteEntry]) {
        let key = ListingCacheKey(device: deviceID.raw, path: path.raw)
        listCache[key] = ListingCacheValue(entries: entries, expiresAt: Date().addingTimeInterval(listingTTL))
    }

    private func invalidateListing(deviceID: DeviceID, path: RemotePath) {
        let key = ListingCacheKey(device: deviceID.raw, path: path.raw)
        listCache.removeValue(forKey: key)
    }

    func handle(payload: Data) async -> Data {
        do {
            let request = try IPCCoder.decoder.decode(IPCRequest.self, from: payload)
            handlerLogger.info("Bridge handling: \(String(describing: request), privacy: .public)")
            let response = try await execute(request)
            return try IPCCoder.encoder.encode(response)
        } catch let error as TransportError {
            handlerLogger.error("Transport error: \(String(describing: error), privacy: .public)")
            let response = IPCResponse.failure(.transport(error))
            return (try? IPCCoder.encoder.encode(response)) ?? Data()
        } catch {
            handlerLogger.error("Bridge handle error: \(String(describing: error), privacy: .public)")
            let response = IPCResponse.failure(.decodingFailed(String(describing: error)))
            return (try? IPCCoder.encoder.encode(response)) ?? Data()
        }
    }

    private func execute(_ request: IPCRequest) async throws -> IPCResponse {
        switch request {
        case let .list(deviceID, path):
            if let cached = cachedListing(deviceID: deviceID, path: path) {
                return .entries(cached)
            }
            let entries = try await sessions.session(for: deviceID.raw).list(path)
            storeListing(deviceID: deviceID, path: path, entries: entries)
            return .entries(entries)
        case let .stat(deviceID, path):
            return .entry(try await sessions.session(for: deviceID.raw).stat(path))
        case let .read(deviceID, path, offset, length):
            return .data(try await sessions.session(for: deviceID.raw).read(path, offset: offset, length: length))
        case let .write(deviceID, path, data, offset):
            try await sessions.session(for: deviceID.raw).write(path, data: data, offset: offset)
            if let parent = path.parent { invalidateListing(deviceID: deviceID, path: parent) }
            return .empty
        case let .mkdir(deviceID, path):
            try await sessions.session(for: deviceID.raw).mkdir(path)
            if let parent = path.parent { invalidateListing(deviceID: deviceID, path: parent) }
            return .empty
        case let .remove(deviceID, path):
            try await sessions.session(for: deviceID.raw).remove(path)
            if let parent = path.parent { invalidateListing(deviceID: deviceID, path: parent) }
            return .empty
        case let .rename(deviceID, from, to):
            try await sessions.session(for: deviceID.raw).rename(from, to: to)
            if let parent = from.parent { invalidateListing(deviceID: deviceID, path: parent) }
            if let parent = to.parent { invalidateListing(deviceID: deviceID, path: parent) }
            return .empty
        case let .fetchToFile(deviceID, path, destination):
            _ = try await sessions.session(for: deviceID.raw)
                .fetch(path, into: URL(fileURLWithPath: destination), progress: nil)
            return .empty
        case let .uploadFromFile(deviceID, source, path):
            _ = try await sessions.session(for: deviceID.raw)
                .upload(from: URL(fileURLWithPath: source), to: path, progress: nil)
            if let parent = path.parent { invalidateListing(deviceID: deviceID, path: parent) }
            return .empty
        }
    }
}
