import Foundation
import FreeDroidADB
import FreeDroidDomain

actor BridgeSessions {
    private let server: ADBServer
    private var sessions: [String: ADBSession] = [:]
    private var serverStarted = false

    init() throws {
        self.server = try ADBServer.liveSync()
        ADBFileSync.purgeStaleTempFiles()
    }

    func session(for deviceID: String) async throws -> ADBSession {
        if let existing = sessions[deviceID] { return existing }
        if !serverStarted {
            try await server.start()
            serverStarted = true
        }
        let session = ADBSession(deviceID: DeviceID(raw: deviceID), serial: deviceID, server: server)
        sessions[deviceID] = session
        return session
    }
}
