import Foundation
import FreeDroidDomain

public struct FileRepositoryImpl: FileRepository {
    private let registry: DeviceRegistry
    private let cache: ListingCache
    private let deviceID: DeviceID

    public init(registry: DeviceRegistry, cache: ListingCache, deviceID: DeviceID) {
        self.registry = registry
        self.cache = cache
        self.deviceID = deviceID
    }

    private func transport() async throws -> any Transport {
        guard let result = await registry.transport(for: deviceID) else {
            throw TransportError.notConnected
        }
        return result
    }

    public func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        let key = ListingCacheKey(deviceID: deviceID, path: path)
        if let cached = await cache.get(key), !cached.isEmpty { return cached }
        let entries = try await transport().list(path)
        if !entries.isEmpty {
            await cache.put(key: key, value: entries)
        }
        return entries
    }

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        try await transport().stat(path)
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        try await transport().read(path, offset: offset, length: length)
    }

    public func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        try await transport().write(path, data: data, offset: offset)
        await cache.invalidate(deviceID: deviceID, path: path.parent ?? .root)
    }

    public func mkdir(_ path: RemotePath) async throws {
        try await transport().mkdir(path)
        await cache.invalidate(deviceID: deviceID, path: path.parent ?? .root)
    }

    public func remove(_ path: RemotePath) async throws {
        try await transport().remove(path)
        await cache.invalidate(deviceID: deviceID, path: path.parent ?? .root)
    }

    public func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        try await transport().rename(from, to: destination)
        await cache.invalidate(deviceID: deviceID, path: from.parent ?? .root)
        await cache.invalidate(deviceID: deviceID, path: destination.parent ?? .root)
    }
}
