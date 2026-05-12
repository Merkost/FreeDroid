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
            try Task.checkCancellation()
            let id = try await connection.readBytes(4)
            let idStr = String(decoding: id, as: UTF8.self)
            switch idStr {
            case "DONE":
                _ = try await connection.readU32LE()
                return entries
            case "FAIL":
                let length = try await connection.readU32LE()
                let msg = try await connection.readString(Int(length))
                throw ADBWireError.syncFailed(msg)
            case "DNT2":
                let entry = try await readDnt2Entry()
                if entry.name != "." && entry.name != ".." {
                    entries.append(entry)
                }
            default:
                throw ADBWireError.framingViolation(
                    context: "listV2 unexpected id '\(idStr)'",
                    firstBytes: Array(id)
                )
            }
        }
    }

    private func readDnt2Entry() async throws -> SyncEntry {
        let header = try await connection.readBytes(SyncV2Dent.bodyAfterId)
        guard header.count == SyncV2Dent.bodyAfterId else {
            throw ADBWireError.framingViolation(
                context: "DNT2 header read short (got \(header.count))",
                firstBytes: Array(header.prefix(16))
            )
        }
        let mode = header.readU32LE(at: 20)
        let uid = header.readU32LE(at: 28)
        let gid = header.readU32LE(at: 32)
        let size = header.readU64LE(at: 36)
        let atime = header.readI64LE(at: 44)
        let mtime = header.readI64LE(at: 52)
        let ctime = header.readI64LE(at: 60)
        let nameLen = header.readU32LE(at: 68)
        let nameBytes = try await connection.readBytes(Int(nameLen))
        let name = String(decoding: nameBytes, as: UTF8.self)
        return SyncEntry(
            name: name,
            mode: mode,
            size: size,
            uid: uid,
            gid: gid,
            atime: UInt64(bitPattern: atime),
            mtime: UInt64(bitPattern: mtime),
            ctime: UInt64(bitPattern: ctime)
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
        switch idStr {
        case "STA2":
            let body = try await connection.readBytes(SyncV2Stat.wireSize - 4)
            var combined = Data()
            combined.append(id)
            combined.append(body)
            let stat = try SyncV2Stat.decode(idAndBody: combined)
            return SyncEntry(
                name: (remotePath as NSString).lastPathComponent,
                mode: stat.mode,
                size: stat.size,
                uid: stat.uid,
                gid: stat.gid,
                atime: UInt64(bitPattern: stat.atime),
                mtime: UInt64(bitPattern: stat.mtime),
                ctime: UInt64(bitPattern: stat.ctime)
            )
        case "FAIL":
            let length = try await connection.readU32LE()
            let msg = try await connection.readString(Int(length))
            throw ADBWireError.syncFailed(msg)
        default:
            throw ADBWireError.framingViolation(
                context: "statV2 unexpected id '\(idStr)'",
                firstBytes: Array(id)
            )
        }
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
