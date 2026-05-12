import Testing
import Foundation
@testable import FreeDroidADB

@Suite(
    "ADBServer integration",
    .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_RUN_ADB_INTEGRATION"] == "1")
)
struct ADBServerIntegrationTests {
    @Test func canStartServerAndListDevices() async throws {
        let server = try await ADBServer.live()
        try await server.start()
        let devices = try await server.listDevices()
        #expect(devices.count >= 1, "Expected at least one running emulator/device")
        await server.stop()
    }
}
