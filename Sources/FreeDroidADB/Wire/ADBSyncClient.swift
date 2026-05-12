import Foundation
import FreeDroidDomain

public struct SyncEntry: Sendable {
    public let name: String
    public let mode: UInt32
    public let size: UInt64
    public let uid: UInt32
    public let gid: UInt32
    public let atime: UInt64
    public let mtime: UInt64
    public let ctime: UInt64

    public var isDirectory: Bool {
        (mode & 0o170000) == 0o040000
    }

    public var isSymlink: Bool {
        (mode & 0o170000) == 0o120000
    }
}

public typealias TransferProgressSink = @Sendable (_ bytesTransferred: Int64, _ totalBytes: Int64?) -> Void

public actor ADBSyncClient {
    private let connection: ADBWireConnection

    public init(connection: ADBWireConnection) {
        self.connection = connection
    }

    public static func open(serial: String, host: String = "127.0.0.1", port: UInt16 = 5037) async throws -> ADBSyncClient {
        let hostClient = ADBHostClient(host: host, port: port)
        let conn = try await hostClient.openTransport(serial: serial)
        try await conn.writeHostMessage("sync:")
        try await conn.readOKAY()
        return ADBSyncClient(connection: conn)
    }

    public nonisolated func close() {
        connection.cancel()
    }

    public func listV2(remotePath: String) async throws -> [SyncEntry] {
        let pathData = Data(remotePath.utf8)
        var req = Data()
        req.append(contentsOf: "LST2".utf8)
        req.appendU32LE(UInt32(pathData.count))
        req.append(pathData)
        try await connection.sendRaw(req)

        var entries: [SyncEntry] = []
        while true {
            let id = try await connection.readBytes(4)
            let idStr = String(decoding: id, as: UTF8.self)
            let length = try await connection.readU32LE()
            switch idStr {
            case "DNT2":
                let entry = try await readDnt2Entry(length: Int(length))
                if entry.name != "." && entry.name != ".." {
                    entries.append(entry)
                }
            case "DONE":
                return entries
            case "FAIL":
                let msg = try await connection.readString(Int(length))
                throw ADBWireError.syncFailed(msg)
            default:
                throw ADBWireError.framingViolation(
                    context: "listV2 unexpected id '\(idStr)'",
                    firstBytes: Array(id)
                )
            }
        }
    }

    private func readDnt2Entry(length: Int) async throws -> SyncEntry {
        let payload = try await connection.readBytes(length)
        guard payload.count >= 36 else {
            throw ADBWireError.framingViolation(
                context: "DNT2 payload < 36 bytes (got \(payload.count))",
                firstBytes: Array(payload.prefix(16))
            )
        }
        let mode = payload.readU32LE(at: 0)
        let size64 = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 16 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 8, as: UInt64.self).littleEndian
        }
        let uid = payload.readU32LE(at: 16)
        let gid = payload.readU32LE(at: 20)
        let atime = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 32 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 24, as: UInt64.self).littleEndian
        }
        let mtime = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 40 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 32, as: UInt64.self).littleEndian
        }
        let ctime = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 48 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 40, as: UInt64.self).littleEndian
        }
        let nameLen = payload.withUnsafeBytes { ptr -> UInt32 in
            guard ptr.count >= 52 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 48, as: UInt32.self).littleEndian
        }
        let nameStart = 52
        guard payload.count >= nameStart + Int(nameLen) else {
            throw ADBWireError.framingViolation(
                context: "DNT2 name truncated (need \(nameStart + Int(nameLen)), have \(payload.count))",
                firstBytes: Array(payload.prefix(16))
            )
        }
        let name = String(decoding: payload[nameStart..<nameStart + Int(nameLen)], as: UTF8.self)
        return SyncEntry(
            name: name,
            mode: mode,
            size: size64,
            uid: uid,
            gid: gid,
            atime: atime,
            mtime: mtime,
            ctime: ctime
        )
    }

    public func statV2(remotePath: String) async throws -> SyncEntry {
        let pathData = Data(remotePath.utf8)
        var req = Data()
        req.append(contentsOf: "STA2".utf8)
        req.appendU32LE(UInt32(pathData.count))
        req.append(pathData)
        try await connection.sendRaw(req)

        let id = try await connection.readBytes(4)
        let idStr = String(decoding: id, as: UTF8.self)
        let length = try await connection.readU32LE()
        switch idStr {
        case "STA2":
            let entry = try await readSta2Entry(path: remotePath, length: Int(length))
            return entry
        case "FAIL":
            let msg = try await connection.readString(Int(length))
            throw ADBWireError.syncFailed(msg)
        default:
            throw ADBWireError.framingViolation(
                context: "statV2 unexpected id '\(idStr)'",
                firstBytes: Array(id)
            )
        }
    }

    private func readSta2Entry(path: String, length: Int) async throws -> SyncEntry {
        let payload = try await connection.readBytes(length)
        guard payload.count >= 24 else {
            throw ADBWireError.framingViolation(
                context: "STA2 payload < 24 bytes (got \(payload.count))",
                firstBytes: Array(payload.prefix(16))
            )
        }
        let mode = payload.readU32LE(at: 0)
        let size64 = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 16 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 8, as: UInt64.self).littleEndian
        }
        let uid = payload.readU32LE(at: 16)
        let gid = payload.readU32LE(at: 20)
        let atime = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 32 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 24, as: UInt64.self).littleEndian
        }
        let mtime = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 40 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 32, as: UInt64.self).littleEndian
        }
        let ctime = payload.withUnsafeBytes { ptr -> UInt64 in
            guard ptr.count >= 48 else { return 0 }
            return ptr.loadUnaligned(fromByteOffset: 40, as: UInt64.self).littleEndian
        }
        let name = (path as NSString).lastPathComponent
        return SyncEntry(
            name: name,
            mode: mode,
            size: size64,
            uid: uid,
            gid: gid,
            atime: atime,
            mtime: mtime,
            ctime: ctime
        )
    }

    public func recv(remotePath: String, to localURL: URL, progress: TransferProgressSink?) async throws -> Int64 {
        let pathData = Data(remotePath.utf8)
        var req = Data()
        req.append(contentsOf: "RECV".utf8)
        req.appendU32LE(UInt32(pathData.count))
        req.append(pathData)
        try await connection.sendRaw(req)

        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: localURL)
        defer { try? handle.close() }
        var total: Int64 = 0

        while true {
            try Task.checkCancellation()
            let id = try await connection.readBytes(4)
            let length = try await connection.readU32LE()
            let idStr = String(decoding: id, as: UTF8.self)
            switch idStr {
            case "DATA":
                let chunk = try await connection.readBytes(Int(length))
                try handle.write(contentsOf: chunk)
                total += Int64(length)
                progress?(total, nil)
            case "DONE":
                return total
            case "FAIL":
                let msg = try await connection.readString(Int(length))
                throw ADBWireError.syncFailed(msg)
            default:
                throw ADBWireError.framingViolation(
                    context: "recv unexpected id '\(idStr)'",
                    firstBytes: Array(id)
                )
            }
        }
    }

    public func send(from localURL: URL, remotePath: String, mode: UInt32 = 0o100644) async throws -> Int64 {
        let remoteArg = "\(remotePath),\(mode)"
        let argData = Data(remoteArg.utf8)
        var req = Data()
        req.append(contentsOf: "SEND".utf8)
        req.appendU32LE(UInt32(argData.count))
        req.append(argData)
        try await connection.sendRaw(req)

        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }

        var total: Int64 = 0
        let chunkSize = 64 * 1024

        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            var packet = Data()
            packet.append(contentsOf: "DATA".utf8)
            packet.appendU32LE(UInt32(chunk.count))
            packet.append(chunk)
            try await connection.sendRaw(packet)
            total += Int64(chunk.count)
        }

        let mtime = UInt32(Date().timeIntervalSince1970)
        var done = Data()
        done.append(contentsOf: "DONE".utf8)
        done.appendU32LE(mtime)
        try await connection.sendRaw(done)

        let id = try await connection.readBytes(4)
        let idStr = String(decoding: id, as: UTF8.self)
        let length = try await connection.readU32LE()
        switch idStr {
        case "OKAY":
            _ = try await connection.readBytes(Int(length))
            return total
        case "FAIL":
            let msg = try await connection.readString(Int(length))
            throw ADBWireError.syncFailed(msg)
        default:
            throw ADBWireError.framingViolation(
                context: "send completion unexpected id '\(idStr)'",
                firstBytes: Array(id)
            )
        }
    }
}
