import Testing
import Foundation
@testable import FreeDroidADB

@Suite("ADBSync LIST_V2", .serialized)
struct ADBSyncListTests {

    @Test func listV2ReturnsParsedEntries() async throws {
        let entries = [
            Dnt2Entry(name: "Documents", mode: 0o040755, size: 4096),
            Dnt2Entry(name: "photo.jpg", mode: 0o100644, size: 1_048_576),
            Dnt2Entry(name: ".hidden", mode: 0o100600, size: 128)
        ]

        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            handleSyncHandshakeFD(fd)
            try? handleListV2RequestFD(fd: fd, entries: entries)
            close(fd)
        }

        let conn = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await conn.writeHostMessage("host:transport:test-serial")
        try await conn.readOKAY()
        try await conn.writeHostMessage("sync:")
        try await conn.readOKAY()

        let syncClient = ADBSyncClient(connection: conn)
        let result = try await syncClient.listV2(remotePath: "/sdcard")

        #expect(result.count == 3)
        #expect(result[0].name == "Documents")
        #expect(result[0].isDirectory == true)
        #expect(result[1].name == "photo.jpg")
        #expect(result[1].isDirectory == false)
        #expect(result[1].size == 1_048_576)
        #expect(result[2].name == ".hidden")

        syncClient.close()
        stub.stop()
    }

    @Test func listV2SkipsDotAndDotDot() async throws {
        let entries = [
            Dnt2Entry(name: ".", mode: 0o040755, size: 4096),
            Dnt2Entry(name: "..", mode: 0o040755, size: 4096),
            Dnt2Entry(name: "real.txt", mode: 0o100644, size: 100)
        ]

        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            handleSyncHandshakeFD(fd)
            try? handleListV2RequestFD(fd: fd, entries: entries)
            close(fd)
        }

        let conn = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await conn.writeHostMessage("host:transport:test-serial")
        try await conn.readOKAY()
        try await conn.writeHostMessage("sync:")
        try await conn.readOKAY()

        let syncClient = ADBSyncClient(connection: conn)
        let result = try await syncClient.listV2(remotePath: "/sdcard")

        #expect(result.count == 1)
        #expect(result[0].name == "real.txt")

        syncClient.close()
        stub.stop()
    }
}

struct Dnt2Entry: Sendable {
    let name: String
    let mode: UInt32
    let size: UInt64
}

func encodeDnt2Entry(_ entry: Dnt2Entry) -> Data {
    var data = Data()
    data.appendU32LE(entry.mode)
    data.appendU32LE(0)
    var s = entry.size.littleEndian
    Swift.withUnsafeBytes(of: &s) { data.append(contentsOf: $0) }
    data.appendU32LE(1000)
    data.appendU32LE(2000)
    var atime: UInt64 = 0
    Swift.withUnsafeBytes(of: &atime) { data.append(contentsOf: $0) }
    var mtime: UInt64 = 1_700_000_000
    Swift.withUnsafeBytes(of: &mtime) { data.append(contentsOf: $0) }
    var ctime: UInt64 = 1_700_000_000
    Swift.withUnsafeBytes(of: &ctime) { data.append(contentsOf: $0) }
    let nameData = Data(entry.name.utf8)
    data.appendU32LE(UInt32(nameData.count))
    data.append(nameData)
    return data
}

func handleListV2RequestFD(fd: Int32, entries: [Dnt2Entry]) throws {
    _ = try readExact(fd: fd, count: 4)
    let lenBytes = try readExact(fd: fd, count: 4)
    let pathLen = lenBytes.readU32LE()
    _ = try readExact(fd: fd, count: Int(pathLen))

    for entry in entries {
        let payload = encodeDnt2Entry(entry)
        var packet = Data()
        packet.append(contentsOf: "DNT2".utf8)
        packet.appendU32LE(UInt32(payload.count))
        packet.append(payload)
        try writeAll(fd: fd, data: packet)
    }

    var done = Data()
    done.append(contentsOf: "DONE".utf8)
    done.appendU32LE(0)
    try writeAll(fd: fd, data: done)
}
