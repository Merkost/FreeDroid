import Foundation

struct WifiEndpoint: Codable, Hashable, Sendable {
    let host: String
    let port: Int
    var displayName: String?
    var lastConnected: Date?
}

actor WifiEndpointStore {
    private var endpoints: [WifiEndpoint] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("FreeDroid", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("wifi-endpoints.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.endpoints = (try? Self.load(from: self.fileURL)) ?? []
    }

    func all() -> [WifiEndpoint] {
        endpoints
    }

    func add(_ endpoint: WifiEndpoint) throws {
        guard !endpoints.contains(where: { $0.host == endpoint.host && $0.port == endpoint.port }) else { return }
        endpoints.append(endpoint)
        try persist()
    }

    func remove(_ endpoint: WifiEndpoint) throws {
        endpoints.removeAll { $0.host == endpoint.host && $0.port == endpoint.port }
        try persist()
    }

    func update(lastConnected date: Date, for endpoint: WifiEndpoint) throws {
        guard let idx = endpoints.firstIndex(where: { $0.host == endpoint.host && $0.port == endpoint.port }) else { return }
        endpoints[idx].lastConnected = date
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(endpoints)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> [WifiEndpoint] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([WifiEndpoint].self, from: data)
    }
}
