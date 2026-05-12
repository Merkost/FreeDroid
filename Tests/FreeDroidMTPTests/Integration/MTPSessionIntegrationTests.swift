import Testing
import Foundation
import FreeDroidDomain
@testable import FreeDroidMTP

@Suite(
    "MTPSession integration",
    .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_RUN_MTP_INTEGRATION"] == "1")
)
struct MTPSessionIntegrationTests {
    private func makeSession() async throws -> MTPSession {
        let runtime = MTPRuntime()
        let discovery = MTPDeviceDiscovery(runtime: runtime)
        let devices = try await discovery.detect()
        guard let raw = devices.first else { throw TransportError.notConnected }
        return MTPSession(deviceID: DeviceID(raw: raw.identifier), raw: raw)
    }

    @Test func canFetchInfo() async throws {
        let session = try await makeSession()
        let info = try await session.info
        #expect(!info.manufacturer.isEmpty)
        await session.close()
    }

    @Test func canListRoot() async throws {
        let session = try await makeSession()
        let entries = try await session.list(.root)
        #expect(!entries.isEmpty)
        await session.close()
    }

    @Test func canMkdirAndRemove() async throws {
        let session = try await makeSession()
        let path = RemotePath.root.appending("freedroid-test-\(UUID().uuidString)")
        try await session.mkdir(path)
        let entry = try await session.stat(path)
        #expect(entry.kind == .directory)
        try await session.remove(path)
        await session.close()
    }
}
