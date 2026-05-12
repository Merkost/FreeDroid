import Foundation
import FreeDroidADB
import FreeDroidProviderShared

actor ProviderTransport {
    let deviceID: DeviceID
    private var session: ADBSession?
    private var server: ADBServer?

    init(deviceID: DeviceID) {
        self.deviceID = deviceID
    }

    func ensure() async throws -> ADBSession {
        if let session { return session }
        let server = try ADBServer.liveSync()
        try await server.start()
        self.server = server
        let session = ADBSession(deviceID: deviceID, serial: deviceID.raw, server: server)
        self.session = session
        return session
    }

    func invalidate() async {
        session = nil
        server = nil
    }
}
