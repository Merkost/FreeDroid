import Testing
import Foundation
@testable import FreeDroidADB

@Suite("ADBWireConnection", .serialized)
struct ADBWireConnectionTests {

    @Test func connectAndReceiveOKAY() async throws {
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            let header = (try? readExact(fd: fd, count: 4)) ?? Data()
            let hexLen = String(decoding: header, as: UTF8.self)
            let len = Int(hexLen, radix: 16) ?? 0
            _ = try? readExact(fd: fd, count: len)
            try? writeAll(fd: fd, data: Data("OKAY".utf8))
            close(fd)
        }

        let client = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await client.writeHostMessage("host:version")
        try await client.readOKAY()
        client.cancel()
        stub.stop()
    }

    @Test func failResponseThrows() async throws {
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            let header = (try? readExact(fd: fd, count: 4)) ?? Data()
            let hexLen = String(decoding: header, as: UTF8.self)
            let len = Int(hexLen, radix: 16) ?? 0
            _ = try? readExact(fd: fd, count: len)
            let msg = "unknown host service"
            let hex = String(format: "%04x", msg.utf8.count)
            let resp = Data("FAIL\(hex)\(msg)".utf8)
            try? writeAll(fd: fd, data: resp)
            close(fd)
        }

        let client = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await client.writeHostMessage("host:bad-command")
        await #expect(throws: ADBWireError.self) {
            try await client.readOKAY()
        }
        client.cancel()
        stub.stop()
    }

    @Test func hostFramingUsesHexLength() async throws {
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        let received = ActorBox<Data>(value: Data())

        stub.acceptOne { fd in
            let header = (try? readExact(fd: fd, count: 4)) ?? Data()
            let hexLen = String(decoding: header, as: UTF8.self)
            let len = Int(hexLen, radix: 16) ?? 0
            let body = (try? readExact(fd: fd, count: len)) ?? Data()
            let full = header + body
            Task { await received.set(full) }
            close(fd)
        }

        let client = try await ADBWireConnection.connect(host: "127.0.0.1", port: port)
        try await client.writeHostMessage("host:version")
        client.cancel()

        var waited = 0
        while await received.value.isEmpty && waited < 50 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }

        let data = await received.value
        let str = String(decoding: data, as: UTF8.self)
        #expect(str == "000chost:version")

        stub.stop()
    }
}

actor ActorBox<T: Sendable> {
    var value: T
    init(value: T) { self.value = value }
    func set(_ v: T) { value = v }
}
