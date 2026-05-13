import Foundation

struct SyncRequest: Sendable {
    let id: String
    let argument: String

    func encode() -> Data {
        let argData = Data(argument.utf8)
        var data = Data()
        data.append(contentsOf: id.utf8.prefix(4))
        data.appendU32LE(UInt32(argData.count))
        data.append(argData)
        return data
    }
}

struct SyncResponse: Sendable {
    let id: String
    let length: UInt32
}

extension Data {
    mutating func appendU32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readU32LE(at offset: Int = 0) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return subdata(in: offset..<offset + 4).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    func readU64LE(at offset: Int) -> UInt64 {
        guard count >= offset + 8 else { return 0 }
        return subdata(in: offset..<offset + 8).withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).littleEndian
        }
    }

    func readI64LE(at offset: Int) -> Int64 {
        Int64(bitPattern: readU64LE(at: offset))
    }
}
