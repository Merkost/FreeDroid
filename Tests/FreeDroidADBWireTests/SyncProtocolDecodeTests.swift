import Foundation
import Testing
@testable import FreeDroidADB

@Suite("SyncProtocol decode")
struct SyncProtocolDecodeTests {
    @Test func decodesRealSta2Frame() throws {
        var buf = Data()
        buf.append(contentsOf: "STA2".utf8)
        buf.appendU32LE(0)
        buf.append(contentsOf: [UInt8](repeating: 0, count: 8))
        buf.append(contentsOf: [UInt8](repeating: 0, count: 8))
        buf.appendU32LE(0o100644)
        buf.appendU32LE(1)
        buf.appendU32LE(1000)
        buf.appendU32LE(1015)
        appendU64LE(into: &buf, 5347282)
        appendI64LE(into: &buf, 1721880000)
        appendI64LE(into: &buf, 1721880120)
        appendI64LE(into: &buf, 1721880000)

        let stat = try SyncV2Stat.decode(idAndBody: buf)
        #expect(stat.mode == 0o100644)
        #expect(stat.size == 5347282)
        #expect(stat.mtime == 1721880120)
        #expect(stat.isDirectory == false)
    }

    @Test func decodesDirectorySta2Frame() throws {
        var buf = Data()
        buf.append(contentsOf: "STA2".utf8)
        buf.appendU32LE(0)
        buf.append(contentsOf: [UInt8](repeating: 0, count: 16))
        buf.appendU32LE(0o040755)
        buf.appendU32LE(2)
        buf.appendU32LE(0)
        buf.appendU32LE(0)
        appendU64LE(into: &buf, 4096)
        appendI64LE(into: &buf, 0)
        appendI64LE(into: &buf, 1700000000)
        appendI64LE(into: &buf, 0)

        let stat = try SyncV2Stat.decode(idAndBody: buf)
        #expect(stat.isDirectory)
        #expect(stat.mtime == 1700000000)
    }

    @Test func throwsOnSta2WithErrno() throws {
        var buf = Data()
        buf.append(contentsOf: "STA2".utf8)
        buf.appendU32LE(2)
        buf.append(contentsOf: [UInt8](repeating: 0, count: 64))

        #expect(throws: ADBWireError.self) {
            _ = try SyncV2Stat.decode(idAndBody: buf)
        }
    }

    @Test func throwsOnSta2TooShort() {
        let buf = Data("STA2".utf8)
        #expect(throws: ADBWireError.self) {
            _ = try SyncV2Stat.decode(idAndBody: buf)
        }
    }

    @Test func throwsOnSta2WrongId() {
        var buf = Data()
        buf.append(contentsOf: "XXXX".utf8)
        buf.append(contentsOf: [UInt8](repeating: 0, count: 68))
        #expect(throws: ADBWireError.self) {
            _ = try SyncV2Stat.decode(idAndBody: buf)
        }
    }

    @Test func decodesDnt2Frame() throws {
        var buf = Data()
        buf.appendU32LE(0)
        appendU64LE(into: &buf, 0xAB)
        appendU64LE(into: &buf, 0xCD)
        buf.appendU32LE(0o100644)
        buf.appendU32LE(1)
        buf.appendU32LE(1000)
        buf.appendU32LE(1015)
        appendU64LE(into: &buf, 1234)
        appendI64LE(into: &buf, 1700000000)
        appendI64LE(into: &buf, 1700000050)
        appendI64LE(into: &buf, 1700000020)
        let nameBytes = Data("photo.jpg".utf8)
        buf.appendU32LE(UInt32(nameBytes.count))

        #expect(buf.count == SyncV2Dent.bodyAfterId)
        #expect(buf.readU32LE(at: 20) == 0o100644)
        #expect(buf.readU64LE(at: 36) == 1234)
        #expect(buf.readI64LE(at: 52) == 1700000050)
        #expect(buf.readU32LE(at: 68) == UInt32(nameBytes.count))
    }

    @Test func decodesSta1Frame() throws {
        var buf = Data()
        buf.append(contentsOf: "STAT".utf8)
        buf.appendU32LE(0o100755)
        buf.appendU32LE(12345)
        buf.appendU32LE(1700000000)
        let stat = try SyncV1Stat.decode(idAndBody: buf)
        #expect(stat.mode == 0o100755)
        #expect(stat.size == 12345)
        #expect(stat.mtime == 1700000000)
    }

    private func appendU64LE(into buf: inout Data, _ value: UInt64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { buf.append(contentsOf: $0) }
    }

    private func appendI64LE(into buf: inout Data, _ value: Int64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { buf.append(contentsOf: $0) }
    }
}
