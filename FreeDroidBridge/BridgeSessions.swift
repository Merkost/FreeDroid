import Foundation
import FreeDroidADB
import FreeDroidDomain

actor BridgeSessions {
    private let server: ADBServer
    private var sessions: [String: ADBSession] = [:]
    private var serverStarted = false
    private var purgeTask: Task<Void, Never>?

    init() throws {
        self.server = try ADBServer.liveSync()
        ADBFileSync.purgeStaleTempFiles()
        Task { await self.startPurgeTimer() }
    }

    deinit {
        purgeTask?.cancel()
    }

    private func startPurgeTimer() {
        purgeTask?.cancel()
        purgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                if Task.isCancelled { return }
                ADBFileSync.purgeStaleTempFiles()
                _ = self
            }
        }
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
