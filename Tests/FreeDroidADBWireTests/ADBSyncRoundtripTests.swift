import Testing
import Foundation
@testable import FreeDroidADB

@Suite("ADBSync Roundtrip", .serialized)
struct ADBSyncRoundtripTests {

    @Test func recvSmallFile() async throws {
        let fileContent = Data((0..<1024).map { UInt8($0 % 256) })
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            handleSyncHandshakeFD(fd)
            try? handleRecvRequestFD(fd: fd, data: fileContent)
            close(fd)
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("wire-test-recv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }

        let conn = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await conn.writeHostMessage("host:transport:test-serial")
        try await conn.readOKAY()
        try await conn.writeHostMessage("sync:")
        try await conn.readOKAY()

        let syncClient = ADBSyncClient(connection: conn)
        let bytesRead = try await syncClient.recv(remotePath: "/sdcard/test.bin", to: dest, progress: nil)

        #expect(bytesRead == Int64(fileContent.count))
        let written = try Data(contentsOf: dest)
        #expect(written == fileContent)

        syncClient.close()
        stub.stop()
    }

    @Test func recvLargeFile() async throws {
        let size = 5 * 1024 * 1024
        var rng = SystemRandomNumberGenerator()
        let fileContent = Data((0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) })

        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            handleSyncHandshakeFD(fd)
            try? handleRecvRequestFD(fd: fd, data: fileContent)
            close(fd)
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("wire-test-recv-large-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }

        let conn = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await conn.writeHostMessage("host:transport:test-serial")
        try await conn.readOKAY()
        try await conn.writeHostMessage("sync:")
        try await conn.readOKAY()

        let syncClient = ADBSyncClient(connection: conn)
        let bytesRead = try await syncClient.recv(remotePath: "/sdcard/large.bin", to: dest, progress: nil)

        #expect(bytesRead == Int64(fileContent.count))
        let written = try Data(contentsOf: dest)
        #expect(written == fileContent)

        syncClient.close()
        stub.stop()
    }

    @Test func sendAndReceiveRoundtrip() async throws {
        let size = 100 * 1024
        var rng = SystemRandomNumberGenerator()
        let original = Data((0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) })

        let received = ActorBox<Data>(value: Data())

        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            handleSyncHandshakeFD(fd)
            if let data = try? captureDataPacketsFD(fd: fd) {
                Task { await received.set(data) }
            }
            var okayResp = Data("OKAY".utf8)
            okayResp.appendU32LE(0)
            try? writeAll(fd: fd, data: okayResp)
            close(fd)
        }

        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("wire-test-send-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: src) }
        try original.write(to: src)

        let conn = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await conn.writeHostMessage("host:transport:test-serial")
        try await conn.readOKAY()
        try await conn.writeHostMessage("sync:")
        try await conn.readOKAY()

        let syncClient = ADBSyncClient(connection: conn)
        let bytesSent = try await syncClient.send(from: src, remotePath: "/sdcard/out.bin")
        #expect(bytesSent == Int64(original.count))

        syncClient.close()
        try await Task.sleep(for: .milliseconds(300))

        let capturedData = await received.value
        #expect(capturedData == original)

        stub.stop()
    }
}

func handleSyncHandshakeFD(_ fd: Int32) {
    guard let header = try? readExact(fd: fd, count: 4),
          let len = Int(String(decoding: header, as: UTF8.self), radix: 16) else { return }
    _ = try? readExact(fd: fd, count: len)
    try? writeAll(fd: fd, data: Data("OKAY".utf8))

    guard let header2 = try? readExact(fd: fd, count: 4),
          let len2 = Int(String(decoding: header2, as: UTF8.self), radix: 16) else { return }
    _ = try? readExact(fd: fd, count: len2)
    try? writeAll(fd: fd, data: Data("OKAY".utf8))
}

func handleRecvRequestFD(fd: Int32, data: Data) throws {
    _ = try readExact(fd: fd, count: 4)
    let lenBytes = try readExact(fd: fd, count: 4)
    let pathLen = lenBytes.readU32LE()
    _ = try readExact(fd: fd, count: Int(pathLen))

    let chunkSize = 64 * 1024
    var offset = 0
    while offset < data.count {
        let end = min(offset + chunkSize, data.count)
        let chunk = data[offset..<end]
        var packet = Data()
        packet.append(contentsOf: "DATA".utf8)
        packet.appendU32LE(UInt32(chunk.count))
        packet.append(contentsOf: chunk)
        try writeAll(fd: fd, data: packet)
        offset = end
    }

    var done = Data()
    done.append(contentsOf: "DONE".utf8)
    done.appendU32LE(0)
    try writeAll(fd: fd, data: done)
}

func captureDataPacketsFD(fd: Int32) throws -> Data {
    _ = try readExact(fd: fd, count: 4)
    let lenBytes = try readExact(fd: fd, count: 4)
    let argLen = lenBytes.readU32LE()
    _ = try readExact(fd: fd, count: Int(argLen))

    var result = Data()
    while true {
        let id = try readExact(fd: fd, count: 4)
        let lenData = try readExact(fd: fd, count: 4)
        let len = lenData.readU32LE()
        let idStr = String(decoding: id, as: UTF8.self)
        if idStr == "DATA" {
            let chunk = try readExact(fd: fd, count: Int(len))
            result.append(chunk)
        } else if idStr == "DONE" {
            break
        }
    }
    return result
}
