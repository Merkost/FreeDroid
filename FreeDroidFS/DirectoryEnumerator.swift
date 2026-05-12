import Foundation
import FSKit
import FreeDroidDomain

actor DirectoryEnumerator {
    private let directory: FreeDroidItem
    private let client: XPCClient
    private var allEntries: [RemoteEntry] = []
    private var fetched = false

    init(directory: FreeDroidItem, client: XPCClient) {
        self.directory = directory
        self.client = client
    }

    func fetchAll() async throws -> [RemoteEntry] {
        if !fetched {
            allEntries = try await client.send(
                .list(deviceID: directory.deviceID, path: directory.entry.path),
                expecting: [RemoteEntry].self
            )
            fetched = true
        }
        return allEntries
    }
}
