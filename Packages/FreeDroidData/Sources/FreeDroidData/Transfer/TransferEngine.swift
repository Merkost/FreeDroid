import Foundation
import FreeDroidDomain

public struct TransferEngine: Sendable {
    let transport: any Transport
    let chunkSize: Int

    public init(transport: any Transport, chunkSize: Int = 4 * 1024 * 1024) {
        self.transport = transport
        self.chunkSize = chunkSize
    }

    public func pull(_ path: RemotePath, to localURL: URL) async throws -> Int64 {
        let entry = try await transport.stat(path)
        let total = entry.sizeBytes ?? 0
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: localURL)
        defer { try? handle.close() }
        var offset: Int64 = 0
        while offset < total {
            try Task.checkCancellation()
            let length = Int(min(Int64(chunkSize), total - offset))
            let chunk = try await transport.read(path, offset: offset, length: length)
            try handle.write(contentsOf: chunk)
            offset += Int64(chunk.count)
            if chunk.isEmpty { break }
        }
        return offset
    }

    public func push(localURL: URL, to remote: RemotePath) async throws -> Int64 {
        let data = try Data(contentsOf: localURL)
        try await transport.write(remote, data: data, offset: 0)
        return Int64(data.count)
    }
}
