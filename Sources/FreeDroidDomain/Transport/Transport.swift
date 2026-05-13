import Foundation

public protocol TransferProgressSink: Sendable {
    func report(bytesTransferred: Int64, totalBytes: Int64?)
}

public protocol Transport: AnyObject, Sendable {
    var deviceID: DeviceID { get }
    var capabilities: TransportCapabilities { get }
    var info: DeviceInfo { get async throws }

    func list(_ path: RemotePath) async throws -> [RemoteEntry]
    func stat(_ path: RemotePath) async throws -> RemoteEntry
    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data
    func write(_ path: RemotePath, data: Data, offset: Int64) async throws
    func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64
    func upload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64
    func mkdir(_ path: RemotePath) async throws
    func remove(_ path: RemotePath) async throws
    func rename(_ from: RemotePath, to destination: RemotePath) async throws
    func close() async
}

public extension Transport {
    func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
        let entry = try await stat(path)
        let total = entry.sizeBytes ?? 0
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        let chunkSize = 1 << 20
        var offset: Int64 = 0
        var bytes: Int64 = 0
        while offset < total || total == 0 {
            try Task.checkCancellation()
            let length = total == 0 ? chunkSize : Int(min(Int64(chunkSize), total - offset))
            let chunk = try await read(path, offset: offset, length: length)
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
            offset += Int64(chunk.count)
            bytes += Int64(chunk.count)
            progress?.report(bytesTransferred: bytes, totalBytes: total > 0 ? total : nil)
            if total == 0 { break }
        }
        return bytes
    }

    func upload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64 {
        let data = try Data(contentsOf: source)
        try await write(path, data: data, offset: 0)
        let bytes = Int64(data.count)
        progress?.report(bytesTransferred: bytes, totalBytes: bytes)
        return bytes
    }
}
