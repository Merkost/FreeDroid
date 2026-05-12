import Foundation

struct SyncV2Stat: Sendable {
    let mode: UInt32
    let nlink: UInt32
    let uid: UInt32
    let gid: UInt32
    let size: UInt64
    let atime: Int64
    let mtime: Int64
    let ctime: Int64

    var isDirectory: Bool { (mode & 0o170000) == 0o040000 }
    var isSymlink: Bool { (mode & 0o170000) == 0o120000 }

    static let wireSize = 72

    static func decode(idAndBody data: Data) throws -> SyncV2Stat {
        guard data.count >= wireSize else {
            throw ADBWireError.framingViolation(
                context: "SyncV2Stat needs \(wireSize) bytes, got \(data.count)",
                firstBytes: Array(data.prefix(16))
            )
        }
        let id = data.subdata(in: 0..<4)
        guard id == Data("STA2".utf8) else {
            throw ADBWireError.framingViolation(
                context: "SyncV2Stat id != STA2",
                firstBytes: Array(data.prefix(16))
            )
        }
        let error = data.readU32LE(at: 4)
        if error != 0 {
            throw ADBWireError.syncFailed("STA2 errno \(error)")
        }
        return SyncV2Stat(
            mode: data.readU32LE(at: 24),
            nlink: data.readU32LE(at: 28),
            uid: data.readU32LE(at: 32),
            gid: data.readU32LE(at: 36),
            size: data.readU64LE(at: 40),
            atime: data.readI64LE(at: 48),
            mtime: data.readI64LE(at: 56),
            ctime: data.readI64LE(at: 64)
        )
    }
}

struct SyncV2Dent: Sendable {
    let name: String
    let mode: UInt32
    let uid: UInt32
    let gid: UInt32
    let size: UInt64
    let atime: Int64
    let mtime: Int64
    let ctime: Int64

    var isDirectory: Bool { (mode & 0o170000) == 0o040000 }
    var isSymlink: Bool { (mode & 0o170000) == 0o120000 }

    static let fixedHeaderSize = 76
    static let bodyAfterId = 72
}

struct SyncV1Stat: Sendable {
    let mode: UInt32
    let size: UInt64
    let mtime: Int64

    var isDirectory: Bool { (mode & 0o170000) == 0o040000 }
    var isSymlink: Bool { (mode & 0o170000) == 0o120000 }

    static let wireSize = 16

    static func decode(idAndBody data: Data) throws -> SyncV1Stat {
        guard data.count >= wireSize else {
            throw ADBWireError.framingViolation(
                context: "SyncV1Stat needs \(wireSize) bytes, got \(data.count)",
                firstBytes: Array(data.prefix(16))
            )
        }
        let id = data.subdata(in: 0..<4)
        guard id == Data("STAT".utf8) else {
            throw ADBWireError.framingViolation(
                context: "SyncV1Stat id != STAT",
                firstBytes: Array(data.prefix(16))
            )
        }
        return SyncV1Stat(
            mode: data.readU32LE(at: 4),
            size: UInt64(data.readU32LE(at: 8)),
            mtime: Int64(data.readU32LE(at: 12))
        )
    }
}
