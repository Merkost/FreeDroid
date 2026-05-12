import Testing
import Foundation
import FreeDroidDomain
@testable import FreeDroidADB

@Suite(
    "ADBSession integration",
    .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_RUN_ADB_INTEGRATION"] == "1")
)
struct ADBSessionIntegrationTests {
    private func makeSession() async throws -> (ADBServer, ADBSession) {
        let server = try await ADBServer.live()
        try await server.start()
        let devices = try await server.listDevices()
        guard let device = devices.first(where: { $0.state == .device }) else {
            throw TransportError.notConnected
        }
        let session = ADBSession(deviceID: DeviceID(raw: device.serial), serial: device.serial, server: server)
        return (server, session)
    }

    @Test func canFetchDeviceInfo() async throws {
        let (server, session) = try await makeSession()
        let deviceInfo = try await session.info
        #expect(!deviceInfo.manufacturer.isEmpty)
        #expect(!deviceInfo.model.isEmpty)
        await server.stop()
    }

    @Test func canListSdcard() async throws {
        let (server, session) = try await makeSession()
        let entries = try await session.list(RemotePath(raw: "/sdcard"))
        #expect(!entries.isEmpty)
        await server.stop()
    }

    @Test func canRoundtripFileWriteReadDelete() async throws {
        let (server, session) = try await makeSession()
        let path = RemotePath(raw: "/sdcard/freedroid-test-\(UUID().uuidString).txt")
        let payload = Data("hello freedroid".utf8)
        try await session.write(path, data: payload, offset: 0)
        let readBack = try await session.read(path, offset: 0, length: 1024)
        #expect(readBack == payload)
        try await session.remove(path)
        await server.stop()
    }
}
