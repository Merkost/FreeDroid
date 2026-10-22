import Foundation
import FreeDroidDomain
import FreeDroidADB

public struct TransferEngine: Sendable {
    let transport: any Transport
    let chunkSize: Int

    public init(transport: any Transport, chunkSize: Int = 4 * 1024 * 1024) {
        self.transport = transport
        self.chunkSize = chunkSize
    }

    public func pull(_ path: RemotePath, to localURL: URL, progress: TransferProgressSink? = nil) async throws -> Int64 {
        try Task.checkCancellation()
        if transport.capabilities.supportsRangeRead == false {
            try? FileManager.default.removeItem(at: localURL)
            let bytes = try await transport.fetch(path, into: localURL, progress: progress)
            try verifyLocalSize(localURL, expected: bytes)
            return bytes
        }
        let entry = try await transport.stat(path)
        let total = entry.sizeBytes ?? 0
        if let localSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value,
           localSize == total {
            return total
        }
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
            progress?.report(bytesTransferred: offset, totalBytes: total)
            if chunk.isEmpty { break }
        }
        try verifyLocalSize(localURL, expected: offset)
        return offset
    }

    public func push(localURL: URL, to remote: RemotePath, progress: TransferProgressSink? = nil) async throws -> Int64 {
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let expected = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        if let existing = try? await transport.stat(remote), existing.kind == .file, existing.sizeBytes == expected {
            return expected
        }
        let bytes: Int64
        if let adb = transport as? ADBSession {
            bytes = try await adb.uploadResumable(from: localURL, to: remote, progress: progress)
        } else {
            bytes = try await transport.upload(from: localURL, to: remote, progress: progress)
        }
        let remoteSize = (try await transport.stat(remote)).sizeBytes ?? -1
        guard remoteSize == expected, bytes == expected else {
            throw TransportError.ioFailure(
                message: "Transfer verification failed for \(remote.raw): expected \(expected) bytes, got \(remoteSize)"
            )
        }
        return bytes
    }

    private func verifyLocalSize(_ url: URL, expected: Int64) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actual = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actual == expected else {
            throw TransportError.ioFailure(
                message: "Transfer verification failed for \(url.lastPathComponent): expected \(expected) bytes, got \(actual)"
            )
        }
    }
}
