import Foundation
import Testing
@testable import FreeDroidADB

@Suite("Live device", .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_LIVE_DEVICE"] != nil))
struct LiveDeviceTests {
    @Test func listSdcardRoot() async throws {
        let serial = try await ensureAttachedSerial()
        let conn = try await openSync(serial: serial)
        defer { conn.close() }
        let entries = try await conn.listV2(remotePath: "/sdcard")
        #expect(!entries.isEmpty)
    }

    @Test func statKnownFile() async throws {
        let serial = try await ensureAttachedSerial()
        let conn = try await openSync(serial: serial)
        defer { conn.close() }
        let entry = try await conn.statV2(remotePath: "/system/build.prop")
        #expect(entry.size > 0)
        #expect(entry.mtime > 0)
    }

    @Test func poolReusesConnectionAcrossOps() async throws {
        let serial = try await ensureAttachedSerial()
        let pool = ADBSyncConnectionPool(serial: serial)
        let first = try await pool.withConnection { try await $0.statV2(remotePath: "/system/build.prop") }
        let second = try await pool.withConnection { try await $0.statV2(remotePath: "/system/build.prop") }
        let third = try await pool.withConnection { try await $0.listV2(remotePath: "/sdcard") }
        await pool.drain()
        #expect(first.size > 0)
        #expect(second.size == first.size)
        #expect(!third.isEmpty)
    }

    @Test func sendThenRecvRoundtrip() async throws {
        let serial = try await ensureAttachedSerial()
        let payload = Data((0..<1024 * 1024).map { _ in UInt8.random(in: 0...255) })
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("freedroid-live-\(UUID().uuidString)")
        try payload.write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        let remotePath = "/sdcard/.freedroid-live-\(UUID().uuidString).bin"

        let sender = try await openSync(serial: serial)
        let sentBytes = try await sender.send(from: local, remotePath: remotePath)
        sender.close()
        #expect(sentBytes == Int64(payload.count))

        let downloaded = FileManager.default.temporaryDirectory.appendingPathComponent("freedroid-live-back-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let receiver = try await openSync(serial: serial)
        let receivedBytes = try await receiver.recv(remotePath: remotePath, to: downloaded, progress: nil)
        receiver.close()
        #expect(receivedBytes == Int64(payload.count))
        let readBack = try Data(contentsOf: downloaded)
        #expect(readBack == payload)
    }

    private func ensureAttachedSerial() async throws -> String {
        let server = try await ADBServer.live()
        try await server.start()
        let devices = try await server.listDevices()
        guard let device = devices.first(where: { $0.state == .device }) else {
            Issue.record("No authorized device attached — connect a phone and accept the ADB prompt")
            throw LiveDeviceError.noAttachedDevice
        }
        return device.serial
    }

    private func openSync(serial: String) async throws -> ADBSyncClient {
        try await ADBSyncClient.open(serial: serial)
    }
}

enum LiveDeviceError: Error { case noAttachedDevice }
