import Foundation

public protocol Transport: AnyObject, Sendable {
    var deviceID: DeviceID { get }
    var capabilities: TransportCapabilities { get }
    var info: DeviceInfo { get async throws }

    func list(_ path: RemotePath) async throws -> [RemoteEntry]
    func stat(_ path: RemotePath) async throws -> RemoteEntry
    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data
    func write(_ path: RemotePath, data: Data, offset: Int64) async throws
    func mkdir(_ path: RemotePath) async throws
    func remove(_ path: RemotePath) async throws
    func rename(_ from: RemotePath, to: RemotePath) async throws
    func close() async
}
