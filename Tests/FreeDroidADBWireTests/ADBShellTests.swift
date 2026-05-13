import Testing
import Foundation
@testable import FreeDroidADB

@Suite("ADBShellClient", .serialized)
struct ADBShellTests {

    @Test func mkdirReturnsExitZero() async throws {
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            consumeHostMessageFD(fd: fd, reply: "OKAY")
            consumeHostMessageFD(fd: fd, reply: "OKAY")
            sendShellV2OutputFD(fd: fd, stdout: "", stderr: "", exitCode: 0)
            close(fd)
        }

        let shell = ADBShellClient(host: "127.0.0.1", port: port, features: ["shell_v2"])
        let result = try await shell.run(serial: "test-serial", command: "mkdir -p /sdcard/TestDir")
        #expect(result.exitCode == 0)

        stub.stop()
    }

    @Test func shellCapturesStdout() async throws {
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            consumeHostMessageFD(fd: fd, reply: "OKAY")
            consumeHostMessageFD(fd: fd, reply: "OKAY")
            sendShellV2OutputFD(fd: fd, stdout: "hello\n", stderr: "", exitCode: 0)
            close(fd)
        }

        let shell = ADBShellClient(host: "127.0.0.1", port: port, features: ["shell_v2"])
        let result = try await shell.run(serial: "test-serial", command: "echo hello")
        #expect(result.stdout == "hello\n")
        #expect(result.exitCode == 0)

        stub.stop()
    }

    @Test func shellCapturesNonZeroExit() async throws {
        let stub = StubADBServer()
        try stub.start()
        let port = stub.port

        stub.acceptOne { fd in
            consumeHostMessageFD(fd: fd, reply: "OKAY")
            consumeHostMessageFD(fd: fd, reply: "OKAY")
            sendShellV2OutputFD(fd: fd, stdout: "", stderr: "No such file\n", exitCode: 1)
            close(fd)
        }

        let shell = ADBShellClient(host: "127.0.0.1", port: port, features: ["shell_v2"])
        let result = try await shell.run(serial: "test-serial", command: "cat /nonexistent")
        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("No such file"))

        stub.stop()
    }
}

func consumeHostMessageFD(fd: Int32, reply: String) {
    guard let header = try? readExact(fd: fd, count: 4),
          let len = Int(String(decoding: header, as: UTF8.self), radix: 16) else { return }
    _ = try? readExact(fd: fd, count: len)
    try? writeAll(fd: fd, data: Data(reply.utf8))
}

func sendShellV2OutputFD(fd: Int32, stdout: String, stderr: String, exitCode: Int32) {
    if !stdout.isEmpty {
        let data = Data(stdout.utf8)
        var packet = Data([1])
        packet.appendU32LE(UInt32(data.count))
        packet.append(data)
        try? writeAll(fd: fd, data: packet)
    }
    if !stderr.isEmpty {
        let data = Data(stderr.utf8)
        var packet = Data([2])
        packet.appendU32LE(UInt32(data.count))
        packet.append(data)
        try? writeAll(fd: fd, data: packet)
    }
    var exitData = Data()
    var code = UInt32(bitPattern: exitCode).littleEndian
    Swift.withUnsafeBytes(of: &code) { exitData.append(contentsOf: $0) }
    var packet = Data([3])
    packet.appendU32LE(UInt32(exitData.count))
    packet.append(exitData)
    try? writeAll(fd: fd, data: packet)
}
